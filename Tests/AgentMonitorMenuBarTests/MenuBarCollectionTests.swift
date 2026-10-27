import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore
@testable import AgentMonitorMenuBar

@Test(.timeLimit(.minutes(1)))
func nativeDefaultCollectionPreservesResourcesWithoutProviderListings() async throws {
    let fixture = NativeCollectionFixture()
    let source = MenuBarCollection.source(reader: { fixture }, clock: fixture, excluding: [])
    let reports = AsyncStream<MonitoringSnapshot>.makeStream()
    let collection = Task {
        defer { reports.continuation.finish() }
        try await source({ .heavy }, LiveInterval(1)) { snapshot in
            reports.continuation.yield(snapshot)
        }
    }
    fixture.ticks.advance()
    var iterator = reports.stream.makeAsyncIterator()
    let first = await iterator.next()
    collection.cancel()
    _ = await collection.result

    let snapshot = try #require(first)
    #expect(snapshot.findings.count == 2)
    #expect(snapshot.findings.allSatisfy { $0.cpuPercent == 100 })
    #expect(snapshot.findings.allSatisfy { $0.attribution.evidence == .runtimeOnly })
    #expect(snapshot.findings.allSatisfy { $0.attribution.threadID == nil && $0.sessionName == nil })
    #expect(fixture.listings.withLock { $0 } == 0)
}

@Test(.timeLimit(.minutes(1)))
@MainActor func nativeCollectionResolvesAndRefreshesSessionsWhilePanelIsClosed() async throws {
    let fixture = NativeCollectionFixture()
    let source = MenuBarCollection.source(
        reader: {
            fixture.readerCreations.withLock { $0 += 1 }
            return fixture
        },
        clock: fixture, registry: fixture, excluding: [])
    let (snapshots, observed) = AsyncStream<MonitoringSnapshot>.makeStream()
    let model = MenuBarModel { thresholds, interval, receive in
        defer { observed.finish() }
        try await source(thresholds, interval) { snapshot in
            try await receive(snapshot)
            observed.yield(snapshot)
        }
    }
    var snapshotsIterator = snapshots.makeAsyncIterator()
    func nextResolved(_ session: String) async throws -> MonitoringSnapshot {
        for _ in 0..<20 {
            for _ in 0..<5 { fixture.ticks.advance() }
            let received = await snapshotsIterator.next(isolation: MainActor.shared)
            let next = try #require(received)
            if next.findings.count == 2, next.findings.allSatisfy({ $0.attribution.threadID == session }) {
                return next
            }
        }
        throw NativeCollectionTestFailure.noResolvedReport
    }
    do {
        model.start()
        fixture.ticks.advance()
        let received = await snapshotsIterator.next(isolation: MainActor.shared)
        let first = try #require(received)
        #expect(first.window?.durationSeconds == 1)
        #expect(first.recentActivity?.units.count == 1)
        let closed = try await nextResolved(NativeCollectionFixture.firstSession)
        #expect(closed.findings.count == 2)
        #expect(closed.window?.durationSeconds == 5)
        expectListedSession(closed, session: NativeCollectionFixture.firstSession)
        #expect(fixture.listings.withLock { $0 } == 1)
        #expect(model.report.snapshot == nil)
        #expect(model.indicator.processCount == 2)

        model.open()
        let opened = try await nextResolved(NativeCollectionFixture.firstSession)
        #expect(opened.recentActivity?.runID == closed.recentActivity?.runID)
        #expect(try #require(opened.recentActivity?.duration) > #require(closed.recentActivity?.duration))
        #expect(opened.recentActivity?.baselineScan == closed.recentActivity?.baselineScan)
        expectListedSession(opened, session: NativeCollectionFixture.firstSession)
        #expect(model.report.snapshot == opened)
        #expect(model.report.groups.count == 1)
        #expect(fixture.listings.withLock { $0 } == 1)

        model.close()
        fixture.session.withLock { $0 = NativeCollectionFixture.secondSession }
        fixture.elapsed.withLock { $0 += 61 }
        let closedAgain = try await nextResolved(NativeCollectionFixture.secondSession)
        expectListedSession(closedAgain, session: NativeCollectionFixture.secondSession)
        #expect(fixture.listings.withLock { $0 } == 2)
        #expect(model.report.snapshot == nil)

        model.open()
        let reopened = try await nextResolved(NativeCollectionFixture.secondSession)
        expectListedSession(reopened, session: NativeCollectionFixture.secondSession)
        #expect(model.report.snapshot == reopened)
        #expect(model.report.groups.count == 1)
        #expect(fixture.listings.withLock { $0 } == 2)
        #expect(fixture.readerCreations.withLock { $0 } == 1)
    } catch {
        await model.stop()
        throw error
    }
    await model.stop()
    #expect(model.error == nil)
}

private func expectListedSession(_ snapshot: MonitoringSnapshot, session: String) {
    #expect(Set(snapshot.findings.map(\.process.pid)) == [42_001, 42_002])
    for finding in snapshot.findings {
        #expect(finding.attribution.provider == .claude)
        #expect(finding.attribution.evidence == .sessionRegistry)
        #expect(finding.attribution.threadID == session)
        #expect(finding.attribution.runtime == NativeCollectionFixture.runtime)
    }
}

private final class NativeCollectionFixture: ProcessReading, AcquisitionClock, SessionRegistryReading,
    Sendable
{
    static let firstSession = "11111111-1111-4111-8111-111111111111"
    static let secondSession = "22222222-2222-4222-8222-222222222222"
    static let runtime = ProcessIdentity(pid: 42_001, startMicroseconds: 1_000)
    let readerCreations = Mutex(0)
    let listings = Mutex(0)
    let elapsed = Mutex(0.0)
    let session = Mutex(firstSession)
    let ticks = CollectionTicks()

    func isCurrent(_ sample: ProcessSample) -> Bool { true }

    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let at = elapsed.withLock { $0 }
        let samples = [
            ProcessSample(
                identity: Self.runtime, parentPID: 1,
                executable: "/Users/test/.local/share/claude/versions/2.1.301", name: "claude",
                terminal: "ttys001", sampledAt: at, cpuSeconds: at, footprintBytes: 2_000_000_000),
            ProcessSample(
                identity: ProcessIdentity(pid: 42_002, startMicroseconds: 2_000), parentPID: Self.runtime.pid,
                executable: "/bin/zsh", name: "zsh", sampledAt: at, cpuSeconds: at,
                footprintBytes: 2_000_000_000),
        ].filter { !excluding.contains($0.identity.pid) }
        return ProcessSnapshot(
            samples: samples, enumeratedCount: samples.count, unreadableCount: 0, listedAt: at,
            scanSeconds: 0, hostCounters: nil, logicalCPUCount: 8
        )
    }

    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        ProcessMetadata(cwd: "/synthetic/project", invocation: sample.name)
    }

    func output(of query: SessionRegistryQuery) throws -> Data {
        #expect(query.command == ["claude", "agents", "--json"])
        listings.withLock { $0 += 1 }
        return try JSONSerialization.data(withJSONObject: [
            ["pid": Int(Self.runtime.pid), "sessionId": session.withLock { $0 }, "status": "busy"]
        ])
    }

    func monotonicNow() -> Double { now().timeIntervalSinceReferenceDate }
    func now() -> Date { Date(timeIntervalSince1970: elapsed.withLock { $0 }) }

    func wait(until deadline: Double, wake: AcquisitionWake) throws {
        let seconds = max(0, deadline - monotonicNow())
        guard ticks.wait(wake: wake) else { return }
        elapsed.withLock { $0 += max(1, seconds) }
    }
}

private final class CollectionTicks: Sendable {
    private struct State {
        var permits = 0
        var waiter: AcquisitionWake?
    }
    private let state = Mutex(State())
    func advance() {
        let wake = state.withLock { state in
            state.permits += 1
            return state.waiter
        }
        wake?.signal()
    }
    func wait(wake: AcquisitionWake) -> Bool {
        let ready = state.withLock { state in
            if state.permits > 0 {
                state.permits -= 1
                return true
            }
            state.waiter = wake
            return false
        }
        if ready { return true }
        wake.wait(seconds: 30)
        return state.withLock { state in
            state.waiter = nil
            guard state.permits > 0 else { return false }
            state.permits -= 1
            return true
        }
    }
}

private enum NativeCollectionTestFailure: Error { case noResolvedReport }

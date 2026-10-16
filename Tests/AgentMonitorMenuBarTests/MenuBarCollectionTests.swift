import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore
@testable import AgentMonitorMenuBar

@Test(.timeLimit(.minutes(1)))
@MainActor func nativeCollectionListsOnlyWhileOpenAndRefreshesDueBindingsOnReopen() async throws {
    let fixture = NativeCollectionFixture()
    let source = MenuBarCollection.source(
        reader: {
            fixture.readerCreations.withLock { $0 += 1 }
            return fixture
        },
        clock: fixture, registry: fixture, excluding: [])
    let (snapshots, observed) = AsyncStream<MonitoringSnapshot>.makeStream()
    let (steps, advance) = AsyncStream<Void>.makeStream()
    let model = MenuBarModel { thresholds, interval, resolveSessions, receive in
        defer { observed.finish() }
        try await source(thresholds, interval, resolveSessions) { snapshot in
            try await receive(snapshot)
            observed.yield(snapshot)
            var iterator = steps.makeAsyncIterator()
            guard await iterator.next() != nil else { throw CancellationError() }
        }
    }
    var snapshotsIterator = snapshots.makeAsyncIterator()
    do {
        model.start()
        let closed = try #require(await snapshotsIterator.next())
        #expect(closed.findings.count == 2)
        #expect(closed.findings.allSatisfy { $0.attribution.evidence == .runtimeOnly })
        #expect(fixture.listings.withLock { $0 } == 0)
        #expect(model.report.snapshot == nil)
        #expect(model.indicator.heavyCount == 2)

        model.open()
        advance.yield(())
        let opened = try #require(await snapshotsIterator.next())
        expectListedSession(opened, session: NativeCollectionFixture.firstSession)
        #expect(model.report.snapshot == opened)
        #expect(model.report.groups.count == 1)
        #expect(fixture.listings.withLock { $0 } == 1)

        model.close()
        fixture.session.withLock { $0 = NativeCollectionFixture.secondSession }
        fixture.elapsed.withLock { $0 += 61 }
        advance.yield(())
        let closedAgain = try #require(await snapshotsIterator.next())
        expectListedSession(closedAgain, session: NativeCollectionFixture.firstSession)
        #expect(fixture.listings.withLock { $0 } == 1)
        #expect(model.report.snapshot == nil)

        model.open()
        advance.yield(())
        let reopened = try #require(await snapshotsIterator.next())
        expectListedSession(reopened, session: NativeCollectionFixture.secondSession)
        #expect(model.report.snapshot == reopened)
        #expect(model.report.groups.count == 1)
        #expect(fixture.listings.withLock { $0 } == 2)
        #expect(fixture.readerCreations.withLock { $0 } == 1)
    } catch {
        advance.finish()
        await model.stop()
        throw error
    }
    advance.finish()
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

private final class NativeCollectionFixture: ProcessReading, SamplingClock, SessionRegistryReading, Sendable {
    static let firstSession = "11111111-1111-4111-8111-111111111111"
    static let secondSession = "22222222-2222-4222-8222-222222222222"
    static let runtime = ProcessIdentity(pid: 42_001, startMicroseconds: 1_000)
    let readerCreations = Mutex(0)
    let listings = Mutex(0)
    let elapsed = Mutex(0.0)
    let session = Mutex(firstSession)

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

    func now() -> Date { Date(timeIntervalSince1970: elapsed.withLock { $0 }) }

    func wait(seconds: Double) async throws {
        try Task.checkCancellation()
        elapsed.withLock { $0 += seconds }
    }
}

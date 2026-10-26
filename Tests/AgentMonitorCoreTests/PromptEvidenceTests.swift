import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private final class PromptFixture: ProcessReading, SamplingClock, Sendable {
    let attempted = Mutex<[ProcessIdentity]>([])
    let allowances = Mutex<[Int]>([])
    let time = Mutex(0.0)
    let readCost: Double
    init(readCost: Double = 0) { self.readCost = readCost }
    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot { diagnosisScan(at: 0) }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        ProcessMetadata(status: .unavailable)
    }
    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        attempted.withLock { $0.append(sample.identity) }
        allowances.withLock { $0.append(maximumBytes) }
        time.withLock { $0 += readCost }
        return ProcessMetadata(
            markers: [SessionMarker(threadID: sessionA, provider: .codex)], status: .markerRead)
    }
    func wait(seconds: Double) async throws {}
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }
    func monotonicNow() -> Double { time.withLock { $0 } }
}

@Suite struct PromptEvidenceTests {
    @Test func churnDoesNotRepeatedlySortThePromptDiscoveryCache() {
        let fixture = PromptFixture()
        var capture = PromptEvidenceCapture()
        let limits = PromptCaptureLimits(attempts: 128, bytes: 128, bytesPerRead: 1, retainedDiscoveries: 128)
        for scan in 0..<1_000 {
            let stable = (1...40).map { sample(Int32($0), at: Double(scan)) }
            let born = (0..<2).map { sample(Int32(100 + scan * 2 + $0), at: Double(scan)) }
            _ = capture.capture(
                stable + born, sequence: UInt64(scan), using: fixture, clock: fixture, limits: limits)
            #expect(capture.retainedDiscoveryCount <= 128)
            #expect(capture.retainedEvictionReferenceCount <= 256)
        }
        #expect(fixture.attempted.withLock { $0.count } == 2_040)
        #expect(capture.evictionSortInputCount < 5_000)
    }

    @Test func missingDiscoveryCannotPinUnboundedOrderReferences() {
        let fixture = PromptFixture()
        var capture = PromptEvidenceCapture()
        let limits = PromptCaptureLimits(retainedDiscoveries: 8)
        _ = capture.capture(
            [sample(1), sample(2)], sequence: 0, using: fixture, clock: fixture, limits: limits)
        for scan in 1...1_000 {
            _ = capture.capture(
                [sample(2)], sequence: UInt64(scan), using: fixture, clock: fixture, limits: limits)
            #expect(capture.retainedEvictionReferenceCount <= 16)
        }
        let returned = capture.capture(
            [sample(1)], sequence: 1_001, using: fixture, clock: fixture, limits: limits)
        #expect(returned.isEmpty)
        #expect(fixture.attempted.withLock { $0.count } == 2)
    }

    @Test(arguments: 0..<100) func promptEvictionMatchesLastSeenSort(seed: Int) {
        let fixture = PromptFixture()
        var capture = PromptEvidenceCapture()
        let limits = PromptCaptureLimits(attempts: 128, bytes: 128, bytesPerRead: 1, retainedDiscoveries: 8)
        var seen: [ProcessIdentity: Int] = [:]
        var random = UInt64(seed + 1)
        func next() -> UInt64 {
            random = random &* 6_364_136_223_846_793_005 &+ 1
            return random >> 32
        }
        for scan in 0..<100 {
            var samples: [ProcessIdentity: ProcessSample] = [:]
            for _ in 0..<Int(next() % 16) {
                let value = sample(Int32(next() % 16 + 1), start: next() % 3, at: Double(scan))
                samples[value.identity] = value
            }
            let expected = Set(samples.keys).subtracting(seen.keys)
            let evidence = capture.capture(
                Array(samples.values), sequence: UInt64(scan), using: fixture, clock: fixture, limits: limits)
            #expect(Set(evidence.map(\.process)) == expected)
            for id in samples.keys { seen[id] = scan }
            let evicted = seen.sorted {
                if $0.value != $1.value { return $0.value < $1.value }
                if $0.key.pid != $1.key.pid { return $0.key.pid < $1.key.pid }
                return $0.key.startMicroseconds < $1.key.startMicroseconds
            }.prefix(max(0, seen.count - 8)).map(\.key)
            for id in evicted { seen[id] = nil }
        }
    }

    @Test func nativePromptCaptureReadsOwnedInvocationWithinTheBufferBound() throws {
        let reader = try NativeProcessReader()
        let pid = ProcessInfo.processInfo.processIdentifier
        let snapshot = try reader.snapshot(processIDs: { [pid] })
        let process = try #require(snapshot.samples.first)
        let captured = try #require(reader.captureLaunchEvidence(for: process, maximumBytes: 65_536))
        #expect(captured.status == .markerRead || captured.status == .notObserved)
        #expect(captured.invocation == CommandLine.arguments.first)
        #expect(captured.command == nil)
        #expect(captured.cwd == nil)
        #expect(captured.writerThreadIDs.isEmpty)
        #expect(captured.listeningSockets.isEmpty)
    }

    enum Budget: CaseIterable { case attempts, bytes }

    @Test(arguments: Budget.allCases)
    func independentBudgetsPreserveDeferredDiscoveryTimes(budget: Budget) throws {
        let fixture = PromptFixture()
        var capture = PromptEvidenceCapture()
        let processes = (1...3).map { sample(Int32($0), at: 10) }
        let limits = PromptCaptureLimits(
            attempts: budget == .attempts ? 2 : 3, bytes: budget == .bytes ? 5 : 12,
            bytesPerRead: 4, elapsedSeconds: 1)
        let first = capture.capture(processes, sequence: 0, using: fixture, clock: fixture, limits: limits)
        #expect(first.filter { $0.status == .captured }.count == 2)
        let expectedAllowances = budget == .attempts ? [4, 4] : [4, 1]
        #expect(fixture.allowances.withLock { $0 } == expectedAllowances)
        #expect(first.map(\.reservedBytes) == expectedAllowances + [0])
        let deferred = try #require(first.first { $0.status == .deferred })
        #expect(deferred.discoveredAt == 10)
        #expect(deferred.metadata == nil)
        let second = capture.capture(processes, sequence: 1, using: fixture, clock: fixture, limits: limits)
        let late = try #require(second.first)
        #expect(late.process == deferred.process)
        #expect(late.discoveredAt == deferred.discoveredAt)
        #expect(late.status == .captured)
        #expect(late.metadata?.markers.first?.threadID == sessionA)
        #expect(fixture.attempted.withLock { $0.count } == 3)
        #expect(second.count == 1)
        #expect(fixture.allowances.withLock { $0 } == expectedAllowances + [4])
    }

    @Test func elapsedBudgetIsCheckedBetweenReadsWithoutClaimingToInterruptOne() {
        let fixture = PromptFixture(readCost: 2)
        var capture = PromptEvidenceCapture()
        let observations = capture.capture(
            [sample(1), sample(2)], sequence: 0, using: fixture, clock: fixture,
            limits: PromptCaptureLimits(elapsedSeconds: 0.01))
        #expect(observations.filter { $0.status == .captured }.count == 1)
        #expect(observations.filter { $0.status == .deferred }.count == 1)
        #expect(fixture.monotonicNow() == 2)
    }

    @Test func changedExecutableAndReusedPIDRequestFreshEvidence() {
        let fixture = PromptFixture()
        var capture = PromptEvidenceCapture()
        _ = capture.capture([sample(1)], sequence: 0, using: fixture, clock: fixture, limits: .init())
        let changed = capture.capture(
            [sample(1, executable: "/other", at: 10)], sequence: 1, using: fixture, clock: fixture,
            limits: .init())
        let reused = capture.capture(
            [sample(1, start: 2)], sequence: 2, using: fixture, clock: fixture, limits: .init())
        #expect(changed.first?.status == .captured)
        #expect(changed.first?.discoveredAt == 10)
        #expect(reused.first?.status == .captured)
        #expect(fixture.attempted.withLock { $0.count } == 3)
    }

    @Test func capturedLaunchEvidenceSurvivesUnavailableBackgroundMetadata() {
        let fixture = PromptFixture()
        let process = sample(1)
        let captured = fixture.captureLaunchEvidence(for: process, maximumBytes: 64)
        let resolved = fixture.metadata(for: process, includeCommand: false, capturedLaunch: captured)
        #expect(resolved.markers.first?.threadID == sessionA)
    }
}

import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private final class PromptFixture: ProcessReading, SamplingClock, Sendable {
    let attempted = Mutex<[ProcessIdentity]>([])
    let time = Mutex(0.0)
    let readCost: Double
    init(readCost: Double = 0) { self.readCost = readCost }
    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot { diagnosisScan(at: 0) }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        ProcessMetadata(status: .unavailable)
    }
    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        attempted.withLock { $0.append(sample.identity) }
        time.withLock { $0 += readCost }
        return ProcessMetadata(
            markers: [SessionMarker(threadID: sessionA, provider: .codex)], status: .markerRead)
    }
    func wait(seconds: Double) async throws {}
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }
    func monotonicNow() -> Double { time.withLock { $0 } }
}

@Suite struct PromptEvidenceTests {
    @Test func nativePromptCaptureReadsOwnedInvocationWithinTheBufferBound() throws {
        let reader = try NativeProcessReader()
        let pid = ProcessInfo.processInfo.processIdentifier
        let snapshot = try reader.snapshot(processIDs: { [pid] })
        let process = try #require(snapshot.samples.first)
        let captured = try #require(reader.captureLaunchEvidence(for: process, maximumBytes: 65_536))
        #expect(captured.status == .markerRead)
        #expect(captured.invocation != nil)
        #expect(captured.command == nil)
        #expect(captured.cwd == nil)
        #expect(captured.writerThreadIDs.isEmpty)
        #expect(captured.listeningSockets.isEmpty)
    }

    @Test func attemptAndByteBudgetsPreserveDeferredDiscoveryTimes() throws {
        let fixture = PromptFixture()
        var capture = PromptEvidenceCapture()
        let processes = (1...3).map { sample(Int32($0), at: 10) }
        let limits = PromptCaptureLimits(attempts: 2, bytes: 8, bytesPerRead: 4, elapsedSeconds: 1)
        let first = capture.capture(processes, sequence: 0, using: fixture, clock: fixture, limits: limits)
        #expect(first.filter { $0.status == .captured }.count == 2)
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

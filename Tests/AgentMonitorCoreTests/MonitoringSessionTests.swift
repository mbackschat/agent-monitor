import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private enum SessionFixtureError: Error { case collection, consumer }

private final class SessionFixture: ProcessReading, SamplingClock, Sendable {
    let events = Mutex<[String]>([])
    let scans = Mutex(0)
    let collected = Mutex<[MonitoringSnapshot]>([])
    let failCollection: Bool
    let cancelWait: Bool

    init(failCollection: Bool = false, cancelWait: Bool = false) {
        self.failCollection = failCollection
        self.cancelWait = cancelWait
    }

    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let index = scans.withLock { value in
            defer { value += 1 }
            return value
        }
        events.withLock { $0.append("scan") }
        if index > 0 && failCollection { throw SessionFixtureError.collection }
        return ProcessSnapshot(
            samples: [sample(42, at: 1 + Double(index) * 2, cpu: Double(index), memory: 1)],
            enumeratedCount: 3, unreadableCount: 2)
    }

    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        events.withLock { $0.append("metadata") }
        return ProcessMetadata(
            marker: SessionMarker(threadID: sessionA), command: includeCommand ? ["worker"] : nil)
    }

    func wait(seconds: Double) async throws {
        events.withLock { $0.append("wait:\(seconds)") }
        if cancelWait { throw CancellationError() }
    }

    func now() -> Date { Date(timeIntervalSince1970: 0) }

    func receive(_ snapshot: MonitoringSnapshot) {
        events.withLock { $0.append("emit") }
        collected.withLock { $0.append(snapshot) }
    }
}

@Test func sessionTakesBaselineAndPublishesNeutralSnapshotsWithBackpressure() async throws {
    let fixture = SessionFixture()
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(intervalSeconds: 2, samples: 2, includeCommands: true),
        reader: fixture, clock: fixture)
    try await session.run { snapshot in fixture.receive(snapshot) }
    #expect(
        fixture.events.withLock { $0 } == [
            "scan", "wait:2.0", "scan", "metadata", "emit", "wait:2.0", "scan", "metadata", "emit",
        ])
    let snapshots = fixture.collected.withLock { $0 }
    #expect(snapshots.count == 2)
    let first = try #require(snapshots.first)
    #expect(first.timestamp == Date(timeIntervalSince1970: 0))
    #expect(first.sampledProcessCount == 1)
    #expect(first.unreadableProcessCount == 2)
    #expect(first.findings.first?.cpuPercent == 50)
    #expect(first.findings.first?.command == ["worker"])
    #expect(first.findings.first?.attribution.threadID == sessionA)
}

@Test func sessionCancellationDuringWaitPublishesNothing() async throws {
    let fixture = SessionFixture(cancelWait: true)
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(), reader: fixture, clock: fixture)
    await #expect(throws: CancellationError.self) {
        try await session.run { fixture.receive($0) }
    }
    #expect(fixture.scans.withLock { $0 } == 1)
    #expect(fixture.collected.withLock { $0.isEmpty })
}

@Test func sessionCollectionFailurePropagatesWithoutEmittingAFalseEmptyReport() async throws {
    let fixture = SessionFixture(failCollection: true)
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(), reader: fixture, clock: fixture)
    await #expect(throws: SessionFixtureError.self) {
        try await session.run { fixture.receive($0) }
    }
    #expect(fixture.collected.withLock { $0.isEmpty })
}

@Test func sessionStopsWhenConsumerFailsEvenInContinuousMode() async throws {
    let fixture = SessionFixture()
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(samples: 0), reader: fixture, clock: fixture)
    await #expect(throws: SessionFixtureError.self) {
        try await session.run { _ in throw SessionFixtureError.consumer }
    }
    #expect(fixture.scans.withLock { $0 } == 2)
}

@Test func sessionRejectsInvalidCadenceAndLimits() {
    #expect(throws: (any Error).self) { try MonitoringConfiguration(intervalSeconds: 0) }
    #expect(throws: (any Error).self) { try MonitoringConfiguration(samples: -1) }
}

@Test func liveThresholdsRecoverOmittedProcessesWithoutRestartingTheBaseline() async throws {
    let fixture = SessionFixture()
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(samples: 4), reader: fixture, clock: fixture)
    let thresholds: @Sendable () async -> Thresholds = {
        switch fixture.collected.withLock({ $0.count }) {
        case 1: Thresholds(cpuPercent: 40, memoryBytes: 1)
        case 2: Thresholds(cpuPercent: 60, memoryBytes: 0)
        default: Thresholds(cpuPercent: 60, memoryBytes: 1)
        }
    }
    try await session.run(thresholds: thresholds) { fixture.receive($0) }
    let snapshots = fixture.collected.withLock { $0 }
    #expect(snapshots.map(\.findings.count) == [0, 1, 1, 0])
    #expect(snapshots.map(\.cpuThresholdPercent) == [60, 40, 60, 60])
    #expect(snapshots.map(\.memoryThresholdBytes) == [1, 1, 0, 1])
    #expect(snapshots[1].findings.first?.cpuPercent == 50)
    #expect(snapshots[1].findings.first?.attribution.threadID == sessionA)
    #expect(fixture.scans.withLock { $0 } == 5)
}

@Test(arguments: [-1.0, Double.infinity, Double.nan])
func sessionRejectsInvalidLiveThresholds(cpu: Double) async throws {
    let fixture = SessionFixture()
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(), reader: fixture, clock: fixture)
    let thresholds: @Sendable () async -> Thresholds = { Thresholds(cpuPercent: cpu) }
    await #expect(throws: MonitoringError.invalidConfiguration) {
        try await session.run(thresholds: thresholds) { fixture.receive($0) }
    }
    #expect(fixture.collected.withLock { $0.isEmpty })
}

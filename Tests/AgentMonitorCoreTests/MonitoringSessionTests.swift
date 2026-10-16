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
    /// Runs inside the first wait, which then lasts until the session cancels it.
    let blockFirstWait: (@Sendable () -> Void)?

    init(
        failCollection: Bool = false, cancelWait: Bool = false, blockFirstWait: (@Sendable () -> Void)? = nil
    ) {
        self.failCollection = failCollection
        self.cancelWait = cancelWait
        self.blockFirstWait = blockFirstWait
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
            enumeratedCount: 3, unreadableCount: 2, listedAt: 1 + Double(index) * 2, scanSeconds: 0)
    }

    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        events.withLock { $0.append("metadata") }
        return ProcessMetadata(
            markers: [SessionMarker(threadID: sessionA, provider: .codex)],
            command: includeCommand ? ["worker"] : nil)
    }

    func wait(seconds: Double) async throws {
        let first = events.withLock { events in
            defer { events.append("wait:\(seconds)") }
            return !events.contains { $0.hasPrefix("wait") }
        }
        if cancelWait { throw CancellationError() }
        if first, let blockFirstWait {
            blockFirstWait()
            try await Task.sleep(for: .seconds(3600))
        }
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

// An unchanged interval costs one wake per sample: a long-lived host must not poll for changes.
@Test func unchangedLiveIntervalWaitsOnce() async throws {
    let fixture = SessionFixture()
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(intervalSeconds: 30, samples: 1), reader: fixture,
        clock: fixture)
    try await session.run(interval: LiveInterval(30), { fixture.receive($0) })
    #expect(fixture.events.withLock { $0 }.filter { $0.hasPrefix("wait") } == ["wait:30.0"])
}

// The TUI can change the interval at any time; the change wakes the waiting session, so a shorter
// one applies without first waiting out the old one, and the snapshot reports the interval used.
@Test func liveIntervalChangeWakesTheWaitAndIsReported() async throws {
    let interval = LiveInterval(30)
    let fixture = SessionFixture(blockFirstWait: { interval.set(0.5) })
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(intervalSeconds: 30, samples: 1), reader: fixture,
        clock: fixture)
    try await session.run(interval: interval, { fixture.receive($0) })
    #expect(fixture.events.withLock { $0 }.filter { $0.hasPrefix("wait") } == ["wait:30.0", "wait:0.5"])
    #expect(fixture.collected.withLock { $0 }.first?.intervalSeconds == 0.5)
}

@Test func invalidLiveIntervalStopsTheSession() async throws {
    let fixture = SessionFixture()
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(samples: 1), reader: fixture, clock: fixture)
    await #expect(throws: MonitoringError.self) {
        try await session.run(interval: LiveInterval(0.01), { fixture.receive($0) })
    }
}

@Test func optionalAgentLoadIncludesProcessesHiddenByReportThresholds() async throws {
    let fixture = SessionFixture()
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(
            thresholds: Thresholds(cpuPercent: 100, memoryBytes: 100), collectAgentLoad: true),
        reader: fixture, clock: fixture)
    try await session.run { fixture.receive($0) }
    let snapshot = try #require(fixture.collected.withLock { $0.first })
    #expect(snapshot.findings.isEmpty)
    let load = try #require(snapshot.agentLoad)
    #expect(load.processCount == 1)
    #expect(load.cpuPercent == 50)
    #expect(load.footprintBytes == 1)
    #expect(load.heavyProcesses == [ProcessIdentity(pid: 42, startMicroseconds: 42)])
    #expect(fixture.events.withLock { $0 }.filter { $0 == "metadata" }.count == 1)
}

@Test func ordinarySamplingDoesNotCollectAnAgentLoadSummary() async throws {
    let fixture = SessionFixture()
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(
            thresholds: Thresholds(cpuPercent: 100, memoryBytes: 100)),
        reader: fixture, clock: fixture)
    try await session.run { fixture.receive($0) }
    #expect(fixture.collected.withLock { $0.first?.agentLoad } == nil)
    #expect(!fixture.events.withLock { $0 }.contains("metadata"))
}

@Test func agentLoadCountsEachLifetimeOnceAndPreservesMissingMeasurements() throws {
    var monitor = Monitor()
    monitor.ingest([
        sample(42, at: 1, cpu: 0, memory: 10), sample(43, at: 1, cpu: 0, memory: 0),
        sample(44, at: 1, cpu: 0, memory: 50),
    ])
    monitor.ingest([
        sample(42, at: 2, cpu: 1, memory: 10), sample(43, at: 2, cpu: 0, memory: 0),
        sample(44, at: 2, cpu: 10, memory: 50), sample(45, at: 2, cpu: nil, memory: nil),
    ])
    monitor.enrich(for: [42, 43, 44, 45].map { ProcessIdentity(pid: $0, startMicroseconds: UInt64($0)) }) {
        sample in
        sample.identity.pid == 44
            ? ProcessMetadata(status: .markerRead)
            : ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)])
    }
    let load = monitor.agentLoad()
    #expect(load.processCount == 3)
    #expect(load.cpuPercent == 100)
    #expect(load.footprintBytes == 10)
    #expect(load.missingCPUCount == 1)
    #expect(load.missingFootprintCount == 1)
    #expect(load.heavyProcesses == [ProcessIdentity(pid: 42, startMicroseconds: 42)])
    monitor.ingest([sample(43, at: 3, cpu: 0, memory: 0)])
    #expect(monitor.agentLoad().processCount == 1)
    #expect(monitor.agentLoad().cpuPercent == 0)
    #expect(monitor.agentLoad().heavyProcesses.isEmpty)
}

private final class SummaryClock: SamplingClock, Sendable {
    let time = Mutex(0.0)
    func now() -> Date { Date(timeIntervalSince1970: time.withLock { $0 }) }
    func wait(seconds: Double) async throws { time.withLock { $0 += seconds } }
}

@Test(arguments: [0.25, 1.0, 15.0, 30.0])
func agentLoadEnrichmentRunsOnFirstSampleThenAtMostEveryFifteenSeconds(interval: Double) async throws {
    let fixture = SessionFixture()
    let clock = SummaryClock()
    let count = Int(30 / interval) + 1
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(
            thresholds: Thresholds(cpuPercent: 100, memoryBytes: 100),
            intervalSeconds: interval, samples: count, collectAgentLoad: true),
        reader: fixture, clock: clock)
    try await session.run { fixture.receive($0) }
    let snapshots = fixture.collected.withLock { $0 }
    let summaryTimes = snapshots.filter { $0.agentLoad != nil }.map { $0.timestamp.timeIntervalSince1970 }
    #expect(
        summaryTimes
            == stride(from: interval, through: Double(count) * interval, by: max(15, interval)).map { $0 })
    #expect(snapshots.count == count)
    #expect(fixture.scans.withLock { $0 } == count + 1)
    #expect(fixture.events.withLock { $0 }.filter { $0 == "metadata" }.count == summaryTimes.count)
}

@Test func summaryCadenceDoesNotSlowHeavyProcessEnrichment() async throws {
    let fixture = SessionFixture()
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(samples: 16, collectAgentLoad: true),
        reader: fixture, clock: SummaryClock())
    try await session.run { fixture.receive($0) }
    let snapshots = fixture.collected.withLock { $0 }
    #expect(snapshots.filter { $0.agentLoad != nil }.count == 2)
    #expect(snapshots.allSatisfy { $0.findings.first?.attribution.threadID == sessionA })
    #expect(fixture.events.withLock { $0 }.filter { $0 == "metadata" }.count == 16)
}

@Test func summaryCadenceRecoversAfterAWallClockRollback() async throws {
    let fixture = SessionFixture()
    let clock = SummaryClock()
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(samples: 4, collectAgentLoad: true),
        reader: fixture, clock: clock)
    try await session.run { snapshot in
        fixture.receive(snapshot)
        if snapshot.timestamp == Date(timeIntervalSince1970: 2) { clock.time.withLock { $0 = -10 } }
    }
    #expect(
        fixture.collected.withLock { $0 }.filter { $0.agentLoad != nil }.map(\.timestamp)
            == [Date(timeIntervalSince1970: 1), Date(timeIntervalSince1970: -9)])
}

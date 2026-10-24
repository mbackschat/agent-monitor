import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private enum WindowFixtureError: Error { case stopped }

private final class WindowReader: ProcessReading, SamplingClock, Sendable {
    struct State {
        var time = 0.0
        var scans = 0
    }
    let state = Mutex(State())
    let failAt: Int?
    let disappearsAt: Int?
    init(failAt: Int? = nil, disappearsAt: Int? = nil) {
        self.failAt = failAt
        self.disappearsAt = disappearsAt
    }
    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        try state.withLock { value in
            if value.scans == failAt { throw WindowFixtureError.stopped }
            let index = value.scans
            value.scans += 1
            let rows =
                disappearsAt.map { index >= $0 } == true
                ? [] : [sample(42, at: value.time, cpu: Double(index) / 100)]
            return diagnosisScan(rows, at: value.time, scan: 0)
        }
    }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)])
    }
    func wait(seconds: Double) async throws {
        try Task.checkCancellation()
        state.withLock { $0.time += seconds }
    }
    func monotonicNow() -> Double { state.withLock { $0.time } }
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }
}

@Suite struct DisplayCadenceTests {
    @Test(arguments: [Thresholds(), Thresholds(memoryBytes: 1_000_000_000)], [1.0, 2.0])
    func fastAcquisitionRetainsWorkerGoneBeforeFirstDisplay(thresholds: Thresholds, displaySeconds: Double)
        async throws
    {
        let reader = WindowReader(disappearsAt: 3)
        let results = Mutex<[MonitoringSnapshot]>([])
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                thresholds: thresholds, intervalSeconds: 0.1, samples: 1, collectAgentLoad: true,
                reportIntervalSeconds: displaySeconds),
            reader: reader, clock: reader)
        try await session.run { result in results.withLock { $0.append(result) } }
        let snapshots = results.withLock { $0 }
        #expect(reader.state.withLock { $0.scans } == Int(displaySeconds * 10) + 1)
        #expect(snapshots.count == 1)
        let snapshot = try #require(snapshots.first)
        let row = try #require(snapshot.findings.first)
        #expect(row.isHistorical)
        #expect(abs(try #require(row.cpuPercent) - 2 / displaySeconds) < 1e-8)
        #expect(row.attribution.threadID == sessionA)
        #expect(snapshot.agentLoad?.footprintBytes == 0)
        #expect(snapshot.agentLoad?.missingFootprintCount == 0)
    }

    @Test func delayedDisplayCoalescesWithoutLosingWorkOrBursting() async throws {
        let reader = WindowReader()
        let results = Mutex<[(MonitoringSnapshot, ContinuousClock.Instant)]>([])
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                intervalSeconds: 0.1, samples: 4, reportIntervalSeconds: 1), reader: reader, clock: reader)
        try await session.run { snapshot in
            results.withLock { $0.append((snapshot, .now)) }
            try await Task.sleep(for: .milliseconds(20))
        }
        let snapshots = results.withLock { $0 }
        #expect(reader.state.withLock { $0.scans } == 41)
        #expect(snapshots.count < 4)
        let seconds = snapshots.compactMap { $0.0.window }.reduce(0.0) { total, window in
            total
                + window.contributions.filter { $0.openingScan >= window.baselineScan }.reduce(0) {
                    $0 + $1.cpuSeconds
                }
        }
        #expect(abs(seconds - 0.4) < 1e-8)
        for pair in zip(snapshots, snapshots.dropFirst()) {
            #expect(pair.0.1.duration(to: pair.1.1) >= .milliseconds(990))
        }
    }

    @Test func acquisitionFailureDrainsAcceptedPartialWindowBeforeError() async throws {
        let reader = WindowReader(failAt: 4)
        let results = Mutex<[MonitoringSnapshot]>([])
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                intervalSeconds: 0.1, samples: 0, reportIntervalSeconds: 1), reader: reader, clock: reader)
        await #expect(throws: WindowFixtureError.self) {
            try await session.run { snapshot in results.withLock { $0.append(snapshot) } }
        }
        let snapshot = try #require(results.withLock { $0.first })
        #expect(snapshot.window?.finalScan == 3)
        #expect(snapshot.findings.first?.accounting?.cpuSeconds == 0.03)
    }
}

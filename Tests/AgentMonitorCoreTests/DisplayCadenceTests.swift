import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private enum WindowFixtureError: Error { case stopped }

private final class WindowReader: ProcessReading, SamplingClock, Sendable {
    struct State {
        var time = 0.0
        var scans = 0
        var waits: [Double] = []
    }
    let state = Mutex(State())
    let firstDelivery = AsyncStream<Void>.makeStream()
    let finalScan = AsyncStream<Void>.makeStream()
    let pauseAfterFirstWindow: Bool
    let failAt: Int?
    let disappearsAt: Int?
    let slowScanAt: Int?
    let expandsAt: Int?
    init(
        failAt: Int? = nil, disappearsAt: Int? = nil, slowScanAt: Int? = nil,
        pauseAfterFirstWindow: Bool = false, expandsAt: Int? = nil
    ) {
        self.expandsAt = expandsAt
        self.pauseAfterFirstWindow = pauseAfterFirstWindow
        self.slowScanAt = slowScanAt
        self.failAt = failAt
        self.disappearsAt = disappearsAt
    }
    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        try state.withLock { value in
            if value.scans == failAt {
                finalScan.continuation.yield(())
                throw WindowFixtureError.stopped
            }
            let index = value.scans
            value.scans += 1
            if index == slowScanAt { value.time += 1.2 }
            var rows =
                disappearsAt.map { index >= $0 } == true
                ? [] : [sample(42, at: value.time, cpu: Double(index) / 100)]
            if expandsAt.map({ index >= $0 }) == true {
                rows += (100..<120).map { sample(Int32($0), at: value.time, cpu: Double(index) / 100) }
            }
            return diagnosisScan(rows, at: value.time, scan: 0)
        }
    }
    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        metadata(for: sample, includeCommand: false)
    }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)], status: .markerRead)
    }
    func wait(seconds: Double) async throws {
        try Task.checkCancellation()
        if pauseAfterFirstWindow, state.withLock({ $0.scans == 11 }) {
            for await _ in firstDelivery.stream { break }
        }
        state.withLock {
            $0.time += seconds
            $0.waits.append(seconds)
        }
    }
    func monotonicNow() -> Double { state.withLock { $0.time } }
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }
}

@Suite struct DisplayCadenceTests {
    @Test func rejectedAccountingScanDrainsOnlyTheLastAcceptedPartial() async throws {
        let reader = WindowReader(expandsAt: 2)
        let reports = Mutex<[MonitoringSnapshot]>([])
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                intervalSeconds: 0.1, samples: 0,
                pipelineLimits: MonitoringPipelineLimits(pendingObservations: 10), reportIntervalSeconds: 5),
            reader: reader, clock: reader)
        await #expect(throws: MonitoringError.overloaded(stage: .accounting, rejectedScan: 2)) {
            try await session.run { report in reports.withLock { $0.append(report) } }
        }
        let delivered = reports.withLock { $0 }
        #expect(delivered.count == 1)
        let report = try #require(delivered.first)
        #expect(report.window?.finalScan == 1)
        #expect(report.cpuAccounting.acquisition?.scanSequence == 1)
        #expect(report.sampledProcessCount == 1)
        #expect(report.window?.contributions.reduce(0) { $0 + $1.cpuSeconds } == 0.01)
    }

    @Test func windowExposesAnOverrunEvenWhenItsFinalScanIsOnTime() async throws {
        let reader = WindowReader(slowScanAt: 3)
        let reports = Mutex<[MonitoringSnapshot]>([])
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                intervalSeconds: 0.1, samples: 2, reportIntervalSeconds: 5),
            reader: reader, clock: reader)
        try await session.run { report in reports.withLock { $0.append(report) } }
        let windows = try reports.withLock { $0 }.compactMap(\.window).map {
            try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) as? [String: Any])
        }
        let coverage = try windows.map { try #require($0["acquisitionCoverage"] as? [String: Any]) }
        #expect(coverage.reduce(0) { $0 + ($1["overrunCount"] as? Int ?? 0) } == 1)
        #expect(abs((coverage.compactMap { $0["maximumGapSeconds"] as? Double }.max() ?? 0) - 1.2) < 1e-9)
        #expect(
            coverage.reduce(0) { $0 + ($1["scanCount"] as? Int ?? 0) } == reader.state.withLock { $0.scans }
                - 1)
    }

    @Test(arguments: [Thresholds(), Thresholds(memoryBytes: 1_000_000_000)], [1.0, 2.0, 5.0])
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
        #expect(reader.state.withLock { $0.scans } == 11)
        #expect(snapshots.count == 1)
        let snapshot = try #require(snapshots.first)
        let row = try #require(snapshot.findings.first)
        #expect(row.isHistorical)
        #expect(abs(try #require(row.cpuPercent) - 2) < 1e-8)
        #expect(row.attribution.threadID == sessionA)
        #expect(snapshot.agentLoad?.footprintBytes == 0)
        #expect(snapshot.agentLoad?.missingFootprintCount == 0)
    }

    @Test(.timeLimit(.minutes(1))) func delayedDisplayCoalescesWithoutLosingWorkOrAddingAnotherPeriod()
        async throws
    {
        let reader = WindowReader(failAt: 41, pauseAfterFirstWindow: true)
        let results = Mutex<[MonitoringSnapshot]>([])
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                intervalSeconds: 0.1, samples: 0, reportIntervalSeconds: 1), reader: reader, clock: reader)
        await #expect(throws: WindowFixtureError.stopped) {
            try await session.run { snapshot in
                let first = results.withLock { value in
                    value.append(snapshot)
                    return value.count == 1
                }
                if first {
                    reader.firstDelivery.continuation.yield(())
                    for await _ in reader.finalScan.stream { break }
                }
            }
        }
        let snapshots = results.withLock { $0 }
        #expect(reader.state.withLock { $0.scans } == 41)
        #expect(reader.state.withLock { $0.waits.count } == 41)
        #expect(abs(reader.monotonicNow() - 4.1) < 1e-9)
        #expect(snapshots.count == 2)
        let seconds = snapshots.compactMap(\.window).reduce(0.0) { total, window in
            total
                + window.contributions.filter { $0.openingScan >= window.baselineScan }.reduce(0) {
                    $0 + $1.cpuSeconds
                }
        }
        #expect(abs(seconds - 0.4) < 1e-8)
    }

    @Test(.timeLimit(.minutes(1))) func workerDepartingDuringSteadyFiveSecondDisplayRemainsAccounted()
        async throws
    {
        let reader = WindowReader(disappearsAt: 25, pauseAfterFirstWindow: true)
        let reports = Mutex<[MonitoringSnapshot]>([])
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                intervalSeconds: 0.1, samples: 2, reportIntervalSeconds: 5), reader: reader, clock: reader)
        try await session.run { snapshot in
            reports.withLock { $0.append(snapshot) }
            reader.firstDelivery.continuation.yield(())
        }
        let values = reports.withLock { $0 }
        #expect(values.count == 2)
        let last = try #require(values.last)
        #expect(abs(try #require(last.window?.durationSeconds) - 5) < 1e-9)
        let row = try #require(last.findings.first)
        #expect(row.isHistorical)
        #expect(abs(try #require(row.accounting?.cpuSeconds) - 0.14) < 1e-9)
        #expect(row.footprintBytes == nil)
        #expect(
            abs(values.compactMap(\.window).flatMap(\.contributions).reduce(0) { $0 + $1.cpuSeconds } - 0.24)
                < 1e-9)
    }

    @Test(arguments: [1.5, 5.0])
    func finiteCollectionDrainsWholeUnitsWhenCadenceDoesNotDivideTheDisplay(display: Double) async throws {
        let reader = WindowReader()
        let reports = Mutex<[MonitoringSnapshot]>([])
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                intervalSeconds: 0.3, samples: 2, scope: .allProcesses, reportIntervalSeconds: display),
            reader: reader, clock: reader)
        try await session.run { report in reports.withLock { $0.append(report) } }
        let scans = reader.state.withLock { $0.scans }
        let values = reports.withLock { $0 }
        #expect(values.last?.window?.finalScan == UInt64(scans - 1))
        #expect(
            abs(
                values.compactMap(\.window).flatMap(\.contributions).reduce(0) { $0 + $1.cpuSeconds }
                    - Double(scans - 1) / 100) < 1e-9)
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

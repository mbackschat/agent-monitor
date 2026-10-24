import Foundation
import Testing

@testable import AgentMonitorCore

@Test func collapsedCoverageRetainsProvenExcludedWorkerCounts() throws {
    var ledger = CounterLedger()
    var monitor = Monitor()
    var window = AccountingWindow(baseline: ledger.ingest([sample(42, at: 0, cpu: 0)], listedAt: 0))
    for tick in 1...4 {
        let values = tick.isMultiple(of: 2) ? [] : [sample(42, at: Double(tick), cpu: nil)]
        let source = diagnosisScan(values, at: Double(tick))
        let scan = ledger.ingest(values, listedAt: source.listedAt)
        monitor.ingest(source, accounting: scan)
        try window.append(scan, rows: monitor.findings(scope: .allProcesses))
        if tick.isMultiple(of: 2) { window.compact(to: MonitoringPipelineLimits(pendingObservations: 1)) }
    }
    #expect(window.summary.unmeasuredLifetimeCount == 1)
    #expect(window.summary.excludedObservationCount == 2)
    let object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(window.summary)) as? [String: Any])
    let bounds = try #require(object["unmeasuredLifetimeCountRange"] as? [String: Int])
    #expect(bounds == ["minimum": 1, "maximum": 2])
}

@Test func failedPIDChurnKeepsExactObservationTotalsWithBoundedIdentityDetail() {
    var coverage = ReadCoverage()
    for tick in 0..<60 {
        let outcomes = (0..<100).map {
            NativeCounterOutcome(
                pid: Int32(tick * 100 + $0), identity: nil,
                operation: .bsdInfo, status: .lookupUnavailable, failure: nil, observedAtTicks: UInt64(tick))
        }
        coverage.append(
            ProcessSnapshot(
                samples: [], enumeratedCount: 100, unreadableCount: 100,
                listedAt: Double(tick), scanSeconds: 0, hostCounters: nil, logicalCPUCount: 1,
                nativeOutcomes: outcomes))
    }
    #expect(coverage.retainedCount <= 1_024)
    #expect(coverage.failedPIDObservations == 6_000)
    #expect(coverage.meanFailedPIDsPerScan == 100)
    #expect(coverage.maximumFailedPIDsPerScan == 100)
    #expect(coverage.failedPIDCount.minimum <= 6_000)
    #expect(coverage.failedPIDCount.maximum >= 6_000)
    #expect(coverage.releasedAll != nil)
    #expect(coverage.startedAt == 0)
    #expect(coverage.endedAt == 59)
}

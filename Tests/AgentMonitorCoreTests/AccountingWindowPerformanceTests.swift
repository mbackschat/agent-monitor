import Foundation
import Testing

@testable import AgentMonitorCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["ACCOUNTING_WINDOW_MEASUREMENT_PATH"] != nil))
func measureDisplayWindowAggregationWithChurn() throws {
    let path = try #require(ProcessInfo.processInfo.environment["ACCOUNTING_WINDOW_MEASUREMENT_PATH"])
    var results: [[String: Any]] = []
    for count in [150, 1_000] {
        let rows = (1...count).map { index in
            let identity = ProcessIdentity(pid: Int32(42_000 + index), startMicroseconds: UInt64(index))
            return HeavyProcess(
                process: identity, executable: "/fake/worker", name: "worker", cpuPercent: nil,
                footprintBytes: 1_000_000, cwd: "/fake/project", command: nil, metadataStatus: .markerRead,
                attribution: Attribution(
                    provider: .codex, evidence: .marker, context: .unverified,
                    threadID: sessionA, rootSessionID: nil, runtime: nil, terminal: nil,
                    runtimeDirectory: nil,
                    candidateThreadIDs: [], ancestry: [identity]))
        }
        var durations: [Double] = []
        for _ in 0..<3 {
            var ledger = CounterLedger()
            func samples(_ tick: Int) -> [ProcessSample] {
                rows.prefix(tick > 5 ? count * 4 / 5 : count).map { row in
                    ProcessSample(
                        identity: row.process, parentPID: 1, executable: row.executable, name: row.name,
                        sampledAt: Double(tick) / 10, cpuSeconds: Double(tick) / 1000,
                        footprintBytes: row.footprintBytes)
                }
            }
            let baseline = ledger.ingest(samples(0), listedAt: 0)
            let scans = (1...10).map { tick in ledger.ingest(samples(tick), listedAt: Double(tick) / 10) }
            let start = ContinuousClock.now
            var window = AccountingWindow(baseline: baseline)
            for scan in scans { try window.append(scan, rows: Array(rows.prefix(scan.observations.count))) }
            let projection = try window.projection(scope: .agentsOnly)
            let findings = projection.rows
            let summary = projection.summary
            let elapsed = start.duration(to: .now).components
            durations.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
            #expect(findings.count == count)
            #expect(findings.filter(\.isHistorical).count == count / 5)
            let expected = Double(count) * 0.009
            #expect(abs(summary.contributions.reduce(0) { $0 + $1.cpuSeconds } - expected) < 1e-8)
            #expect(abs(findings.compactMap { $0.accounting?.cpuSeconds }.reduce(0, +) - expected) < 1e-8)
            #expect(window.payloadSize.observations <= MonitoringPipelineLimits().pendingObservations)
        }
        results.append([
            "processes": count, "scansPerWindow": 10, "historicalProcesses": count / 5,
            "milliseconds": durations, "maximumMilliseconds": 200,
        ])
        #expect(try #require(durations.max()) < 200)
    }
    try JSONSerialization.data(
        withJSONObject: [
            "date": String(Date().ISO8601Format().prefix(10)), "build": "debug", "runs": results,
        ],
        options: [.prettyPrinted, .sortedKeys]
    )
    .write(to: URL(fileURLWithPath: path))
}

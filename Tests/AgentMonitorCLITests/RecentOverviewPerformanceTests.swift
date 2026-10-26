import AgentMonitorPresentation
import Darwin
import Foundation
import Testing

@testable import AgentMonitorCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["RECENT_OVERVIEW_PERFORMANCE_PATH"] != nil))
func compactRecentHistoryFitsOneMinuteAtTenScansPerSecond() throws {
    let path = try #require(ProcessInfo.processInfo.environment["RECENT_OVERVIEW_PERFORMANCE_PATH"])
    var results: [[String: Any]] = []
    for count in [90, 613] {
        var ledger = CounterLedger()
        let store = RecentActivityStore()
        func samples(_ tick: Int) -> [ProcessSample] {
            (1...count).map { index in
                ProcessSample(
                    identity: ProcessIdentity(pid: Int32(index), startMicroseconds: UInt64(index)),
                    parentPID: 0, executable: "/usr/local/bin/node", name: "node",
                    sampledAt: Double(tick) / 10, cpuSeconds: Double(tick) / 1000,
                    footprintBytes: 10_000_000)
            }
        }
        func rows(_ values: [ProcessSample]) -> [HeavyProcess] {
            values.map { sample in
                HeavyProcess(
                    process: sample.identity, executable: sample.executable, name: sample.name,
                    cpuPercent: nil, footprintBytes: sample.footprintBytes, cwd: "/fixture/project",
                    command: nil,
                    metadataStatus: .markerRead,
                    attribution: Attribution(
                        provider: .codex, evidence: .marker,
                        context: .unverified, threadID: "session-\(sample.identity.pid % 20)",
                        rootSessionID: nil,
                        runtime: nil, terminal: nil, runtimeDirectory: nil, candidateThreadIDs: [],
                        ancestry: []))
            }
        }
        var baseline = ledger.ingest(samples(0), listedAt: 0)
        var elapsed: [Double] = []
        var projectionTimes: [Double] = []
        var overview = ContributorOverview()
        var usage = rusage()
        _ = getrusage(RUSAGE_SELF, &usage)
        let rssBefore = usage.ru_maxrss
        let begin = ContinuousClock.now
        for unit in 0..<60 {
            var accumulator = AccountingWindow(baseline: baseline)
            for offset in 1...10 {
                let tick = unit * 10 + offset
                let values = samples(tick)
                let scan = ledger.ingest(values, listedAt: Double(tick) / 10)
                let findings = rows(values)
                let started = ContinuousClock.now
                try accumulator.append(scan, rows: findings)
                _ = accumulator.payloadSize
                elapsed.append(milliseconds(started.duration(to: .now)))
                baseline = scan
            }
            store.append(
                accumulator.seal(scope: .allProcesses), current: accumulator.current,
                present: accumulator.present)
            let recent = try #require(store.snapshot())
            let snapshot = MonitoringSnapshot(
                cpuAccounting: CPUAccounting(
                    hostBusyPercent: nil, logicalCPUCount: 8,
                    measuredUserPercent: 0, unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
                timestamp: Date(),
                intervalSeconds: 0.1, cpuThresholdPercent: 0, memoryThresholdBytes: 0,
                sampledProcessCount: count, unreadableProcessCount: 0, findings: [], recentActivity: recent)
            let started = ContinuousClock.now
            overview.receive(snapshot)
            projectionTimes.append(milliseconds(started.duration(to: .now)))
        }
        let recent = try #require(store.snapshot())
        #expect(recent.duration == 60)
        #expect(recent.units.flatMap(\.records).count == count)
        #expect(!recent.retentionLimited)
        #expect(abs(recent.cpuSeconds - Double(count) * 0.6) < 1e-6)
        _ = getrusage(RUSAGE_SELF, &usage)
        let p95 = elapsed.sorted()[Int(Double(elapsed.count - 1) * 0.95)]
        let projectionP95 = projectionTimes.sorted()[Int(Double(projectionTimes.count - 1) * 0.95)]
        #expect(p95 < 50)
        #expect(projectionP95 < 200)
        results.append([
            "processes": count, "scans": 600, "unitRecords": recent.units.flatMap(\.records).count,
            "chargedRecords": store.retainedPayloadSize.observations,
            "chargedTextBytes": store.retainedPayloadSize.textBytes,
            "acquisitionAggregationP95Ms": p95, "projectionP95Ms": projectionP95,
            "elapsedMs": milliseconds(begin.duration(to: .now)), "peakRSSBefore": rssBefore,
            "peakRSSAfter": usage.ru_maxrss,
        ])
    }
    try JSONSerialization.data(
        withJSONObject: ["date": Date().ISO8601Format(), "runs": results],
        options: [.prettyPrinted, .sortedKeys]
    )
    .write(to: URL(fileURLWithPath: path))
}

private func milliseconds(_ value: Duration) -> Double {
    Double(value.components.seconds) * 1000 + Double(value.components.attoseconds) / 1e15
}

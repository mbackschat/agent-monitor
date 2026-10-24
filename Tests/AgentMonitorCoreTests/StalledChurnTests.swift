import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct StalledChurnTests {
    @Test(arguments: [60, 600], [0, 5, 50])
    func stalledConsumerConservesStableAndChurningWork(seconds: Int, birthsPerSecond: Int) async throws {
        let limits = MonitoringPipelineLimits()
        var ledger = CounterLedger()
        var expected = 0.0
        var expectedIntervals = 0
        let ancestry = (0..<8).map { ProcessIdentity(pid: Int32(100_000 + $0), startMicroseconds: 1) }
        func population(_ unit: Int, _ tick: Int) -> [ProcessSample] {
            let time = Double(tick) / 10
            let ids = Array(1...1_000) + (0..<birthsPerSecond).map { 10_000 + unit * birthsPerSecond + $0 }
            return ids.map { sample(Int32($0), at: time, cpu: time / 100, memory: UInt64($0)) }
        }
        let baselineRows = population(0, 0)
        var baseline = ledger.ingest(baselineRows, listedAt: 0)
        let channel = MonitoringChannel<AccountingWindow>(
            stage: .presentation, limits: limits,
            coalesce: { old, new in
                try old.merge(new)
                old.compact(to: MonitoringPipelineLimits())
                return old.payloadSize
            })
        for unit in 0..<seconds {
            var window = AccountingWindow(baseline: baseline)
            let findings = population(unit, unit * 10).map { sample in
                HeavyProcess(
                    process: sample.identity, executable: sample.executable, name: sample.name,
                    cpuPercent: nil, footprintBytes: sample.footprintBytes,
                    kernelPeakFootprintBytes: nil, cwd: nil, command: nil, metadataStatus: .markerRead,
                    attribution: Attribution(
                        provider: .codex, evidence: .marker, context: .unverified,
                        threadID: sessionA, rootSessionID: nil, runtime: nil, terminal: nil,
                        runtimeDirectory: nil, candidateThreadIDs: [],
                        ancestry: ancestry))
            }
            for offset in 1...10 {
                let tick = unit * 10 + offset
                let rows = population(unit, tick)
                let scan = ledger.ingest(rows, listedAt: Double(tick) / 10)
                expected += scan.contributions.reduce(0) { $0 + $1.cpuSeconds }
                expectedIntervals += scan.contributions.reduce(0) { $0 + $1.intervalCount }
                try window.append(scan, rows: findings)
                baseline = scan
            }
            try await channel.send(window, size: window.payloadSize, sequence: window.final.id.sequence)
        }
        let value = try #require(await channel.next())
        let summary = value.summary
        let json = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as? [String: Any])
        let collapsed = json["collapsedContributions"] as? [[String: Any]] ?? []
        let collapsedCPU = collapsed.reduce(0) { $0 + ($1["cpuSeconds"] as? Double ?? 0) }
        #expect(abs(summary.contributions.reduce(0) { $0 + $1.cpuSeconds } + collapsedCPU - expected) < 1e-6)
        let unit = value.seal(scope: .allProcesses)
        let retainedCount = Set(unit.records.map(\.category.process)).count
        var bounds = LifetimeCountRange(minimum: retainedCount, maximum: retainedCount)
        for record in summary.collapsedContributions { bounds.union(record.workerCount) }
        let actualWorkers = 1_000 + seconds * birthsPerSecond
        #expect(bounds.minimum <= actualWorkers)
        #expect(bounds.maximum >= actualWorkers)
        #expect(
            summary.contributions.reduce(0) { $0 + $1.intervalCount }
                + summary.collapsedContributions.reduce(0) { $0 + $1.intervalCount } == expectedIntervals)
        let maximum =
            (unit.records.compactMap { $0.maximumFootprint?.bytes }
            + summary.collapsedContributions.compactMap { $0.maximumFootprint?.bytes }).max()
        #expect(maximum == UInt64(birthsPerSecond == 0 ? 1_000 : 10_000 + seconds * birthsPerSecond - 1))
        #expect(value.payloadSize.observations <= limits.pendingObservations)
        #expect(value.payloadSize.textBytes <= limits.pendingTextBytes)
        #expect(value.present.count == 1_000 + birthsPerSecond)
        if seconds == 600, birthsPerSecond > 0 { #expect(!collapsed.isEmpty) }
    }
}

@Test func collapsedWorkerReappearanceKeepsExactResourcesAndProvenCounts() throws {
    var ledger = CounterLedger()
    var monitor = Monitor()
    let initial = diagnosisScan([sample(42, at: 0, cpu: 0)], at: 0)
    let baseline = ledger.ingest(initial.samples, listedAt: 0)
    monitor.ingest(initial, accounting: baseline)
    var window = AccountingWindow(baseline: baseline)
    for tick in 1...4 {
        let samples =
            tick.isMultiple(of: 2)
            ? [] : [sample(42, at: Double(tick), cpu: Double(tick), memory: tick == 1 ? 100 : 80)]
        let source = diagnosisScan(samples, at: Double(tick))
        let counters = ledger.ingest(samples, listedAt: Double(tick))
        monitor.ingest(source, accounting: counters)
        monitor.enrich(
            ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]),
            for: ProcessIdentity(pid: 42, startMicroseconds: 42))
        try window.append(counters, rows: monitor.findings(scope: .allProcesses))
        if tick.isMultiple(of: 2) { window.compact(to: MonitoringPipelineLimits(pendingObservations: 1)) }
    }
    let value = try #require(window.summary.collapsedContributions.first)
    #expect(value.cpuSeconds == 3)
    #expect(value.intervalCount == 2)
    #expect(value.missingReadIntervalCount == 1)
    #expect(value.maximumFootprint?.bytes == 100)
    #expect(value.processCount == LifetimeCountRange(minimum: 1, maximum: 2))
    #expect(value.workerCount == LifetimeCountRange(minimum: 1, maximum: 2))
    #expect(value.startedAt == 0)
    #expect(value.endedAt == 3)
    #expect(window.summary.contributions.isEmpty)
    #expect(window.present.isEmpty)
    #expect(AgentLoadSummary(processes: [], window: window.summary).cpuPercent == 75)
}

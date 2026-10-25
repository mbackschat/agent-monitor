import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct AccountingWindowTests {
    @Test func vanishedWorkerContributesToWholeWindowWithoutCurrentMemory() throws {
        var ledger = CounterLedger()
        let baseline = ledger.ingest([sample(42, at: 0, cpu: 0)], listedAt: 0)
        var window = AccountingWindow(baseline: baseline)
        var monitor = Monitor()
        let first = ledger.ingest([sample(42, at: 0.1, cpu: 0.08)], listedAt: 0.1)
        monitor.ingest(diagnosisScan([sample(42, at: 0.1, cpu: 0.08)], at: 0.1), accounting: first)
        monitor.enrich(
            ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]),
            for: first.observations[0].id.process)
        try window.append(first, rows: monitor.findings(scope: .allProcesses))
        try window.append(ledger.ingest([], listedAt: 1), rows: [])
        let row = try #require(try window.findings(scope: .agentsOnly).first)
        #expect(abs(try #require(row.cpuPercent) - 8) < 1e-9)
        #expect(row.isHistorical)
        #expect(row.footprintBytes == nil)
        #expect(row.accounting?.cpuSeconds == 0.08)
        #expect(row.attribution.threadID == sessionA)
        #expect(window.summary.contributions.count == 1)
    }

    @Test func coalescingRecomputesRecoveryAndRejectsOverlappingAdmission() throws {
        var ledger = CounterLedger()
        let zero = ledger.ingest([sample(42, at: 0, cpu: 0)], listedAt: 0)
        let missing = ledger.ingest([], listedAt: 1)
        let recovered = ledger.ingest([sample(42, at: 2, cpu: 1)], listedAt: 2)
        var monitor = Monitor()
        monitor.ingest(diagnosisScan(recovered.observations.map(\.sample), at: 2), accounting: recovered)
        let rows = monitor.findings(scope: .allProcesses)
        var earlier = AccountingWindow(baseline: zero)
        try earlier.append(missing, rows: [])
        var later = AccountingWindow(baseline: missing)
        try later.append(recovered, rows: rows)
        #expect(try later.findings(scope: .allProcesses).first?.cpuPercent == nil)
        #expect(try later.findings(scope: .allProcesses).first?.accounting?.recoveredCPUSeconds == 1)
        try earlier.merge(later)
        #expect(throws: CounterWindowError.self) { try earlier.merge(later) }
        let row = try #require(try earlier.findings(scope: .allProcesses).first)
        #expect(row.cpuPercent == 50)
        #expect(row.accounting?.recoveredCPUSeconds == 0)
        #expect(earlier.summary.contributions.count == 1)
    }
    @Test func currentMemoryCannotBeAssignedToAnEarlierSession() throws {
        var ledger = CounterLedger()
        var monitor = Monitor()
        let baseline = ledger.ingest([sample(42, at: 0, cpu: 0)], listedAt: 0)
        var window = AccountingWindow(baseline: baseline)
        for (time, cpu, session) in [(0.5, Optional(0.1), sessionA), (1.0, nil, sessionB)] {
            let scan = diagnosisScan([sample(42, at: time, cpu: cpu)], at: time)
            let counters = ledger.ingest(scan.samples, listedAt: time)
            monitor.ingest(scan, accounting: counters)
            monitor.enrich(
                ProcessMetadata(markers: [SessionMarker(threadID: session, provider: .codex)]),
                for: scan.samples[0].identity)
            try window.append(counters, rows: monitor.findings(scope: .allProcesses))
        }
        let row = try #require(try window.findings(scope: .agentsOnly).first)
        #expect(row.attribution.threadID == sessionB)
        #expect(row.attribution.evidence == .marker)
        #expect(row.accounting?.labelChangedInWindow == true)
        #expect(row.accounting?.pointCandidateCPUSeconds == 0.1)
        #expect(row.accounting?.uncertainCPUSeconds == 0)
        #expect(window.summary.contributions.first?.attribution.threadID == sessionA)
    }

    @Test func agentSummaryKeepsKnownCPUWithoutAssigningUnknownWork() throws {
        var ledger = CounterLedger()
        var monitor = Monitor()
        var window = AccountingWindow(baseline: ledger.ingest([sample(42, at: 0, cpu: 0)], listedAt: 0))
        for tick in 1...2 {
            let time = Double(tick) / 2
            let scan = diagnosisScan([sample(42, at: time, cpu: Double(tick) / 10)], at: time)
            let counters = ledger.ingest(scan.samples, listedAt: time)
            monitor.ingest(scan, accounting: counters)
            monitor.enrich(
                ProcessMetadata(
                    markers: tick == 1 ? [SessionMarker(threadID: sessionA, provider: .codex)] : [],
                    status: .markerRead), for: scan.samples[0].identity)
            try window.append(counters, rows: monitor.findings(scope: .allProcesses))
        }
        let rows = try window.findings(scope: .agentsOnly)
        #expect(rows.count == 1)
        #expect(rows.first?.attribution.provider == nil)
        #expect(rows.first?.cpuPercent == 20)
        let load = AgentLoadSummary(processes: rows, window: window.summary)
        #expect(load.processCount == 1)
        #expect(load.cpuPercent == 10)
        #expect(load.footprintBytes == 0)
    }

    @Test func exportedContributionsRespectScopeWhileHostContextKeepsAllUserCPU() throws {
        var ledger = CounterLedger()
        let initial = [sample(42, at: 0, cpu: 0), sample(43, at: 0, cpu: 0)]
        var window = AccountingWindow(baseline: ledger.ingest(initial, listedAt: 0))
        let scan = diagnosisScan([sample(42, at: 1, cpu: 0.1), sample(43, at: 1, cpu: 0.1)], at: 1)
        let counters = ledger.ingest(scan.samples, listedAt: 1)
        var monitor = Monitor()
        monitor.ingest(scan, accounting: counters)
        monitor.enrich(
            ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]),
            for: initial[0].identity)
        try window.append(counters, rows: monitor.findings(scope: .allProcesses))
        let projection = try window.projection(scope: .agentsOnly)
        #expect(projection.rows.map(\.process.pid) == [42])
        #expect(projection.summary.contributions.map(\.process.pid) == [42])
        #expect(projection.counters.cpuSeconds == 0.2)
        #expect(try window.projection(scope: .allProcesses).summary.contributions.count == 2)
    }

    @Test func collapsedMixedLabelsKeepScopeWithoutReassigningUnknownCPU() throws {
        var ledger = CounterLedger()
        var monitor = Monitor()
        var window = AccountingWindow(baseline: ledger.ingest([sample(42, at: 0, cpu: 0)], listedAt: 0))
        for tick in 1...2 {
            let source = diagnosisScan([sample(42, at: Double(tick), cpu: Double(tick))], at: Double(tick))
            let scan = ledger.ingest(source.samples, listedAt: source.listedAt)
            monitor.ingest(source, accounting: scan)
            if tick == 2 {
                monitor.enrich(
                    ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]),
                    for: source.samples[0].identity)
            }
            try window.append(scan, rows: monitor.findings(scope: .allProcesses))
        }
        try window.append(ledger.ingest([], listedAt: 3), rows: [])
        window.compact(to: MonitoringPipelineLimits(pendingObservations: 2))
        let summary = try window.projection(scope: .agentsOnly).summary
        #expect(summary.collapsedContributions.reduce(0) { $0 + $1.cpuSeconds } == 2)
        #expect(window.seal(scope: .agentsOnly).collapsedContributions.reduce(0) { $0 + $1.cpuSeconds } == 2)
        #expect(abs(AgentLoadSummary(processes: [], window: summary).cpuPercent - 100.0 / 3) < 1e-9)
    }

}

import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct CoverageStatusTests {
    private func snapshot(
        _ statuses: [NativeCounterStatus] = [], achievedPeriod: Double = 0.1,
        unmeasured: Int = 0, unmeasuredRange: LifetimeCountRange? = nil
    ) throws
        -> MonitoringSnapshot
    {
        var ledger = CounterLedger()
        let baseline = ledger.ingest([], listedAt: 0)
        let source = ProcessSnapshot(
            samples: [], enumeratedCount: statuses.count, unreadableCount: statuses.count,
            listedAt: achievedPeriod, scanSeconds: 0, hostCounters: nil, logicalCPUCount: 8,
            nativeOutcomes: statuses.enumerated().map {
                NativeCounterOutcome(
                    pid: Int32(40 + $0.offset), identity: nil, operation: .bsdInfo, status: $0.element,
                    failure: nil, observedAtTicks: 1)
            })
        let scan = ledger.ingest([], listedAt: achievedPeriod, source: source)
        var window = AccountingWindow(baseline: baseline)
        try window.append(
            scan, rows: [],
            timing: AcquisitionTiming(
                runID: scan.id.runID, scanSequence: scan.id.sequence, qualityOfService: .userInitiated,
                requestedPeriodSeconds: 0.1, achievedPeriodSeconds: achievedPeriod,
                scanWorkSeconds: 0, resolutionDelaySeconds: 0))
        return MonitoringSnapshot(
            cpuAccounting: CPUAccounting(
                hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
                unmeasuredLifetimeCount: unmeasured, previousScanSeconds: nil,
                unmeasuredLifetimeCountRange: unmeasuredRange),
            timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 0.1, cpuThresholdPercent: 0,
            memoryThresholdBytes: 0, sampledProcessCount: 0, unreadableProcessCount: statuses.count,
            findings: [], window: window.summary)
    }

    /// ESRCH after listing means the process exited before its read, which is an expected polling
    /// limit rather than a failure to read a live process; only the latter warns.
    @Test func exitedBeforeReadIsANoticeSeparateFromReadFailures() throws {
        let status = CoverageStatus(
            snapshot: try snapshot([.lookupUnavailable, .lookupUnavailable, .permissionDenied]))
        #expect(
            status.notes.map(\.text) == [
                "Read failures: 1 same-user PID", "Exited before read: 2 same-user PIDs",
            ])
        #expect(status.notes.map(\.severity) == [.warning, .notice])
        #expect(CoverageStatus(snapshot: try snapshot([.lookupUnavailable])).severity == .notice)
    }

    @Test func singleOverrunUsesSingularWording() throws {
        let status = CoverageStatus(snapshot: try snapshot(achievedPeriod: 1.2))
        #expect(status.notes.count == 1)
        #expect(status.notes.first?.text.hasPrefix("1 overrun · max gap 1200") == true)
        #expect(status.severity == .warning)
    }

    @Test(arguments: [false, true])
    func missingCPUCountsRemainVisibleWithCollectionWideScope(ranged: Bool) throws {
        let report = try snapshot(
            unmeasured: ranged ? 0 : 3,
            unmeasuredRange: ranged ? LifetimeCountRange(minimum: 2, maximum: 5) : nil)
        let status = CoverageStatus(snapshot: report)
        let warning = try #require(status.notes.first)
        #expect(warning.severity == .warning)
        #expect(warning.text.contains(ranged ? "2–5" : "3"))
        #expect(warning.help.contains("same-user"))
        #expect(warning.help.contains("agent"))
        var state = LiveReportState()
        state.receive(report)
        let live = LiveReportLayout.lines(state: state, width: 40, height: 8)
        #expect(live.contains { $0.style == .warning && $0.text.contains("D diagnostics") })
        state.showReference(.diagnostics)
        let details = ReportReferenceLayout.content(state: state, page: .diagnostics)
        #expect(details.contains { $0.text == warning.text && $0.style == .warning })
        #expect(details.contains { $0.text == warning.help })
    }

    /// A gap appearing or clearing must not move the rows under the user's selection.
    @Test(arguments: [60, 100, 140])
    func processHeaderReservesOneCoverageRow(width: Int) throws {
        func header(_ snapshot: MonitoringSnapshot) -> [ReportLine] {
            var state = LiveReportState()
            state.receive(snapshot)
            state.overview.enabled = false
            let lines = LiveReportLayout.lines(state: state, width: width, height: 30)
            return Array(lines.prefix { !$0.text.hasPrefix("PID") && $0.style != .heading })
        }
        let clean = header(try snapshot())
        let exited = header(try snapshot([.lookupUnavailable]))
        #expect(clean.contains(ReportLine("", style: .muted)))
        #expect(
            exited.contains(ReportLine("Exited before read: 1 same-user PID · D diagnostics", style: .normal))
        )
        #expect(clean.count == exited.count)
        let text = TextReport.lines(try snapshot([.lookupUnavailable]))
        #expect(text.contains(ReportLine("Exited before read: 1 same-user PID", style: .normal)))
    }
}

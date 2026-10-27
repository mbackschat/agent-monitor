import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore

@Test func backlogCountsAndSpanAgreeInJSONTextOverviewAndProcessLayout() throws {
    var ledger = CounterLedger()
    let first = ledger.ingest([], listedAt: 0)
    let middle = ledger.ingest([], listedAt: 1)
    let final = ledger.ingest([], listedAt: 2)
    var window = AccountingWindow(baseline: first)
    try window.append(middle, rows: [])
    var last = AccountingWindow(baseline: middle)
    try last.append(final, rows: [])
    try window.merge(last)
    #expect(AccountingContext.publication(window.summary.publicationCoverage) == nil)
    window.coalescePublication()
    let store = RecentActivityStore()
    store.append(window.seal(scope: .allProcesses))
    let snapshot = MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
            unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 0.1, cpuThresholdPercent: 0,
        memoryThresholdBytes: 0, sampledProcessCount: 0, unreadableProcessCount: 0, findings: [],
        window: window.summary, recentActivity: store.snapshot())
    let line = try JSONReport.encodeLine(snapshot)
    let json = try #require(JSONSerialization.jsonObject(with: line) as? [String: Any])
    let encoded = try #require(json["window"] as? [String: Any])
    let publication = try #require(encoded["publicationCoverage"] as? [String: Any])
    #expect(publication["coalescedUnitCount"] as? Int == 2)
    #expect(publication["maximumUnitSpanSeconds"] as? Double == 2)
    let disclosure = try #require(AccountingContext.publication(window.summary.publicationCoverage))
    #expect(disclosure.hasPrefix("Window:"))
    #expect(TextReport.render(snapshot).contains(disclosure))
    #expect(TextReport.render(snapshot).contains("coalesced range"))
    var state = LiveReportState()
    state.receive(snapshot)
    #expect(state.overview.coverageStatus.text.contains("Recent: 2 units coalesced"))
    #expect(state.overview.coverage.contains("coalesced range"))
    state.overview.enabled = false
    let live = LiveReportLayout.lines(state: state, width: 120, height: 24)
    #expect(live.contains { $0.text.contains("D diagnostics") })
    state.showReference(.diagnostics)
    let details = ReportReferenceLayout.content(state: state, page: .diagnostics).map(\.text).joined(
        separator: "\n")
    #expect(details.contains(disclosure))
    #expect(details.contains("coalesced range"))
}

@Test(arguments: [60, 100, 140])
func processHeadersExposeReadGapsAndOverruns(width: Int) throws {
    var ledger = CounterLedger()
    let baseline = ledger.ingest([], listedAt: 0)
    let source = ProcessSnapshot(
        samples: [], enumeratedCount: 2, unreadableCount: 2, listedAt: 1.2, scanSeconds: 0,
        hostCounters: nil, logicalCPUCount: 8,
        nativeOutcomes: [41, 42].map {
            NativeCounterOutcome(
                pid: $0, identity: nil, operation: .bsdInfo, status: .lookupUnavailable,
                failure: nil, observedAtTicks: 1)
        })
    let scan = ledger.ingest([], listedAt: 1.2, source: source)
    var window = AccountingWindow(baseline: baseline)
    try window.append(
        scan, rows: [],
        timing: AcquisitionTiming(
            runID: scan.id.runID, scanSequence: scan.id.sequence, qualityOfService: .userInitiated,
            requestedPeriodSeconds: 0.1, achievedPeriodSeconds: 1.2,
            scanWorkSeconds: 0, resolutionDelaySeconds: 0))
    let snapshot = MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
            unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 0.1, cpuThresholdPercent: 0,
        memoryThresholdBytes: 0, sampledProcessCount: 0, unreadableProcessCount: 0, findings: [],
        window: window.summary)
    var state = LiveReportState()
    state.receive(snapshot)
    state.overview.enabled = false
    let lines = LiveReportLayout.lines(state: state, width: width, height: 24)
    let warnings = lines.prefix(10).filter { $0.style == .warning }.map(\.text).joined(separator: " ")
    #expect(warnings.contains("D diagnostics"))
    state.showReference(.diagnostics)
    let details = ReportReferenceLayout.content(state: state, page: .diagnostics).map(\.text).joined(
        separator: "\n")
    #expect(details.contains("Exited before read: 2"))
    #expect(details.contains("1 overrun · max gap"))
    let textWarnings = TextReport.lines(snapshot).filter { $0.style == .warning }.map(\.text)
    #expect(textWarnings.contains { $0.contains("1 overrun · max gap") })
}

@Test func passiveDiagnosticsRetainsCollectionCountsAndWarnings() throws {
    let snapshot = MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: nil, logicalCPUCount: 8,
            measuredUserPercent: 0, unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 0.1,
        cpuThresholdPercent: 0, memoryThresholdBytes: 0,
        sampledProcessCount: 653, unreadableProcessCount: 9, findings: [])
    var state = LiveReportState()
    state.receive(snapshot)
    state.showReference(.diagnostics)
    let summary = try #require(state.displaySamplingCoverage)
    #expect(summary.metrics.first { $0.id == "sampled" }?.value == "653")
    #expect(summary.metrics.first { $0.id == "failed" }?.value == "9")
    #expect(summary.metrics.first { $0.id == "failed" }?.warning == true)
    let content = ReportReferenceLayout.content(state: state, page: .diagnostics)
    #expect(content.contains { $0.text == "Sampled: 653" })
    #expect(content.contains { $0.text == "Read gaps: 9" && $0.style == .warning })
}

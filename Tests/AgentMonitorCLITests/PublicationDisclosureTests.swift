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
    #expect(TextReport.render(snapshot).contains(disclosure))
    var state = LiveReportState()
    state.receive(snapshot)
    #expect(state.overview.coverageWarning.contains(disclosure))
    #expect(state.overview.coverage.contains("coalesced range"))
    state.overview.enabled = false
    #expect(LiveReportLayout.lines(state: state, width: 120, height: 24).contains { $0.text == disclosure })
}

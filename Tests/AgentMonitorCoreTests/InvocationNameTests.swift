import Foundation
import Testing

@testable import AgentMonitorCore

@Test func embeddedInvocationNamesFreezeWithCPUAndSurviveCategoryCollapse() throws {
    let executable = "/fixture/claude/versions/2.1.299"
    var ledger = CounterLedger()
    var monitor = Monitor()
    let first = sample(42, executable: executable, at: 0, cpu: 0)
    var window = AccountingWindow(baseline: ledger.ingest([first], listedAt: 0))
    for (tick, invocation) in ["ugrep", "jq"].enumerated() {
        let process = sample(42, executable: executable, at: Double(tick + 1), cpu: Double(tick + 1))
        let scan = ledger.ingest([process], listedAt: process.sampledAt)
        monitor.ingest([process])
        monitor.enrich(
            ProcessMetadata(
                markers: [SessionMarker(threadID: sessionA, provider: .claude)],
                invocation: invocation), for: process.identity)
        let row = try #require(monitor.finding(for: process.identity))
        #expect(row.invocationName == invocation)
        #expect(row.observedName == invocation)
        #expect(row.command == nil)
        try window.append(scan, rows: [row])
        #expect(window.payloadSize == window.recountedPayloadSize)
    }
    let records = window.seal(scope: .agentsOnly).records
    #expect(Set(records.map { $0.category.invocationName }) == ["ugrep", "jq"])
    #expect(records.allSatisfy { $0.cpuSeconds == 1 && $0.category.executable == executable })
    #expect(try window.findings(scope: .agentsOnly).first?.invocationName == "jq")
    try window.append(ledger.ingest([], listedAt: 3), rows: [])
    let size = window.compact(to: MonitoringPipelineLimits(pendingObservations: 4))
    #expect(size.observations <= 4)
    let collapsed = window.summary.collapsedContributions
    #expect(Set(collapsed.map { $0.category.invocationName }) == ["ugrep", "jq"])
    #expect(collapsed.allSatisfy { $0.cpuSeconds == 1 && $0.category.executable == executable })
}

@Test(arguments: ["", " ", "ugrep\nforged", String(repeating: "x", count: 161), "claude"])
func embeddedInvocationRejectsUnhelpfulLabels(invocation: String) {
    let adapter = ClaudeAttributionAdapter()
    #expect(adapter.workloadInvocationName(invocation, executable: "/fixture/claude/versions/2.1.299") == nil)
}

@Test func invocationLabelDoesNotClassifyUnrecognisedExecutables() throws {
    var monitor = Monitor()
    let process = sample(42, executable: "/fixture/ordinary")
    monitor.ingest([process])
    monitor.enrich(ProcessMetadata(invocation: "ugrep"), for: process.identity)
    #expect(monitor.finding(for: process.identity)?.invocationName == nil)
}

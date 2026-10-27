import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitor
@testable import AgentMonitorCore

@Suite struct InspectionInterfaceTests {
    @Test func onlyExplicitTUIOptionEnablesInspection() throws {
        #expect(try !Options.parse(["--tui"]).inspectionObservations)
        #expect(try Options.parse(["--tui", "--inspection-observations"]).inspectionObservations)
        for args in [["--inspection-observations"], ["--json", "--inspection-observations"]] {
            #expect(throws: (any Error).self) { try Options.parse(args) }
        }
    }

    @Test(arguments: [false, true]) func jsonDeclaresModeAndPassiveDiagnosticsShowsEnabledInspection(
        enabled: Bool
    ) throws {
        var coverage = InspectionCoverage()
        coverage.mode = enabled ? .enabled : .disabled
        coverage.opportunitiesTaken = enabled ? 2 : 0
        coverage.opportunitiesSkipped = enabled ? 3 : 0
        var ledger = CounterLedger()
        var window = AccountingWindow(baseline: ledger.ingest([], listedAt: 0))
        try window.append(ledger.ingest([], listedAt: 1), rows: [], inspectionCoverage: coverage)
        let snapshot = MonitoringSnapshot(
            cpuAccounting: CPUAccounting(
                hostBusyPercent: nil,
                logicalCPUCount: 8, measuredUserPercent: 0, unmeasuredLifetimeCount: 0,
                previousScanSeconds: nil),
            timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 0.1, cpuThresholdPercent: 0,
            memoryThresholdBytes: 0, sampledProcessCount: 0, unreadableProcessCount: 0,
            findings: [], window: window.summary)
        let json = try #require(
            JSONSerialization.jsonObject(with: JSONReport.encodeLine(snapshot)) as? [String: Any])
        if enabled, let path = ProcessInfo.processInfo.environment["JSON_INSPECTION_FIXTURE_PATH"] {
            try JSONReport.encodeLine(snapshot).write(to: URL(fileURLWithPath: path))
        }
        let encoded = try #require(json["inspectionCoverage"] as? [String: Any])
        #expect(encoded["mode"] as? String == (enabled ? "enabled" : "disabled"))
        var state = LiveReportState()
        state.receive(snapshot)
        state.overview.enabled = false
        let rendered = LiveReportLayout.lines(state: state, width: 120, height: 24).map(\.text).joined()
        #expect(rendered.contains("Between-scan reads skipped") == enabled)
        state.showReference(.diagnostics)
        let content = ReportReferenceLayout.content(state: state, page: .diagnostics).map(\.text).joined(
            separator: "\n")
        #expect(content.contains("Between-scan reads · enabled") == enabled)
        if enabled {
            #expect(content.contains("Opportunities: 2 taken · 3 skipped"))
            #expect(content.contains("Enumeration failures: 0"))
            #expect(content.contains("Candidates: 0 read · 0 failed · 0 left unread"))
        }
    }
}

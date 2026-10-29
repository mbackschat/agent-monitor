import AgentMonitorActions
import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore

@Test func terminationConfirmationKeepsTheSelectedIdentity() throws {
    var state = LiveReportState()
    let first = panelRow(42)
    state.receive(panelSnapshot([first, panelRow(84)]))
    #expect(state.beginAction(.terminate) == nil)
    #expect(state.actionPanel?.process == first)
    state.receive(panelSnapshot([panelRow(84)]))
    #expect(state.actionPanel?.process == first)
    #expect(state.actionPanel?.phase == .confirmTermination)
    #expect(state.actionInput(.confirm) == .terminate(first))
    #expect(state.actionInput(.confirm) == nil)
}

private func panelRow(_ pid: Int32, provider: AgentProvider = .codex) -> HeavyProcess {
    HeavyProcess(
        process: ProcessIdentity(pid: pid, startMicroseconds: 1),
        executable: "/fixture/worker", name: "worker", cpuPercent: nil, footprintBytes: nil,
        cwd: nil, command: nil, metadataStatus: .notObserved,
        attribution: Attribution(
            provider: provider, evidence: .marker, context: .terminal, threadID: "child",
            rootSessionID: nil, runtime: nil, terminal: nil, runtimeDirectory: nil,
            candidateThreadIDs: [], ancestry: []))
}

private func panelSnapshot(_ rows: [HeavyProcess]) -> MonitoringSnapshot {
    MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
            unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1,
        cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
        sampledProcessCount: rows.count, unreadableProcessCount: 0, findings: rows)
}

@Test func focusStartsImmediatelyAndWaitsForTheResult() throws {
    var state = LiveReportState()
    let row = panelRow(42)
    state.receive(panelSnapshot([row]))
    #expect(state.beginAction(.focus) == .focus(row))
    #expect(state.actionPanel?.phase == .focusing)
    let waiting = LiveReportLayout.lines(state: state, width: 200, height: 24).map(\.text).joined()
    #expect(waiting.contains("Focusing terminal") && waiting.contains("macOS may ask"))
    #expect(state.actionInput(.escape) == nil)
    #expect(state.actionPanel != nil)
    state.actionFinished(
        .accepted(FocusWording.result(.session(application: "Terminal", tty: "/dev/ttys019"))))
    #expect(state.actionInput(.escape) == nil)
    #expect(state.actionPanel == nil)
}

// A selected tab is exact; activating an app without an adapter may show another of its windows.
@Test(arguments: [
    (
        FocusOutcome.session(application: "Terminal", tty: "/dev/ttys019"),
        "Selected the session on ttys019 in Terminal"
    ),
    (.application("Editor"), "cannot select the session's tab"),
])
func focusWordingSeparatesExactAndAppOnlyResults(outcome: FocusOutcome, expected: String) {
    #expect(FocusWording.result(outcome).contains(expected))
}

@Test func panelLinesCarryRolesForTitleNotesWarningsAndKeys() throws {
    var state = LiveReportState()
    let row = panelRow(42)
    state.receive(panelSnapshot([row]))
    _ = state.beginAction(.terminate)
    let lines = LiveReportLayout.lines(state: state, width: 200, height: 24)
    #expect(lines.first?.style == .title)
    #expect(lines.first { $0.text.hasPrefix("Send SIGTERM") }?.style == .warning)
    #expect(lines.first { $0.text.contains("No process group") }?.style == .muted)
    #expect(lines.last?.style == .muted)
    #expect(lines.first { $0.text.hasPrefix("Process PID 42") }?.style == .normal)
}

@Test(arguments: [
    (ActionResult.accepted("SIGTERM accepted."), ReportLine.Style.success),
    (.failed("Process exited."), .failure),
    (.uncertain("Termination may have been accepted."), .warning),
])
func actionResultsAreColoredByOutcome(result: ActionResult, style: ReportLine.Style) throws {
    var state = LiveReportState()
    state.receive(panelSnapshot([panelRow(42)]))
    _ = state.beginAction(.terminate)
    _ = state.actionInput(.confirm)
    state.actionFinished(result)
    let lines = LiveReportLayout.lines(state: state, width: 200, height: 24)
    #expect(lines.contains { $0.style == style && result.text.contains($0.text) })
}

private func sessionRow(_ pid: Int32, runtime: Int32?) -> HeavyProcess {
    HeavyProcess(
        process: ProcessIdentity(pid: pid, startMicroseconds: 1),
        executable: "/fixture/worker", name: "worker", cpuPercent: nil, footprintBytes: nil,
        cwd: nil, command: nil, metadataStatus: .markerRead,
        attribution: Attribution(
            provider: .claude, evidence: .marker, context: .terminal,
            threadID: "11111111-1111-4111-8111-111111111111", rootSessionID: nil,
            runtime: runtime.map { ProcessIdentity(pid: $0, startMicroseconds: 1) },
            terminal: nil, runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []))
}

// A launch group identifies one session for focus; termination still requires a process.
@Test func focusOnACollapsedGroupTargetsItsOneRuntime() throws {
    var state = LiveReportState(grouping: .session)
    let rows = [sessionRow(42, runtime: nil), sessionRow(43, runtime: 700)]
    state.receive(panelSnapshot(rows))
    #expect(state.selectedGroup != nil)
    #expect(state.beginAction(.terminate) == nil)
    #expect(state.actionPanel == nil)
    #expect(state.beginAction(.focus) == .focus(rows[1]))
    #expect(state.actionPanel?.phase == .focusing)
}

@Test(arguments: [[Int32?.none, nil], [700, 701]])
func focusOnAGroupWithoutOneRuntimeExplains(runtimes: [Int32?]) throws {
    var state = LiveReportState(grouping: .session)
    state.receive(
        panelSnapshot(
            runtimes.enumerated().map { sessionRow(Int32(42 + $0.offset), runtime: $0.element) }))
    #expect(state.beginAction(.focus) == nil)
    #expect(state.actionPanel == nil)
    #expect(state.notice?.contains("runtime") == true)
}

// The TUI panel and the CLI commands show the same target and result wording.
@Test func actionWordingIsSharedByPanelAndCommands() throws {
    let row = panelRow(42)
    #expect(
        ActionWording.target(row) == [
            "Process PID 42: worker", "Executable: /fixture/worker", "Attributed session: codex/child",
        ])
    var state = LiveReportState()
    state.receive(panelSnapshot([row]))
    _ = state.beginAction(.terminate)
    let panel = LiveReportLayout.lines(state: state, width: 200, height: 24).map(\.text)
    #expect(ActionWording.target(row).allSatisfy(panel.contains))
    #expect(
        ActionWording.terminationAccepted(pid: 42)
            == "SIGTERM accepted for PID 42. Exit is not yet confirmed.")
}

@Test func unavailableMessageNeverCreatesAnActionPanel() {
    var state = LiveReportState()
    state.receive(panelSnapshot([panelRow(42)]))
    #expect(state.beginAction(.message) == nil)
    #expect(state.actionPanel == nil)
    #expect(state.notice == ProviderRuntimeAvailability.messagingUnavailableReason)
}

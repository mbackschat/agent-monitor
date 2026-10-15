import AgentMonitorActions
import AgentMonitorCore
import AgentMonitorPresentation
import Foundation
import Testing

@Test func actionSelectionIsFrozenAndTypingDoesNotTriggerCommands() throws {
    var state = LiveReportState()
    let first = try panelRow(42)
    state.receive(panelSnapshot([first, try panelRow(84)]))
    #expect(state.beginAction(.terminate) == nil)
    #expect(state.actionPanel?.process == first)
    state.receive(panelSnapshot([try panelRow(84)]))
    #expect(state.actionPanel?.process == first)
    #expect(state.actionInput(.text("qky")) == nil)
    #expect(state.actionPanel?.phase == .confirmTermination)
    #expect(state.actionInput(.confirm) == .terminate(first))
    #expect(state.actionInput(.confirm) == nil)
}

@Test func composerRequiresReviewAndExplicitConfirmation() throws {
    var state = LiveReportState()
    let row = try panelRow(42)
    state.receive(panelSnapshot([row]))
    #expect(state.beginAction(.message) == .prepare(row))
    let recipients = MessageRecipients(
        root: AgentRecipient(id: "root", label: "Root agent"),
        selected: AgentRecipient(id: "child", label: "Selected agent"))
    let draft = MessageDraft(process: row, recipients: recipients)
    state.messagePrepared(draft)
    #expect(state.actionInput(.confirm) == nil)
    #expect(state.actionInput(.text("q\nkill it?")) == nil)
    #expect(state.actionPanel?.text == "q\nkill it?")
    #expect(state.actionInput(.review) == nil)
    #expect(state.actionPanel?.recipient?.id == "root")
    #expect(state.actionInput(.text("y")) == nil)
    #expect(state.actionInput(.confirm) == .send(draft, "q\nkill it?", "root"))
}

@Test(arguments: [40, 60, 120, 200])
func actionPanelsFitAndAllowFullMessageReview(width: Int) throws {
    var state = LiveReportState()
    let row = try panelRow(42)
    state.receive(panelSnapshot([row]))
    _ = state.beginAction(.message)
    let recipient = AgentRecipient(id: "root", label: "Root agent")
    state.messagePrepared(
        MessageDraft(process: row, recipients: MessageRecipients(root: recipient, selected: recipient)))
    _ = state.actionInput(.text(String(repeating: "Long message ", count: 80)))
    _ = state.actionInput(.review)
    let before = LiveReportLayout.lines(state: state, width: width, height: 12)
    #expect(before.count == 12)
    #expect(before.allSatisfy { $0.text.count <= width })
    #expect(before.map(\.text).joined().contains("Ctrl-Y send"))
    _ = state.actionInput(.scroll(100))
    #expect(LiveReportLayout.lines(state: state, width: width, height: 12) != before)
}

private func panelRow(_ pid: Int32, provider: AgentProvider = .codex) throws -> HeavyProcess {
    try JSONDecoder().decode(
        HeavyProcess.self,
        from: Data(
            """
            {"process":{"pid":\(pid),"startMicroseconds":1},"executable":"/fixture/worker","name":"worker",
            "metadataStatus":"notObserved","attribution":{"provider":"\(provider.rawValue)","evidence":"marker",
            "context":"terminal","threadID":"child","candidateThreadIDs":[],"ancestry":[]}}
            """.utf8))
}
private func panelSnapshot(_ rows: [HeavyProcess]) -> MonitoringSnapshot {
    MonitoringSnapshot(
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1,
        cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
        sampledProcessCount: rows.count, unreadableProcessCount: 0, findings: rows)
}

@Test func messageReviewWrapsWideCharactersWithoutHidingText() throws {
    var state = LiveReportState()
    let row = try panelRow(42)
    state.receive(panelSnapshot([row]))
    _ = state.beginAction(.message)
    let recipient = AgentRecipient(id: "root", label: "Root agent")
    state.messagePrepared(
        MessageDraft(process: row, recipients: MessageRecipients(root: recipient, selected: recipient)))
    _ = state.actionInput(.text(String(repeating: "調査", count: 35)))
    _ = state.actionInput(.review)
    let lines = LiveReportLayout.lines(state: state, width: 40, height: 24)
    let messageLines = lines.map(\.text).filter { $0.contains("調") || $0.contains("査") }
    #expect(messageLines.joined() == String(repeating: "調査", count: 35))
    #expect(messageLines.allSatisfy { $0.count * 2 <= 40 })
}

// Codex queues a request; Claude's inbox may still hold or refuse a peer message.
@Test(arguments: [
    (AgentProvider.codex, "Queued acceptance does not mean delivery", "Message queued for root."),
    (.claude, "may hold or refuse", "Message handed to the inbox of Claude session root."),
])
func acceptanceWordingFollowsTheProviderTransport(provider: AgentProvider, note: String, result: String)
    throws
{
    var state = LiveReportState()
    let row = try panelRow(42, provider: provider)
    state.receive(panelSnapshot([row]))
    _ = state.beginAction(.message)
    let recipient = AgentRecipient(id: "root", label: "Root agent")
    let draft = MessageDraft(
        process: row, recipients: MessageRecipients(root: recipient, selected: recipient))
    state.messagePrepared(draft)
    #expect(LiveReportLayout.lines(state: state, width: 200, height: 24).map(\.text).joined().contains(note))
    #expect(MessageWording.accepted(draft, recipient: "root").hasPrefix(result))
}

@Test func focusStartsImmediatelyAndWaitsForTheResult() throws {
    var state = LiveReportState()
    let row = try panelRow(42)
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
    let row = try panelRow(42)
    state.receive(panelSnapshot([row]))
    _ = state.beginAction(.message)
    let root = AgentRecipient(id: "root", label: "Root agent", unavailableReason: "Root is not loaded.")
    state.messagePrepared(
        MessageDraft(
            process: row,
            recipients: MessageRecipients(
                root: root, selected: AgentRecipient(id: "child", label: "Selected agent"))))
    let lines = LiveReportLayout.lines(state: state, width: 200, height: 24)
    #expect(lines.first?.style == .title)
    #expect(lines.first { $0.text.hasPrefix("Unavailable:") }?.style == .warning)
    #expect(lines.first { $0.text.contains("Queued acceptance") }?.style == .muted)
    #expect(lines.last?.style == .muted)
    #expect(lines.first { $0.text.hasPrefix("Process PID 42") }?.style == .normal)
}

@Test(arguments: [
    (ActionResult.accepted("SIGTERM accepted."), ReportLine.Style.success),
    (.failed("Process exited."), .failure),
    (.uncertain("The message may have been accepted."), .warning),
])
func actionResultsAreColoredByOutcome(result: ActionResult, style: ReportLine.Style) throws {
    var state = LiveReportState()
    state.receive(panelSnapshot([try panelRow(42)]))
    _ = state.beginAction(.terminate)
    _ = state.actionInput(.confirm)
    state.actionFinished(result)
    let lines = LiveReportLayout.lines(state: state, width: 200, height: 24)
    #expect(lines.contains { $0.style == style && result.text.contains($0.text) })
}

private func sessionRow(_ pid: Int32, runtime: Int32?) throws -> HeavyProcess {
    let runtimeJSON = runtime.map { #","runtime":{"pid":\#($0),"startMicroseconds":1}"# } ?? ""
    return try JSONDecoder().decode(
        HeavyProcess.self,
        from: Data(
            """
            {"process":{"pid":\(pid),"startMicroseconds":1},"executable":"/fixture/worker","name":"worker",
            "metadataStatus":"markerRead","attribution":{"provider":"claude","evidence":"marker",
            "context":"terminal","threadID":"11111111-1111-4111-8111-111111111111"\(runtimeJSON),
            "candidateThreadIDs":[],"ancestry":[]}}
            """.utf8))
}

// A launch group identifies one session, which is all focus needs; k and s keep requiring a process.
@Test func focusOnACollapsedGroupTargetsItsOneRuntime() throws {
    var state = LiveReportState(grouping: .session)
    let rows = [try sessionRow(42, runtime: nil), try sessionRow(43, runtime: 700)]
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
            try runtimes.enumerated().map { try sessionRow(Int32(42 + $0.offset), runtime: $0.element) }))
    #expect(state.beginAction(.focus) == nil)
    #expect(state.actionPanel == nil)
    #expect(state.notice?.contains("runtime") == true)
}

// The TUI panel and the CLI commands show the same target and result wording.
@Test func actionWordingIsSharedByPanelAndCommands() throws {
    let row = try panelRow(42)
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

// The composer, the send check and the CLI help use one limit.
@Test func messageLengthLimitHasOneSource() throws {
    #expect(MessageDraft.maximumLength == 4000)
    var state = LiveReportState()
    let row = try panelRow(42)
    state.receive(panelSnapshot([row]))
    _ = state.beginAction(.message)
    let recipient = AgentRecipient(id: "root", label: "Root agent")
    state.messagePrepared(
        MessageDraft(process: row, recipients: MessageRecipients(root: recipient, selected: recipient)))
    _ = state.actionInput(.text(String(repeating: "x", count: MessageDraft.maximumLength + 10)))
    #expect(state.actionPanel?.text.count == MessageDraft.maximumLength)
}

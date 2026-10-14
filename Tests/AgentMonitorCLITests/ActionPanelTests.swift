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

private func panelRow(_ pid: Int32) throws -> HeavyProcess {
    try JSONDecoder().decode(
        HeavyProcess.self,
        from: Data(
            """
            {"process":{"pid":\(pid),"startMicroseconds":1},"executable":"/fixture/worker","name":"worker",
            "metadataStatus":"notObserved","attribution":{"provider":"codex","evidence":"marker",
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

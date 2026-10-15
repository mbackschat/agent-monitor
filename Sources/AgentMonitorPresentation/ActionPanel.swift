import AgentMonitorActions
import AgentMonitorCore
import Foundation

public enum ProcessActionKind: Sendable { case terminate, message, focus }
public enum ActionInput: Sendable {
    case text(String)
    case backspace, review, confirm, escape, recipient
    case scroll(Int)
}
public enum ActionEffect: Equatable, Sendable {
    case prepare(HeavyProcess)
    case terminate(HeavyProcess)
    case send(MessageDraft, String, String)
    case focus(HeavyProcess)
}

/// Acceptance means different things per transport: Codex accepts a queue request, while a Claude
/// inbox applies the session's peer controls after the handoff (docs/research/claude-session-messaging.md).
public enum MessageWording {
    public static func note(_ provider: AgentProvider?) -> String {
        switch provider {
        case .codex, nil: "Queued acceptance does not mean delivery or action."
        case .claude:
            "Inbox acceptance does not mean delivery: the session may hold or refuse messages from other processes."
        }
    }

    public static func accepted(_ draft: MessageDraft, recipient: String) -> String {
        switch draft.process.attribution.provider {
        case .codex, nil: "Message queued for \(recipient). Delivery and action are not confirmed."
        case .claude:
            "Message handed to the inbox of Claude session \(recipient). Delivery and action are not confirmed."
        }
    }
}

/// Target and result wording shared by the TUI panel and the command-line actions.
public enum ActionWording {
    public static func target(_ process: HeavyProcess) -> [String] {
        let attribution = process.attribution
        return [
            "Process PID \(process.process.pid): \(process.name)",
            "Executable: \(process.executable)",
            "\(process.isSharedRuntime ? "Attribution" : "Attributed session"): \(attribution.provider?.rawValue ?? "unknown")/\(process.sessionDescription)",
        ]
    }

    public static func terminationAccepted(pid: Int32) -> String {
        "SIGTERM accepted for PID \(pid). Exit is not yet confirmed."
    }
}

/// A selected session is exact; activating an application without an adapter may surface another
/// of its windows (docs/research/terminal-focus.md#4-generic-fallback).
public enum FocusWording {
    public static func result(_ outcome: FocusOutcome) -> String {
        switch outcome {
        case .session(let application, let tty):
            "Selected the session on \(tty.replacing("/dev/", with: "")) in \(application) and asked \(application) to come to the front. macOS may keep another app in front."
        case .application(let name):
            "Asked \(name) to come to the front. Agent Monitor cannot select the session's tab in \(name), so another of its windows may show."
        }
    }
}

/// Accepted means a signal or message was handed over, never that it took effect.
public enum ActionResult: Equatable, Sendable {
    case accepted(String)
    case failed(String)
    /// Possibly accepted; the user must check before retrying.
    case uncertain(String)

    public var text: String {
        switch self {
        case .accepted(let text), .failed(let text), .uncertain(let text): text
        }
    }
}

public struct ActionPanel: Equatable, Sendable {
    public enum Phase: Sendable {
        case confirmTermination, loading, compose, review, working, focusing, result
    }
    public let process: HeavyProcess
    public var phase: Phase
    public var draft: MessageDraft?
    public var text = ""
    public var recipientIndex = 0
    public var offset = 0
    public var result: ActionResult?
    public var recipient: AgentRecipient? {
        guard let choices = draft?.recipients.choices, choices.indices.contains(recipientIndex) else {
            return nil
        }
        return choices[recipientIndex]
    }

    public mutating func input(_ input: ActionInput) -> ActionEffect? {
        switch input {
        case .text(let text) where phase == .compose:
            let safe = text.unicodeScalars.filter {
                !CharacterSet.controlCharacters.contains($0) || $0 == "\n"
            }
            offset = 0
            self.text = String(
                (self.text + String(String.UnicodeScalarView(safe))).prefix(MessageDraft.maximumLength))
        case .backspace where phase == .compose:
            if !text.isEmpty { text.removeLast() }
        case .recipient where phase == .compose:
            if let choices = draft?.recipients.choices {
                recipientIndex = (recipientIndex + 1) % choices.count
            }
        case .review where phase == .compose:
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                recipient?.unavailableReason == nil
            else { return nil }
            phase = .review
            offset = 0
        case .escape where phase == .review:
            phase = .compose
            offset = 0
        case .confirm where phase == .confirmTermination:
            phase = .working
            return .terminate(process)
        case .confirm where phase == .review:
            guard let draft, let recipient, recipient.unavailableReason == nil else { return nil }
            phase = .working
            return .send(draft, text, recipient.id)
        case .scroll(let delta):
            offset =
                phase == .compose ? min(0, max(-10_000, offset + delta)) : max(0, min(10_000, offset + delta))
        default: break
        }
        return nil
    }

    func lines(width: Int, height: Int) -> [ReportLine] {
        let (title, content, controls) = phaseContent()
        let footer = Self.wrap([ReportLine(controls, style: .muted)], width: width)
        let capacity = max(1, height - 1 - footer.count)
        let rows = Self.wrap(content, width: width)
        // Editing follows the insertion point; review starts at the target and is scrollable.
        let start =
            phase == .compose
            ? max(0, rows.count - capacity + offset) : min(offset, max(0, rows.count - capacity))
        let visible = Array(rows.dropFirst(start).prefix(capacity))
        let heading = String((title + " [\(start + 1)-\(start + visible.count)/\(rows.count)]").prefix(width))
        return [ReportLine(heading, style: .title)] + visible
            + Array(repeating: ReportLine(""), count: max(0, capacity - visible.count)) + footer
    }

    private func phaseContent() -> (title: String, content: [ReportLine], controls: String) {
        let title: String
        let controls: String
        var content = ActionWording.target(process).map { ReportLine($0) }
        switch phase {
        case .confirmTermination:
            title = "Terminate selected process?"
            content += [
                ReportLine(
                    "Send SIGTERM to this process only. It may stop work or lose unsaved changes.",
                    style: .warning),
                ReportLine(
                    "No process group or session-wide signal. Process identity and owner will be checked again.",
                    style: .muted),
            ]
            controls = "Ctrl-Y terminate | Esc cancel | ↑/↓ scroll"
        case .loading:
            title = "Checking live recipients…"
            controls = "Ctrl-C quit"
        case .compose, .review:
            title = phase == .compose ? "Message agent" : "Review exact message"
            content += messageContent()
            controls =
                phase == .compose
                ? "Enter review | Tab recipient | Esc cancel | ↑/↓ scroll"
                : "Ctrl-Y send | Esc edit | ↑/↓ scroll"
        case .working:
            title = "Submitting action…"
            controls = "Ctrl-C quit"
        case .focusing:
            title = "Focusing terminal…"
            content += [
                ReportLine("Bringing the agent runtime's terminal to the front."),
                ReportLine(
                    "On first use, macOS may ask whether the terminal running Agent Monitor may control it.",
                    style: .muted),
            ]
            controls = "Ctrl-C quit"
        case .result:
            title = "Action result"
            switch result {
            case .accepted(let text): content += [ReportLine(""), ReportLine(text, style: .success)]
            case .failed(let text): content += [ReportLine(""), ReportLine(text, style: .failure)]
            case .uncertain(let text): content += [ReportLine(""), ReportLine(text, style: .warning)]
            case nil: break
            }
            controls = "Esc close | ↑/↓ scroll"
        }
        return (title, content, controls)
    }

    private func messageContent() -> [ReportLine] {
        var content: [ReportLine] = []
        if let recipient {
            content += [ReportLine("Recipient: \(recipient.label) / \(recipient.id)")]
            if let reason = recipient.unavailableReason {
                content += [ReportLine("Unavailable: \(reason)", style: .warning)]
            }
        }
        if draft?.recipients.choices.count == 2 {
            content += [ReportLine("Tab chooses root or selected agent while editing.", style: .muted)]
        }
        content += [
            ReportLine(MessageWording.note(process.attribution.provider), style: .muted), ReportLine(""),
        ]
        var message = (draft?.message(text) ?? text).components(separatedBy: "\n")
        if phase == .compose { message[message.count - 1] += "▏" }
        return content + message.map { ReportLine($0) }
    }

    private static func wrap(_ lines: [ReportLine], width: Int) -> [ReportLine] {
        lines.flatMap { line in
            if line.text.isEmpty { return [line] }
            var rows: [ReportLine] = []
            var row = ""
            var columns = 0
            for character in line.text {
                // Conservatively reserve two cells for non-ASCII text: the one-row
                // terminal view clips CJK/emoji if wrapping only counts characters.
                let cells = character.unicodeScalars.allSatisfy { $0.isASCII } ? 1 : 2
                if columns + cells > width {
                    rows.append(ReportLine(row, style: line.style))
                    row = ""
                    columns = 0
                }
                row.append(character)
                columns += cells
            }
            if !row.isEmpty { rows.append(ReportLine(row, style: line.style)) }
            return rows
        }
    }
}

extension LiveReportState {
    public mutating func beginAction(_ kind: ProcessActionKind) -> ActionEffect? {
        guard actionPanel == nil else { return nil }
        if visibleRows.contains(where: {
            if case .unavailable(let pin) = $0 { return pin.id == selection }
            return false
        }) {
            setActionNotice("Pinned target is not in current results. Unpin it or wait for a fresh sample.")
            return nil
        }
        if case .focus = kind, let group = selectedGroup.flatMap({ id in groups.first { $0.id == id } }) {
            return beginFocus(on: group)
        }
        guard let row = rows.first(where: { $0.process == selected }) else {
            setActionNotice("Expand a group and select a process first.")
            return nil
        }
        switch kind {
        case .terminate:
            actionPanel = ActionPanel(process: row, phase: .confirmTermination)
            return nil
        case .message:
            return beginMessage(for: row)
        case .focus:
            actionPanel = ActionPanel(process: row, phase: .focusing)
            return .focus(row)
        }
    }

    /// Starts fresh recipient verification for a frozen target, including a restored UI draft.
    public mutating func beginMessage(for process: HeavyProcess) -> ActionEffect? {
        guard actionPanel == nil else { return nil }
        actionPanel = ActionPanel(process: process, phase: .loading)
        return .prepare(process)
    }

    /// A launch group names one session, which is all focus needs: it targets the group's runtime
    /// when its processes agree on exactly one.
    private mutating func beginFocus(on group: SessionGroup) -> ActionEffect? {
        let runtimes = Set(group.processes.compactMap(\.attribution.runtime))
        guard runtimes.count == 1, let row = group.processes.first(where: { $0.attribution.runtime != nil })
        else {
            setActionNotice(
                runtimes.isEmpty
                    ? "This group has no live agent runtime to focus."
                    : "This group spans several runtimes; expand it and select a process.")
            return nil
        }
        actionPanel = ActionPanel(process: row, phase: .focusing)
        return .focus(row)
    }

    public mutating func actionInput(_ input: ActionInput) -> ActionEffect? {
        guard var panel = actionPanel else { return nil }
        if case .escape = input {
            switch panel.phase {
            case .confirmTermination, .compose, .result:
                actionPanel = nil
                return nil
            case .loading, .working, .focusing, .review: break
            }
        }
        let effect = panel.input(input)
        actionPanel = panel
        return effect
    }

    public mutating func messagePrepared(_ draft: MessageDraft) {
        guard actionPanel?.phase == .loading, actionPanel?.process == draft.process else { return }
        actionPanel?.draft = draft
        actionPanel?.phase = .compose
    }

    public mutating func actionFinished(_ result: ActionResult) {
        actionPanel?.phase = .result
        actionPanel?.result = result
        actionPanel?.offset = 0
    }
}

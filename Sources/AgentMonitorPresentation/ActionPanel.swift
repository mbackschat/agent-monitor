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
    static func note(_ provider: AgentProvider?) -> String {
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
    public var result = ""
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
            self.text = String((self.text + String(String.UnicodeScalarView(safe))).prefix(4000))
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
        let title: String
        let controls: String
        var content = [
            "Process PID \(process.process.pid): \(process.name)",
            "Executable: \(process.executable)",
            "Attributed session: \(process.attribution.provider?.rawValue ?? "unknown")/\(process.attribution.threadID ?? "unresolved")",
        ]
        switch phase {
        case .confirmTermination:
            title = "Terminate selected process?"
            content += [
                "Send SIGTERM to this process only. It may stop work or lose unsaved changes.",
                "No process group or session-wide signal. Process identity and owner will be checked again.",
            ]
            controls = "Ctrl-Y terminate | Esc cancel | ↑/↓ scroll"
        case .loading:
            title = "Checking live recipients…"
            controls = "Ctrl-C quit"
        case .compose, .review:
            title = phase == .compose ? "Message agent" : "Review exact message"
            if let recipient {
                content += ["Recipient: \(recipient.label) / \(recipient.id)"]
                if let reason = recipient.unavailableReason { content += ["Unavailable: \(reason)"] }
            }
            if draft?.recipients.choices.count == 2 {
                content += ["Tab chooses root or selected agent while editing."]
            }
            content += [MessageWording.note(process.attribution.provider), ""]
            content += (draft?.message(text) ?? text).components(separatedBy: "\n")
            if phase == .compose { content[content.count - 1] += "▏" }
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
                "Bringing the agent runtime's terminal to the front.",
                "On first use, macOS may ask whether the terminal running Agent Monitor may control it.",
            ]
            controls = "Ctrl-C quit"
        case .result:
            title = "Action result"
            content += ["", result]
            controls = "Esc close | ↑/↓ scroll"
        }
        func wrap(_ values: [String]) -> [String] {
            values.flatMap { value in
                let safe = TextReport.safe(value)
                if safe.isEmpty { return [""] }
                var rows: [String] = []
                var row = ""
                var columns = 0
                for character in safe {
                    // Conservatively reserve two cells for non-ASCII text: the one-row
                    // terminal view clips CJK/emoji if wrapping only counts characters.
                    let cells = character.unicodeScalars.allSatisfy { $0.isASCII } ? 1 : 2
                    if columns + cells > width {
                        rows.append(row)
                        row = ""
                        columns = 0
                    }
                    row.append(character)
                    columns += cells
                }
                if !row.isEmpty { rows.append(row) }
                return rows
            }
        }
        let footer = wrap([controls])
        let capacity = max(1, height - 1 - footer.count)
        let rows = wrap(content)
        // Editing follows the insertion point; review starts at the target and is scrollable.
        let start =
            phase == .compose
            ? max(0, rows.count - capacity + offset) : min(offset, max(0, rows.count - capacity))
        let visible = Array(rows.dropFirst(start).prefix(capacity))
        let heading = String((title + " [\(start + 1)-\(start + visible.count)/\(rows.count)]").prefix(width))
        return [ReportLine(heading, style: .heading)] + visible.map { ReportLine($0) }
            + Array(repeating: ReportLine(""), count: max(0, capacity - visible.count))
            + footer.map { ReportLine($0, style: .muted) }
    }
}

extension LiveReportState {
    public mutating func beginAction(_ kind: ProcessActionKind) -> ActionEffect? {
        guard actionPanel == nil else { return nil }
        guard let row = rows.first(where: { $0.process == selected }) else {
            setActionNotice("Expand a group and select a process first.")
            return nil
        }
        switch kind {
        case .terminate:
            actionPanel = ActionPanel(process: row, phase: .confirmTermination)
            return nil
        case .message:
            actionPanel = ActionPanel(process: row, phase: .loading)
            return .prepare(row)
        case .focus:
            actionPanel = ActionPanel(process: row, phase: .focusing)
            return .focus(row)
        }
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

    public mutating func actionFinished(_ result: String) {
        actionPanel?.phase = .result
        actionPanel?.result = result
        actionPanel?.offset = 0
    }
}

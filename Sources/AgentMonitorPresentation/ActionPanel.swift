import AgentMonitorActions
import AgentMonitorCore
import Foundation

public enum ProcessActionKind: Sendable { case terminate, message, focus }
public enum ActionInput: Sendable {
    case confirm, escape
    case scroll(Int)
}
public enum ActionEffect: Equatable, Sendable {
    case terminate(HeavyProcess)
    case focus(HeavyProcess)
}

/// Target and result wording shared by the TUI panel and the command-line actions.
public enum ActionWording {
    public static func target(_ process: HeavyProcess) -> [String] {
        let attribution = process.attribution
        return [
            "Process PID \(process.process.pid): \(process.observedName)",
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

/// Signal acceptance does not confirm process exit.
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
        case confirmTermination, working, focusing, result
    }
    public let process: HeavyProcess
    public var phase: Phase
    public var offset = 0
    public var result: ActionResult?
    public mutating func input(_ input: ActionInput) -> ActionEffect? {
        switch input {
        case .confirm where phase == .confirmTermination:
            phase = .working
            return .terminate(process)
        case .scroll(let delta):
            offset = max(0, min(10_000, offset + delta))
        default: break
        }
        return nil
    }

    func lines(width: Int, height: Int) -> [ReportLine] {
        let (title, content, controls) = phaseContent()
        let footer = Self.wrap([ReportLine(controls, style: .muted)], width: width)
        let capacity = max(1, height - 1 - footer.count)
        let rows = Self.wrap(content, width: width)
        let start = min(offset, max(0, rows.count - capacity))
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

    private static func wrap(_ lines: [ReportLine], width: Int) -> [ReportLine] {
        lines.flatMap { line in
            TerminalCells.wrapped(line.text, to: width).map { ReportLine($0, style: line.style) }
        }
    }
}

extension LiveReportState {
    public mutating func beginAction(_ kind: ProcessActionKind) -> ActionEffect? {
        if case .message = kind {
            setActionNotice(ProviderRuntimeAvailability.messagingUnavailableReason)
            return nil
        }
        guard !showsOverview else { return nil }
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
        guard !row.isHistorical else {
            setActionNotice("Historical contributors cannot initiate actions.")
            return nil
        }
        return beginAction(kind, admitted: row)
    }

    public mutating func beginContributorAction(
        _ kind: ProcessActionKind, contributor: ContributorID,
        process: ProcessIdentity
    ) -> ActionEffect? {
        guard actionPanel == nil, !diagnosis.isVisible,
            let row = contributorProcesses(for: contributor).first(where: { $0.process == process })
        else { return nil }
        overview.select(contributor)
        return beginAction(kind, admitted: row)
    }

    private mutating func beginAction(_ kind: ProcessActionKind, admitted row: HeavyProcess) -> ActionEffect?
    {
        switch kind {
        case .terminate:
            actionPanel = ActionPanel(process: row, phase: .confirmTermination)
            return nil
        case .message:
            setActionNotice(ProviderRuntimeAvailability.messagingUnavailableReason)
            return nil
        case .focus:
            actionPanel = ActionPanel(process: row, phase: .focusing)
            return .focus(row)
        }
    }

    /// A launch group names one session, which is all focus needs: it targets the group's runtime
    /// when its processes agree on exactly one.
    private mutating func beginFocus(on group: SessionGroup) -> ActionEffect? {
        let runtimes = Set(group.processes.filter { !$0.isHistorical }.compactMap(\.attribution.runtime))
        guard runtimes.count == 1,
            let row = group.processes.first(where: { !$0.isHistorical && $0.attribution.runtime != nil })
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
            case .confirmTermination, .result:
                actionPanel = nil
                return nil
            case .working, .focusing: break
            }
        }
        let effect = panel.input(input)
        actionPanel = panel
        return effect
    }

    public mutating func actionFinished(_ result: ActionResult) {
        actionPanel?.phase = .result
        actionPanel?.result = result
        actionPanel?.offset = 0
    }
}

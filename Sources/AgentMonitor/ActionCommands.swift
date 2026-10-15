import AgentMonitorActions
import AgentMonitorCore
import AgentMonitorPresentation
import ArgumentParser
import Darwin

/// Exit statuses of the action subcommands; scripts must not retry `uncertain` blindly.
enum ActionExit: Int32 {
    case accepted = 0
    case notDone = 1
    case uncertain = 2
}

enum RecipientChoice: String, ExpressibleByArgument, CaseIterable {
    case root, selected
}

/// The TUI's action contract for one PID: the same fresh identity and recipient checks, a review
/// of the exact target or message, and explicit confirmation, which a script gives with `--yes`.
struct ActionRunner {
    let actions: any ProcessActions
    let lookup: @Sendable (Int32) throws -> HeavyProcess
    let interactive: Bool
    let confirm: (String) -> Bool
    let out: (ReportLine) -> Void
    let err: (ReportLine) -> Void

    static func local(noColor: Bool) -> Self {
        let outColor = ColorPolicy.enabled(noColor: noColor, descriptor: STDOUT_FILENO)
        let errColor = ColorPolicy.enabled(noColor: noColor, descriptor: STDERR_FILENO)
        return
            Self(
                actions: SessionActions.local(), lookup: NativeActions.process,
                interactive: isatty(STDIN_FILENO) == 1,
                confirm: { prompt in
                    print(prompt, terminator: "")
                    return ["y", "yes"].contains(readLine()?.lowercased() ?? "")
                },
                out: { print(outColor ? ANSIText.styled($0) : $0.text) },
                err: {
                    // Keep the review and the error in order when stdout is piped and buffered.
                    fflush(stdout)
                    fputs((errColor ? ANSIText.styled($0) : $0.text) + "\n", stderr)
                })
    }

    func terminate(pid: Int32, yes: Bool) async -> ActionExit {
        await perform {
            let process = try lookup(pid)
            describe(process)
            out(
                ReportLine(
                    "Send SIGTERM to this process only. It may stop work or lose unsaved changes.",
                    style: .warning))
            guard approved("Send SIGTERM? [y/N] ", yes: yes) else { return .notDone }
            try await actions.terminate(process)
            out(ReportLine("SIGTERM accepted for PID \(pid). Exit is not yet confirmed.", style: .success))
            return .accepted
        }
    }

    func message(pid: Int32, text: String, to choice: RecipientChoice, yes: Bool) async -> ActionExit {
        await perform {
            let process = try lookup(pid)
            let draft = try await actions.prepareMessage(for: process)
            let recipient =
                switch choice {
                case .root: draft.recipients.root
                case .selected: draft.recipients.selected
                }
            if let reason = recipient.unavailableReason {
                throw ActionFailure("Recipient unavailable: \(reason)")
            }
            describe(process)
            out(ReportLine("Recipient: \(recipient.label) / \(recipient.id)"))
            out(ReportLine(MessageWording.note(process.attribution.provider), style: .muted))
            out(ReportLine(""))
            for line in draft.message(text).components(separatedBy: "\n") { out(ReportLine(line)) }
            out(ReportLine(""))
            guard approved("Send this message? [y/N] ", yes: yes) else { return .notDone }
            try await actions.send(draft, text: text, recipient: recipient.id)
            out(ReportLine(MessageWording.accepted(draft, recipient: recipient.id), style: .success))
            return .accepted
        }
    }

    func focus(pid: Int32) async -> ActionExit {
        await perform {
            out(
                ReportLine(
                    FocusWording.result(try await actions.focusTerminal(of: try lookup(pid))), style: .success
                ))
            return .accepted
        }
    }

    private func describe(_ process: HeavyProcess) {
        let attribution = process.attribution
        out(ReportLine("Process PID \(process.process.pid): \(process.name)"))
        out(ReportLine("Executable: \(process.executable)"))
        out(
            ReportLine(
                "Attributed session: \(attribution.provider?.rawValue ?? "unknown")/\(attribution.threadID ?? "unresolved")"
            ))
    }

    private func approved(_ prompt: String, yes: Bool) -> Bool {
        if yes { return true }
        guard interactive else {
            err(
                ReportLine(
                    "Confirmation needs an interactive terminal; pass --yes to confirm from a script.",
                    style: .failure))
            return false
        }
        guard confirm(prompt) else {
            err(ReportLine("Cancelled. Nothing was done.", style: .muted))
            return false
        }
        return true
    }

    private func perform(_ body: () async throws -> ActionExit) async -> ActionExit {
        do {
            return try await body()
        } catch let failure as ActionFailure {
            err(ReportLine(failure.message, style: failure.uncertain ? .warning : .failure))
            return failure.uncertain ? .uncertain : .notDone
        } catch {
            err(ReportLine(error.localizedDescription, style: .failure))
            return .notDone
        }
    }
}

private func finish(_ exit: ActionExit) throws {
    switch exit {
    case .accepted: return
    case .notDone, .uncertain: throw ExitCode(exit.rawValue)
    }
}

struct ColorOption: ParsableArguments {
    @Flag(help: "Disable colors, like NO_COLOR.")
    var noColor = false
}

struct KillCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kill",
        abstract: "Send SIGTERM to one process after showing it and asking for confirmation.",
        discussion: "Exit status: 0 accepted (exit not yet confirmed), 1 nothing was done.")

    @Option(help: "PID of the process; its identity is checked again before signaling.")
    var pid: Int32

    @Flag(help: "Confirm without a prompt; required when stdin is not a terminal.")
    var yes = false

    @OptionGroup var color: ColorOption

    func run() async throws {
        try finish(await ActionRunner.local(noColor: color.noColor).terminate(pid: pid, yes: yes))
    }
}

struct MessageCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "message",
        abstract: "Message the Codex or Claude Code session of a process after reviewing it.",
        discussion: """
            The selected PID and process name are prepended. Exit status: 0 accepted (delivery and \
            action not confirmed), 1 nothing was sent, 2 the message may have been accepted; check \
            the session before retrying.
            """)

    @Option(help: "PID of the process whose session receives the message.")
    var pid: Int32

    @Option(help: "Message text, 1-4000 characters.")
    var text: String

    @Option(help: "Codex recipient: root (default) or selected, the agent that launched the process.")
    var to: RecipientChoice = .root

    @Flag(help: "Confirm without a prompt; required when stdin is not a terminal.")
    var yes = false

    @OptionGroup var color: ColorOption

    func run() async throws {
        try finish(
            await ActionRunner.local(noColor: color.noColor).message(pid: pid, text: text, to: to, yes: yes))
    }
}

struct FocusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus",
        abstract: "Bring the terminal hosting a process's agent session to the front.",
        discussion: "Terminal.app tabs are selected; other apps are only activated. Exit status: 0 or 1.")

    @Option(help: "PID of the process whose agent runtime's terminal is focused.")
    var pid: Int32

    @OptionGroup var color: ColorOption

    func run() async throws { try finish(await ActionRunner.local(noColor: color.noColor).focus(pid: pid)) }
}

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
    let out: (String) -> Void
    let err: (String) -> Void

    static func local() -> Self {
        Self(
            actions: SessionActions.local(), lookup: NativeActions.process,
            interactive: isatty(STDIN_FILENO) == 1,
            confirm: { prompt in
                print(prompt, terminator: "")
                return ["y", "yes"].contains(readLine()?.lowercased() ?? "")
            },
            out: { print(TextReport.safe($0)) },
            err: {
                // Keep the review and the error in order when stdout is piped and buffered.
                fflush(stdout)
                fputs(TextReport.safe($0) + "\n", stderr)
            })
    }

    func terminate(pid: Int32, yes: Bool) async -> ActionExit {
        await perform {
            let process = try lookup(pid)
            describe(process)
            out("Send SIGTERM to this process only. It may stop work or lose unsaved changes.")
            guard approved("Send SIGTERM? [y/N] ", yes: yes) else { return .notDone }
            try await actions.terminate(process)
            out("SIGTERM accepted for PID \(pid). Exit is not yet confirmed.")
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
            out("Recipient: \(recipient.label) / \(recipient.id)")
            out(MessageWording.note(process.attribution.provider))
            out("")
            out(draft.message(text))
            out("")
            guard approved("Send this message? [y/N] ", yes: yes) else { return .notDone }
            try await actions.send(draft, text: text, recipient: recipient.id)
            out(MessageWording.accepted(draft, recipient: recipient.id))
            return .accepted
        }
    }

    func focus(pid: Int32) async -> ActionExit {
        await perform {
            out(FocusWording.result(try await actions.focusTerminal(of: try lookup(pid))))
            return .accepted
        }
    }

    private func describe(_ process: HeavyProcess) {
        let attribution = process.attribution
        out("Process PID \(process.process.pid): \(process.name)")
        out("Executable: \(process.executable)")
        out(
            "Attributed session: \(attribution.provider?.rawValue ?? "unknown")/\(attribution.threadID ?? "unresolved")"
        )
    }

    private func approved(_ prompt: String, yes: Bool) -> Bool {
        if yes { return true }
        guard interactive else {
            err("Confirmation needs an interactive terminal; pass --yes to confirm from a script.")
            return false
        }
        guard confirm(prompt) else {
            err("Cancelled. Nothing was done.")
            return false
        }
        return true
    }

    private func perform(_ body: () async throws -> ActionExit) async -> ActionExit {
        do {
            return try await body()
        } catch let failure as ActionFailure {
            err(failure.message)
            return failure.uncertain ? .uncertain : .notDone
        } catch {
            err(error.localizedDescription)
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

struct KillCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kill",
        abstract: "Send SIGTERM to one process after showing it and asking for confirmation.",
        discussion: "Exit status: 0 accepted (exit not yet confirmed), 1 nothing was done.")

    @Option(help: "PID of the process; its identity is checked again before signaling.")
    var pid: Int32

    @Flag(help: "Confirm without a prompt; required when stdin is not a terminal.")
    var yes = false

    func run() async throws { try finish(await ActionRunner.local().terminate(pid: pid, yes: yes)) }
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

    func run() async throws {
        try finish(await ActionRunner.local().message(pid: pid, text: text, to: to, yes: yes))
    }
}

struct FocusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus",
        abstract: "Bring the terminal hosting a process's agent session to the front.",
        discussion: "Terminal.app tabs are selected; other apps are only activated. Exit status: 0 or 1.")

    @Option(help: "PID of the process whose agent runtime's terminal is focused.")
    var pid: Int32

    func run() async throws { try finish(await ActionRunner.local().focus(pid: pid)) }
}

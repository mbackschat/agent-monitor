import AgentMonitorActions
import ArgumentParser
import Foundation
import Synchronization
import Testing

@testable import AgentMonitor
@testable import AgentMonitorCore

private let rootID = "22222222-2222-4222-8222-222222222222"
private let childID = "11111111-1111-4111-8111-111111111111"

private final class FakeActions: ProcessActions {
    let calls = Mutex<[String]>([])
    let failure: ActionFailure?
    init(failure: ActionFailure? = nil) { self.failure = failure }

    func terminate(_ process: HeavyProcess) async throws {
        calls.withLock { $0.append("terminate \(process.process.pid)") }
        if let failure { throw failure }
    }
    func prepareMessage(for process: HeavyProcess) async throws -> MessageDraft {
        MessageDraft(
            process: process,
            recipients: MessageRecipients(
                root: AgentRecipient(id: rootID, label: "Root agent"),
                selected: AgentRecipient(id: childID, label: "Selected agent")))
    }
    func send(_ draft: MessageDraft, text: String, recipient: String) async throws {
        calls.withLock { $0.append("send \(recipient) \(text)") }
        if let failure { throw failure }
    }
    func focusTerminal(of process: HeavyProcess) async throws -> FocusOutcome {
        calls.withLock { $0.append("focus \(process.process.pid)") }
        if let failure { throw failure }
        return .session(application: "Terminal", tty: "/dev/ttys019")
    }
}

private final class Console: Sendable {
    let output = Mutex<[String]>([])
    let errors = Mutex<[String]>([])
    let prompts = Mutex<[String]>([])
}

private func runner(
    _ actions: FakeActions, console: Console, interactive: Bool = true, answer: Bool = true
) -> ActionRunner {
    ActionRunner(
        actions: actions,
        lookup: { pid in
            guard pid == 42 else { throw ActionFailure("No process with PID \(pid).") }
            return HeavyProcess(
                process: ProcessIdentity(pid: 42, startMicroseconds: 1), executable: "/fixture/worker",
                name: "worker", cpuPercent: nil, footprintBytes: nil, cwd: nil, command: nil,
                metadataStatus: .markerRead,
                attribution: Attribution(
                    provider: .codex, evidence: .marker, context: .terminal, threadID: childID,
                    rootSessionID: rootID, runtime: ProcessIdentity(pid: 40, startMicroseconds: 1),
                    terminal: "ttys019", runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []))
        },
        interactive: interactive,
        confirm: { prompt in
            console.prompts.withLock { $0.append(prompt) }
            return answer
        },
        out: { line in console.output.withLock { $0.append(line) } },
        err: { line in console.errors.withLock { $0.append(line) } })
}

@Test func killShowsTheTargetAndSignalsOnlyAfterConfirmation() async {
    let actions = FakeActions()
    let console = Console()
    let exit = await runner(actions, console: console).terminate(pid: 42, yes: false)
    #expect(exit == .accepted)
    #expect(actions.calls.withLock { $0 } == ["terminate 42"])
    #expect(console.output.withLock { $0.joined() }.contains("/fixture/worker"))
    #expect(console.prompts.withLock { $0.count } == 1)
    #expect(console.output.withLock { $0.last ?? "" }.contains("SIGTERM accepted for PID 42"))
}

@Test func declinedConfirmationDoesNothing() async {
    let actions = FakeActions()
    let exit = await runner(actions, console: Console(), answer: false).terminate(pid: 42, yes: false)
    #expect(exit == .notDone)
    #expect(actions.calls.withLock { $0 }.isEmpty)
}

// Scripts must opt in explicitly; a pipe cannot answer the prompt.
@Test func nonInteractiveActionsNeedYes() async {
    let actions = FakeActions()
    let console = Console()
    let refused = await runner(actions, console: console, interactive: false).terminate(pid: 42, yes: false)
    #expect(refused == .notDone)
    #expect(actions.calls.withLock { $0 }.isEmpty)
    #expect(console.errors.withLock { $0.joined() }.contains("--yes"))
    let accepted = await runner(actions, console: console, interactive: false)
        .message(pid: 42, text: "Look", to: .root, yes: true)
    #expect(accepted == .accepted)
    #expect(console.prompts.withLock { $0 }.isEmpty)
}

@Test(arguments: [(RecipientChoice.root, rootID), (.selected, childID)])
func messageGoesToTheChosenVerifiedRecipientWithTheReviewedText(choice: RecipientChoice, recipient: String)
    async
{
    let actions = FakeActions()
    let console = Console()
    let exit = await runner(actions, console: console).message(
        pid: 42, text: "Please check.", to: choice, yes: false)
    #expect(exit == .accepted)
    #expect(actions.calls.withLock { $0 } == ["send \(recipient) Please check."])
    let review = console.output.withLock { $0.joined(separator: "\n") }
    #expect(review.contains("[Agent Monitor: selected process PID 42 (worker)]\nPlease check."))
    #expect(review.contains(recipient))
}

@Test func uncertainSendHasItsOwnExitCode() async {
    let actions = FakeActions(failure: .uncertain("The message may have been accepted."))
    let console = Console()
    let exit = await runner(actions, console: console).message(pid: 42, text: "Hi", to: .root, yes: true)
    #expect(exit == .uncertain)
    #expect(exit.rawValue == 2)
    #expect(console.errors.withLock { $0.joined() }.contains("may have been accepted"))
}

@Test func focusNeedsNoConfirmationAndReportsFailures() async {
    let console = Console()
    let focused = await runner(FakeActions(), console: console).focus(pid: 42)
    #expect(focused == .accepted)
    #expect(console.prompts.withLock { $0 }.isEmpty)
    #expect(console.output.withLock { $0.joined() }.contains("Selected the session on ttys019 in Terminal"))
    let missing = await runner(FakeActions(), console: console).focus(pid: 7)
    #expect(missing == .notDone)
    #expect(console.errors.withLock { $0.joined() }.contains("No process with PID 7"))
}

@Test func subcommandsParseAndKeepTheReportAsDefault() throws {
    #expect(try AgentMonitorCommand.parseAsRoot(["kill", "--pid", "42"]) is KillCommand)
    #expect(try AgentMonitorCommand.parseAsRoot(["focus", "--pid", "42"]) is FocusCommand)
    let message = try #require(
        try AgentMonitorCommand.parseAsRoot(["message", "--pid", "42", "--text", "Hi", "--to", "selected"])
            as? MessageCommand)
    #expect(message.to == .selected)
    #expect(throws: (any Error).self) { try AgentMonitorCommand.parseAsRoot(["message", "--pid", "42"]) }
    #expect(try AgentMonitorCommand.parseAsRoot(["--cpu", "10"]) is AgentMonitorCommand)
    let help = AgentMonitorCommand.helpMessage()
    for name in ["kill", "message", "focus"] { #expect(help.contains(name)) }
}

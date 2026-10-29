import AgentMonitorActions
import AgentMonitorPresentation
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
    let lookups = Mutex<[Int32]>([])
    let styles = Mutex<[String: ReportLine.Style]>([:])
}

private func runner(
    _ actions: FakeActions, console: Console, interactive: Bool = true, answer: Bool = true
) -> ActionRunner {
    ActionRunner(
        actions: actions,
        lookup: { pid in
            console.lookups.withLock { $0.append(pid) }
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
        out: { line in
            console.output.withLock { $0.append(line.text) }
            console.styles.withLock { $0[line.text] = line.style }
        },
        err: { line in
            console.errors.withLock { $0.append(line.text) }
            console.styles.withLock { $0[line.text] = line.style }
        })
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
        .terminate(pid: 42, yes: true)
    #expect(accepted == .accepted)
    #expect(console.prompts.withLock { $0 }.isEmpty)
}

@Test func uncertainActionHasItsOwnExitCode() async {
    let actions = FakeActions(failure: .uncertain("The action may have been accepted."))
    let console = Console()
    let exit = await runner(actions, console: console).terminate(pid: 42, yes: true)
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
    #expect(try AgentMonitorCommand.parseAsRoot(["message"]) is MessageCommand)
    #expect(throws: (any Error).self) {
        try AgentMonitorCommand.parseAsRoot(["message", "--pid", "42", "--text", "Unsent"])
    }
    #expect(try AgentMonitorCommand.parseAsRoot(["--cpu", "10"]) is AgentMonitorCommand)
    let help = AgentMonitorCommand.helpMessage()
    for name in ["kill", "message", "focus"] { #expect(help.contains(name)) }
}

@Test func actionOutputCarriesRolesForWarningsResultsAndErrors() async {
    let console = Console()
    _ = await runner(FakeActions(), console: console).terminate(pid: 42, yes: true)
    let styles = console.styles.withLock { $0 }
    #expect(styles.first { $0.key.hasPrefix("Send SIGTERM") }?.value == .warning)
    #expect(styles.first { $0.key.hasPrefix("SIGTERM accepted") }?.value == .success)
    _ = await runner(FakeActions(), console: console).focus(pid: 7)
    #expect(
        console.styles.withLock { $0 }.first { $0.key.contains("No process with PID 7") }?.value == .failure)
    _ = await runner(FakeActions(failure: .uncertain("May have been accepted.")), console: console)
        .terminate(pid: 42, yes: true)
    #expect(console.styles.withLock { $0 }["May have been accepted."] == .warning)
}

@Test func unavailableMessageRefusesBeforeLookupOrConfirmation() async {
    let actions = FakeActions()
    let console = Console()
    let exit = runner(actions, console: console).message()
    #expect(exit == .notDone)
    #expect(console.errors.withLock { $0 } == [ProviderRuntimeAvailability.messagingUnavailableReason])
    #expect(console.lookups.withLock { $0.isEmpty })
    #expect(console.output.withLock { $0.isEmpty })
    #expect(console.prompts.withLock { $0.isEmpty })
    #expect(actions.calls.withLock { $0.isEmpty })
}

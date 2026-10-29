import AgentMonitorActions
import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private let childID = "11111111-1111-4111-8111-111111111111"
private let rootID = "22222222-2222-4222-8222-222222222222"

private func workload(
    start: UInt64 = 1, context: RuntimeContext = .terminal,
    runtime: ProcessIdentity? = ProcessIdentity(pid: 700, startMicroseconds: 1)
) -> HeavyProcess {
    HeavyProcess(
        process: ProcessIdentity(pid: 701, startMicroseconds: start),
        executable: "/fixture/worker", name: "worker", cpuPercent: 80, footprintBytes: 2_000_000_000,
        cwd: nil, command: nil, metadataStatus: .markerRead,
        attribution: Attribution(
            provider: .codex, evidence: .marker,
            context: context, threadID: childID, rootSessionID: rootID, runtime: runtime,
            terminal: "ttys001", runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []))
}

private func makeActions(
    _ inspect: @escaping @Sendable (HeavyProcess) throws -> HeavyProcess,
    terminate: @escaping @Sendable (HeavyProcess) throws -> Void = { _ in }
) -> SessionActions {
    SessionActions(
        inspect: inspect, terminate: terminate,
        focus: TerminalFocus(
            locate: { _ in throw ActionFailure("Not used.") }, adapters: [], activate: { _ in false }))
}

@Test func staleTerminationDoesNotReachSignalOperation() async {
    let signaled = Mutex(false)
    let actions = makeActions(
        { _ in workload(start: 2) }, terminate: { _ in signaled.withLock { $0 = true } })
    await #expect(throws: (any Error).self) { try await actions.terminate(workload()) }
    #expect(!signaled.withLock { $0 })
}

@Test(arguments: [
    (workload(), true),
    (workload(runtime: nil), false),
    (workload(context: .nonterminal), false),
    (workload(context: .unverified), false),
])
func snapshotFocusEligibilityUsesTheExecutionPrerequisites(process: HeavyProcess, focus: Bool) {
    #expect(SessionActions.canFocusTerminal(process) == focus)
}

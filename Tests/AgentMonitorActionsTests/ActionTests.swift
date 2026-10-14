import AgentMonitorActions
import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private let childID = "11111111-1111-4111-8111-111111111111"
private let rootID = "22222222-2222-4222-8222-222222222222"

private func workload(
    start: UInt64 = 1, thread: String? = childID,
    provider: AgentProvider = .codex,
    runtime: ProcessIdentity? = ProcessIdentity(pid: 700, startMicroseconds: 1)
) -> HeavyProcess {
    HeavyProcess(
        process: ProcessIdentity(pid: 701, startMicroseconds: start),
        executable: "/fixture/worker", name: "worker", cpuPercent: 80, footprintBytes: 2_000_000_000,
        cwd: nil, command: nil, metadataStatus: .markerRead,
        attribution: Attribution(
            provider: provider, evidence: thread == nil ? .ambiguous : .marker,
            context: .terminal, threadID: thread, rootSessionID: rootID, runtime: runtime,
            terminal: "ttys001", runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []))
}

private final class FakeMessaging: AgentMessaging {
    let sent = Mutex<[String]>([])
    func recipients(for thread: String) throws -> MessageRecipients {
        MessageRecipients(
            root: AgentRecipient(id: rootID, label: "Root agent"),
            selected: AgentRecipient(id: thread, label: "Selected agent"))
    }
    func queue(_ message: String, to recipient: String) throws {
        sent.withLock { $0.append(recipient + "\n" + message) }
    }
}

@Test func messageDefaultsToRootAndIncludesWorkloadPID() async throws {
    let provider = FakeMessaging()
    let actions = SessionActions(inspect: { _ in workload() }, terminate: { _ in }, messaging: provider)
    let draft = try await actions.prepareMessage(for: workload())
    #expect(draft.recipients.root.id == rootID)
    let message = draft.message("Please investigate.")
    #expect(message == "[Agent Monitor: selected process PID 701 (worker)]\nPlease investigate.")
    try await actions.send(draft, text: "Please investigate.", recipient: rootID)
    #expect(provider.sent.withLock { $0 } == [rootID + "\n" + message])
}

@Test(arguments: [
    workload(start: 2), workload(thread: rootID), workload(thread: nil), workload(runtime: nil),
])
func changedProcessOrAttributionCannotSend(current: HeavyProcess) async throws {
    let provider = FakeMessaging()
    let currentRow = Mutex(workload())
    let actions = SessionActions(
        inspect: { _ in currentRow.withLock { $0 } }, terminate: { _ in }, messaging: provider)
    let draft = try await actions.prepareMessage(for: workload())
    currentRow.withLock { $0 = current }
    await #expect(throws: (any Error).self) {
        try await actions.send(draft, text: "Investigate", recipient: rootID)
    }
    #expect(provider.sent.withLock { $0.isEmpty })
}

@Test(arguments: [workload(thread: nil), workload(runtime: nil), workload(provider: .claude)])
func unverifiableOrUnsupportedRecipientsAreRejected(row: HeavyProcess) async {
    let actions = SessionActions(inspect: { _ in row }, terminate: { _ in }, messaging: FakeMessaging())
    await #expect(throws: (any Error).self) { try await actions.prepareMessage(for: row) }
}

@Test func staleTerminationDoesNotReachSignalOperation() async {
    let signaled = Mutex(false)
    let actions = SessionActions(
        inspect: { _ in workload(start: 2) },
        terminate: { _ in signaled.withLock { $0 = true } }, messaging: FakeMessaging())
    await #expect(throws: (any Error).self) { try await actions.terminate(workload()) }
    #expect(!signaled.withLock { $0 })
}

@Test func explicitSelectedRecipientAndLiteralTextArePreserved() async throws {
    let provider = FakeMessaging()
    let actions = SessionActions(inspect: { _ in workload() }, terminate: { _ in }, messaging: provider)
    let draft = try await actions.prepareMessage(for: workload())
    let text = "Check $(whoami); `pwd` and 'quotes'"
    try await actions.send(draft, text: text, recipient: childID)
    #expect(provider.sent.withLock { $0 } == [childID + "\n" + draft.message(text)])
    await #expect(throws: (any Error).self) { try await actions.send(draft, text: text, recipient: "other") }
}

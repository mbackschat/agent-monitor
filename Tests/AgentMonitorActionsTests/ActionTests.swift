import AgentMonitorActions
import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private let childID = "11111111-1111-4111-8111-111111111111"
private let rootID = "22222222-2222-4222-8222-222222222222"

private func workload(
    start: UInt64 = 1, thread: String? = childID,
    cpu: Double? = 80, memory: UInt64? = 2_000_000_000, name: String = "worker",
    provider: AgentProvider = .codex, root: String? = rootID,
    context: RuntimeContext = .terminal, evidence: AttributionEvidence? = nil,
    runtime: ProcessIdentity? = ProcessIdentity(pid: 700, startMicroseconds: 1)
) -> HeavyProcess {
    HeavyProcess(
        process: ProcessIdentity(pid: 701, startMicroseconds: start),
        executable: "/fixture/worker", name: name, cpuPercent: cpu, footprintBytes: memory,
        cwd: nil, command: nil, metadataStatus: .markerRead,
        attribution: Attribution(
            provider: provider, evidence: evidence ?? (thread == nil ? .ambiguous : .marker),
            context: context, threadID: thread, rootSessionID: root, runtime: runtime,
            terminal: "ttys001", runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []))
}

private final class FakeMessaging: AgentMessaging {
    let sent = Mutex<[String]>([])
    let single: Bool
    init(single: Bool = false) { self.single = single }
    func recipients(for target: MessageTarget) throws -> MessageRecipients {
        let selected = AgentRecipient(id: target.session, label: "Selected agent")
        return MessageRecipients(
            root: single ? selected : AgentRecipient(id: rootID, label: "Root agent"), selected: selected)
    }
    func send(_ message: String, to recipient: String, for target: MessageTarget) throws {
        sent.withLock { $0.append(recipient + "\n" + message) }
    }
}

private func makeActions(
    _ inspect: @escaping @Sendable (HeavyProcess) throws -> HeavyProcess,
    terminate: @escaping @Sendable (HeavyProcess) throws -> Void = { _ in },
    codex: FakeMessaging = FakeMessaging(), claude: FakeMessaging = FakeMessaging(single: true)
) -> SessionActions {
    SessionActions(
        inspect: inspect, terminate: terminate, codex: codex, claude: claude,
        focus: TerminalFocus(
            locate: { _ in throw ActionFailure("Not used.") }, adapters: [], activate: { _ in false }))
}

@Test func messageDefaultsToRootAndIncludesWorkloadPID() async throws {
    let provider = FakeMessaging()
    let actions = makeActions({ _ in workload() }, codex: provider)
    let draft = try await actions.prepareMessage(for: workload())
    #expect(draft.recipients.root.id == rootID)
    let message = draft.message("Please investigate.")
    #expect(
        message
            == "[Agent Monitor: selected process PID 701 (worker)]\nSample time: unavailable\nCPU: 80.0% (100% = one core)\nMemory footprint: 2.00 GB\n\nPlease investigate."
    )
    try await actions.send(draft, text: "Please investigate.", recipient: rootID)
    #expect(provider.sent.withLock { $0 } == [rootID + "\n" + message])
}

@Test(arguments: [
    workload(start: 2), workload(thread: rootID), workload(thread: nil), workload(runtime: nil),
])
func changedProcessOrAttributionCannotSend(current: HeavyProcess) async throws {
    let provider = FakeMessaging()
    let currentRow = Mutex(workload())
    let actions = makeActions({ _ in currentRow.withLock { $0 } }, codex: provider)
    let draft = try await actions.prepareMessage(for: workload())
    currentRow.withLock { $0 = current }
    await #expect(throws: (any Error).self) {
        try await actions.send(draft, text: "Investigate", recipient: rootID)
    }
    #expect(provider.sent.withLock { $0.isEmpty })
}

@Test(arguments: [workload(thread: nil), workload(runtime: nil), workload(thread: "not-a-uuid")])
func unverifiableRecipientsAreRejected(row: HeavyProcess) async {
    let actions = makeActions({ _ in row })
    await #expect(throws: (any Error).self) { try await actions.prepareMessage(for: row) }
}

@Test func staleTerminationDoesNotReachSignalOperation() async {
    let signaled = Mutex(false)
    let actions = makeActions(
        { _ in workload(start: 2) }, terminate: { _ in signaled.withLock { $0 = true } })
    await #expect(throws: (any Error).self) { try await actions.terminate(workload()) }
    #expect(!signaled.withLock { $0 })
}

@Test func explicitSelectedRecipientAndLiteralTextArePreserved() async throws {
    let provider = FakeMessaging()
    let actions = makeActions({ _ in workload() }, codex: provider)
    let draft = try await actions.prepareMessage(for: workload())
    let text = "Check $(whoami); `pwd` and 'quotes'"
    try await actions.send(draft, text: text, recipient: childID)
    #expect(provider.sent.withLock { $0 } == [childID + "\n" + draft.message(text)])
    await #expect(throws: (any Error).self) { try await actions.send(draft, text: text, recipient: "other") }
}

@Test func claudeRowsRouteOnlyToTheClaudeAdapter() async throws {
    let codex = FakeMessaging()
    let claude = FakeMessaging(single: true)
    let row = workload(provider: .claude, root: nil)
    let actions = makeActions({ _ in row }, codex: codex, claude: claude)
    let draft = try await actions.prepareMessage(for: row)
    #expect(draft.recipients.choices.map(\.id) == [childID])
    try await actions.send(draft, text: "Investigate", recipient: childID)
    #expect(claude.sent.withLock { $0 } == [childID + "\n" + draft.message("Investigate")])
    #expect(codex.sent.withLock { $0.isEmpty })
}

@Test(arguments: [
    (workload(), true, true),
    (workload(thread: nil), false, true),
    (workload(thread: "invalid"), false, true),
    (workload(runtime: nil), false, false),
    (workload(context: .nonterminal), true, false),
    (workload(context: .unverified), false, false),
    (workload(evidence: .ambiguous), false, true),
    (workload(evidence: .runtimeOnly), false, true),
    // A listed session has no marker-carried inbox, so messaging stays closed.
    (workload(evidence: .sessionRegistry), false, true),
])
func snapshotEligibilityUsesTheExecutionPrerequisites(
    process: HeavyProcess, message: Bool, focus: Bool
) {
    #expect(SessionActions.canMessage(process) == message)
    #expect(SessionActions.canFocusTerminal(process) == focus)
}

@Test func preparedMessageIncludesFrozenResourcesAndTimestampWithoutChangingUserText() {
    let recipient = AgentRecipient(id: rootID, label: "Root agent")
    let draft = MessageDraft(
        process: workload(name: "worker\nforged"),
        recipients: MessageRecipients(root: recipient, selected: recipient),
        sampledAt: Date(timeIntervalSince1970: 0))
    #expect(draft.context.contains("worker�forged"))
    #expect(draft.context.contains("Sample time: 1970-01-01T00:00:00Z"))
    #expect(draft.context.contains("CPU: 80.0% (100% = one core)"))
    #expect(draft.context.contains("Memory footprint: 2.00 GB"))
    #expect(
        draft.message("Check `literal` text.\nPlease.") == draft.context
            + "\n\nCheck `literal` text.\nPlease.")
}

@Test func unavailableMessageResourcesAndTimeAreExplicitInsteadOfFabricatedZeroes() {
    let recipient = AgentRecipient(id: rootID, label: "Root agent")
    let draft = MessageDraft(
        process: workload(cpu: nil, memory: nil),
        recipients: MessageRecipients(root: recipient, selected: recipient))
    #expect(draft.context.contains("Sample time: unavailable"))
    #expect(draft.context.contains("CPU: unavailable"))
    #expect(draft.context.contains("Memory footprint: unavailable"))
}

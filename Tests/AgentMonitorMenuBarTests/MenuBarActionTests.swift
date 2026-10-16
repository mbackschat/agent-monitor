import AgentMonitorActions
import AgentMonitorCore
import AgentMonitorPresentation
import Foundation
import Synchronization
import Testing

@testable import AgentMonitorMenuBar

private final class FakeActions: ProcessActions, Sendable {
    let calls = Mutex<[String]>([])
    let recipients = Mutex(
        MessageRecipients(
            root: AgentRecipient(id: "root", label: "Root agent"),
            selected: AgentRecipient(id: "child", label: "Selected agent")))
    let sendFailure: ActionFailure?
    let prepare: (@Sendable () async throws -> Void)?

    init(sendFailure: ActionFailure? = nil, prepare: (@Sendable () async throws -> Void)? = nil) {
        self.sendFailure = sendFailure
        self.prepare = prepare
    }

    func terminate(_ process: HeavyProcess) async throws {
        calls.withLock { $0.append("terminate \(process.process.pid)") }
    }
    func prepareMessage(for process: HeavyProcess) async throws -> MessageDraft {
        calls.withLock { $0.append("prepare") }
        try await prepare?()
        return MessageDraft(
            process: process,
            recipients: recipients.withLock { $0 })
    }
    func send(_ draft: MessageDraft, text: String, recipient: String) async throws {
        calls.withLock { $0.append("send \(recipient): \(draft.message(text))") }
        if let sendFailure { throw sendFailure }
    }
    func focusTerminal(of process: HeavyProcess) async throws -> FocusOutcome {
        calls.withLock { $0.append("focus \(process.process.pid)") }
        return .session(application: "Terminal", tty: "/dev/ttys001")
    }
}

func menuBarFixture(
    pids: [Int32] = [42001], name: String = "swift-frontend", project: String = "sample-app",
    cpu: Double = 184.6, memoryBytes: UInt64 = 1_420_000_000,
    provider: String = "codex", sessionID: String = "11111111-1111-4111-8111-111111111111",
    sharedRuntime: Bool = false
) throws -> MonitoringSnapshot {
    let rows = try pids.map { pid in
        try JSONDecoder().decode(
            HeavyProcess.self,
            from: Data(
                """
                {"process":{"pid":\(pid),"startMicroseconds":1},"executable":"/fixture/\(name)",
                "name":"\(name)","cpuPercent":\(cpu),"footprintBytes":\(memoryBytes),"cwd":"/projects/\(project)",
                "metadataStatus":"markerRead","attribution":{"provider":"\(provider)","evidence":"\(sharedRuntime ? "ambiguous" : "marker")",
                "context":"\(sharedRuntime ? "nonterminal" : "terminal")","threadID":\(sharedRuntime ? "null" : "\"\(sessionID)\""),
                "runtime":{"pid":\(sharedRuntime ? pid : 41000),"startMicroseconds":1},"terminal":"ttys001",
                "runtimeDirectory":"/projects/\(project)","candidateThreadIDs":\(sharedRuntime ? "[\"11111111-1111-4111-8111-111111111111\",\"22222222-2222-4222-8222-222222222222\"]" : "[]"),"ancestry":[]}}
                """.utf8))
    }
    return MonitoringSnapshot(
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1,
        cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
        sampledProcessCount: 42, unreadableProcessCount: 0, findings: rows)
}

@MainActor private func readyModel(_ actions: FakeActions) async throws -> MenuBarModel {
    let snapshot = try menuBarFixture()
    let model = MenuBarModel(actions: actions) { _, _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    return model
}

@Test @MainActor func menuBarTerminationRequiresConfirmationAndKeepsFrozenIdentity() async throws {
    let actions = FakeActions()
    let model = try await readyModel(actions)
    let row = try #require(model.report.rows.first)
    model.begin(.terminate, row: .process(row.process))
    #expect(actions.calls.withLock { $0.isEmpty })
    model.report.receive(
        MonitoringSnapshot(
            timestamp: Date(), intervalSeconds: 1,
            cpuThresholdPercent: 25, memoryThresholdBytes: 1, sampledProcessCount: 0,
            unreadableProcessCount: 0, findings: []))
    model.input(.confirm)
    model.input(.confirm)
    await model.waitForAction()
    #expect(actions.calls.withLock { $0 } == ["terminate 42001"])
    await model.stop()
}

@Test @MainActor func menuBarMessageRequiresReviewUsesRootAndDoesNotRetryUncertainSend() async throws {
    let actions = FakeActions(sendFailure: .uncertain("Check delivery before retrying."))
    let model = try await readyModel(actions)
    let row = try #require(model.report.rows.first)
    model.begin(.message, row: .process(row.process))
    await model.waitForAction()
    model.setMessage("Please inspect this workload.")
    model.input(.confirm)
    #expect(actions.calls.withLock { $0 } == ["prepare"])
    model.input(.review)
    #expect(model.report.actionPanel?.recipient?.id == "root")
    model.input(.confirm)
    await model.waitForAction()
    model.input(.confirm)
    #expect(
        actions.calls.withLock { $0 } == [
            "prepare",
            "send root: [Agent Monitor: selected process PID 42001 (swift-frontend)]\nSample time: 1970-01-01T00:00:00Z\nCPU: 184.6% (100% = one core)\nMemory footprint: 1.42 GB\n\nPlease inspect this workload.",
        ])
    #expect(model.lastActionResult == .uncertain("Check delivery before retrying."))
    await model.stop()
    #expect(model.savedMessage == nil)
}

@Test @MainActor func menuBarFocusUsesTheSelectedProcessAndClosedPanelCannotAct() async throws {
    let actions = FakeActions()
    let model = try await readyModel(actions)
    let row = try #require(model.report.rows.first)
    model.begin(.focus, row: .process(row.process))
    await model.waitForAction()
    #expect(actions.calls.withLock { $0 } == ["focus 42001"])
    await model.stop()
    model.begin(.terminate, row: .process(row.process))
    model.input(.confirm)
    #expect(actions.calls.withLock { $0 } == ["focus 42001"])
}

@Test @MainActor func vanishedNativeRowCannotActOnAnotherSelection() async throws {
    let actions = FakeActions()
    let model = try await readyModel(actions)
    model.begin(.terminate, row: .process(ProcessIdentity(pid: 7, startMicroseconds: 2)))
    #expect(model.report.actionPanel == nil)
    await model.stop()
}

@Test @MainActor func closingDrainsOwnedActionWorkBeforeReturning() async throws {
    let (events, continuation) = AsyncStream<String>.makeStream()
    let actions = FakeActions(prepare: {
        continuation.yield("started")
        defer { continuation.yield("finished") }
        try await Task.sleep(for: .seconds(3600))
    })
    let model = try await readyModel(actions)
    let row = try #require(model.report.rows.first)
    model.begin(.message, row: .process(row.process))
    var iterator = events.makeAsyncIterator()
    try #require(model.report.actionPanel?.phase == .loading)
    #expect(await iterator.next() == "started")
    await model.stop()
    #expect(await iterator.next() == "finished")
    #expect(model.report.actionPanel == nil)
    #expect(actions.calls.withLock { $0 } == ["prepare"])
}

@Test @MainActor func multiProcessSessionRequiresDisclosureAndTargetsTheChosenChild() async throws {
    let actions = FakeActions()
    let snapshot = try menuBarFixture(pids: [42001, 42002])
    let model = MenuBarModel(actions: actions) { _, _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let process = try #require(model.report.rows.last)
    model.begin(.terminate, row: .process(process.process))
    #expect(model.report.actionPanel == nil)
    model.report.toggleDisclosure()
    model.begin(.terminate, row: .process(process.process))
    #expect(model.report.actionPanel?.process.process == process.process)
    model.input(.confirm)
    await model.waitForAction()
    #expect(actions.calls.withLock { $0 } == ["terminate 42002"])
    await model.stop()
}

@Test(arguments: [false, true])
@MainActor func dismissedMessageRestoresTextAndRecipientAfterFreshPreparation(reviewing: Bool) async throws {
    let actions = FakeActions()
    let model = try await readyModel(actions)
    let row = try #require(model.report.rows.first)
    model.begin(.message, row: .process(row.process))
    await model.waitForAction()
    model.setMessage("Please inspect this workload.\nKeep this draft.")
    model.input(.recipient)
    if reviewing { model.input(.review) }
    model.close()
    model.open()
    await model.waitForCollection()
    model.begin(.message, row: .process(row.process))
    await model.waitForAction()
    #expect(model.report.actionPanel?.phase == .compose)
    #expect(model.report.actionPanel?.text == "Please inspect this workload.\nKeep this draft.")
    #expect(model.report.actionPanel?.recipient?.id == "child")
    model.input(.confirm)
    #expect(actions.calls.withLock { $0 } == ["prepare", "prepare"])
    await model.stop()
}

@Test @MainActor func explicitlyCancelledMessageDoesNotReturnAfterReopening() async throws {
    let actions = FakeActions()
    let model = try await readyModel(actions)
    let row = try #require(model.report.rows.first)
    model.begin(.message, row: .process(row.process))
    await model.waitForAction()
    model.setMessage("Discard this text.")
    model.input(.escape)
    model.close()
    model.open()
    await model.waitForCollection()
    model.begin(.message, row: .process(row.process))
    await model.waitForAction()
    #expect(model.report.actionPanel?.text == "")
    await model.stop()
}

@Test(arguments: [false, true])
@MainActor func restoredDraftKeepsTextWhenTargetOrRecipientCannotBeVerified(targetFailure: Bool) async throws
{
    let fails = Mutex(false)
    let actions = FakeActions(prepare: {
        if fails.withLock({ $0 }) { throw ActionFailure("Process lifetime changed.") }
    })
    let model = try await readyModel(actions)
    let row = try #require(model.report.rows.first)
    model.begin(.message, row: .process(row.process))
    await model.waitForAction()
    model.setMessage("Recover this text.")
    model.input(.recipient)
    model.close()
    if targetFailure {
        fails.withLock { $0 = true }
    } else {
        actions.recipients.withLock {
            $0 = MessageRecipients(
                root: AgentRecipient(id: "root", label: "Root agent"),
                selected: AgentRecipient(id: "replacement", label: "Replacement agent"))
        }
    }
    model.open()
    await model.waitForCollection()
    model.resumeMessage()
    await model.waitForAction()
    #expect(model.report.actionPanel?.phase == .result)
    #expect(model.savedMessage?.text == "Recover this text.")
    #expect(model.savedMessage?.process == row)
    model.input(.confirm)
    #expect(actions.calls.withLock { $0 } == ["prepare", "prepare"])
    model.input(.escape)
    model.discardMessage()
    #expect(model.savedMessage == nil)
    await model.stop()
}

@Test @MainActor func savedMessageCannotBeOverwrittenByAnotherProcessOrAnEmptyComposer() async throws {
    let actions = FakeActions()
    let model = try await readyModel(actions)
    let row = try #require(model.report.rows.first)
    model.begin(.message, row: .process(row.process))
    await model.waitForAction()
    model.close()
    #expect(model.savedMessage == nil)
    model.open()
    await model.waitForCollection()
    model.begin(.message, row: .process(row.process))
    await model.waitForAction()
    model.setMessage("Retain original target.")
    model.close()
    model.open()
    await model.waitForCollection()
    model.begin(.message, row: .process(ProcessIdentity(pid: row.process.pid, startMicroseconds: 2)))
    #expect(model.report.actionPanel == nil)
    #expect(model.savedMessage?.process.process == row.process)
    #expect(model.savedMessage?.text == "Retain original target.")
    await model.stop()
}

@Test @MainActor func nativeSessionFocusUsesTheSharedVerifiedAction() async throws {
    let actions = FakeActions()
    let snapshot = try menuBarFixture(pids: [42001, 42002])
    let model = MenuBarModel(actions: actions) { _, _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let group = try #require(model.report.groups.first)
    model.begin(.focus, row: .group(group.id))
    await model.waitForAction()
    #expect(actions.calls.withLock { $0 } == ["focus 42001"])
    #expect(model.report.actionPanel?.phase == .result)
    await model.stop()
}

@Test @MainActor func copyingPreparedMessageMatchesReviewAndSendWithoutSendingOrTouchingTheRealClipboard()
    async throws
{
    let actions = FakeActions()
    let model = try await readyModel(actions)
    var copied = ""
    let noDraft = model.copyMessage(using: {
        copied = $0
        return true
    })
    #expect(!noDraft)
    let row = try #require(model.report.rows.first)
    model.begin(.message, row: .process(row.process))
    await model.waitForAction()
    model.setMessage("Please inspect this workload.")
    let success = model.copyMessage(using: {
        copied = $0
        return true
    })
    #expect(success)
    #expect(model.messageCopyStatus == "Copied")
    #expect(copied.contains("CPU: 184.6%"))
    #expect(copied.contains("Memory footprint: 1.42 GB"))
    #expect(copied.contains("Sample time: 1970-01-01T00:00:00Z"))
    #expect(actions.calls.withLock { $0 } == ["prepare"])
    model.input(.review)
    let panel = try #require(model.report.actionPanel)
    #expect(copied == panel.draft?.message(panel.text))
    let failure = model.copyMessage(using: { _ in false })
    #expect(!failure)
    #expect(model.messageCopyStatus == "Copy failed")
    model.input(.confirm)
    await model.waitForAction()
    #expect(actions.calls.withLock { $0.last } == "send root: " + copied)
    let afterSend = model.copyMessage(using: { _ in
        Issue.record("Copied after send")
        return true
    })
    #expect(!afterSend)
    await model.stop()
}

@Test @MainActor func restoredMessageKeepsOriginalObservationTimeAndResources() async throws {
    let actions = FakeActions()
    let model = try await readyModel(actions)
    let row = try #require(model.report.rows.first)
    model.begin(.message, row: .process(row.process))
    await model.waitForAction()
    model.setMessage("Keep these observations.")
    let original = try #require(model.report.actionPanel?.draft?.message("Keep these observations."))
    model.close()
    model.open()
    await model.waitForCollection()
    model.report.receive(
        MonitoringSnapshot(
            timestamp: Date(timeIntervalSince1970: 60), intervalSeconds: 1,
            cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
            sampledProcessCount: 1, unreadableProcessCount: 0, findings: [row]))
    model.resumeMessage()
    await model.waitForAction()
    #expect(model.report.actionPanel?.draft?.message("Keep these observations.") == original)
    await model.stop()
}

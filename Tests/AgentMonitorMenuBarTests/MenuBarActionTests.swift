import AgentMonitorActions
import AgentMonitorCore
import AgentMonitorPresentation
import Foundation
import Synchronization
import Testing

@testable import AgentMonitorMenuBar

private final class FakeActions: ProcessActions, Sendable {
    let calls = Mutex<[String]>([])
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
            recipients: MessageRecipients(
                root: AgentRecipient(id: "root", label: "Root agent"),
                selected: AgentRecipient(id: "child", label: "Selected agent")))
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
    provider: String = "codex", sessionID: String = "11111111-1111-4111-8111-111111111111"
) throws -> MonitoringSnapshot {
    let rows = try pids.map { pid in
        try JSONDecoder().decode(
            HeavyProcess.self,
            from: Data(
                """
                {"process":{"pid":\(pid),"startMicroseconds":1},"executable":"/fixture/\(name)",
                "name":"\(name)","cpuPercent":184.6,"footprintBytes":1420000000,"cwd":"/projects/\(project)",
                "metadataStatus":"markerRead","attribution":{"provider":"\(provider)","evidence":"marker",
                "context":"terminal","threadID":"\(sessionID)",
                "runtime":{"pid":41000,"startMicroseconds":1},"terminal":"ttys001",
                "runtimeDirectory":"/projects/\(project)","candidateThreadIDs":[],"ancestry":[]}}
                """.utf8))
    }
    return MonitoringSnapshot(
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1,
        cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
        sampledProcessCount: 42, unreadableProcessCount: 0, findings: rows)
}

@MainActor private func readyModel(_ actions: FakeActions) async throws -> MenuBarModel {
    let snapshot = try menuBarFixture()
    let model = MenuBarModel(actions: actions) { receive in try await receive(snapshot) }
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
            "send root: [Agent Monitor: selected process PID 42001 (swift-frontend)]\nPlease inspect this workload.",
        ])
    #expect(model.lastActionResult == .uncertain("Check delivery before retrying."))
    await model.stop()
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
    let model = MenuBarModel(actions: actions) { receive in try await receive(snapshot) }
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

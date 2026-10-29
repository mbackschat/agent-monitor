import AgentMonitorActions
import AgentMonitorCore
import AgentMonitorPresentation
import Testing

@testable import AgentMonitorMenuBar

@Suite(.timeLimit(.minutes(1))) struct MenuBarTaskOwnershipTests {
    @Test(arguments: [false, true]) @MainActor
    func reopeningCoalescesTaskAdmissionUntilTheCollectorDrains(restart: Bool) async throws {
        let gate = OwnershipGate()
        let model = MenuBarModel { _, _, _ in await gate.wait() }
        model.setLiveIcon(false)
        model.open()
        try await requireOwnedStart(gate, in: model)
        let original = try #require(model.collection)
        var admitted: Set<Task<Void, Never>> = [original]
        for _ in 0..<200 {
            model.close()
            model.open()
            if let task = model.collection { admitted.insert(task) }
        }
        if !restart { model.close() }
        #expect(admitted.count == 1)
        #expect(await gate.calls == 1)
        await gate.release()
        await model.waitForCollection()
        #expect(await gate.calls == (restart ? 2 : 1))
        await model.stop()
    }

    @Test(arguments: [ProcessActionKind.focus, .terminate]) @MainActor
    func cancelledActionsRemainOwnedAcrossDismissalUntilTheyDrain(kind: ProcessActionKind) async throws {
        let gate = OwnershipGate()
        let snapshot = try menuBarFixture()
        let (received, marker) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let model = MenuBarModel(actions: BlockedActions(gate: gate)) { _, _, receive in
            try await receive(snapshot)
            marker.yield(())
            try await Task.sleep(for: .seconds(3600))
        }
        model.open()
        var signals = received.makeAsyncIterator()
        await signals.next()
        if model.report.snapshot == nil {
            await gate.release()
            await model.stop()
        }
        try #require(model.report.snapshot != nil)
        let row = LiveReportRowID.process(try #require(snapshot.findings.first).process)
        beginOwnedAction(kind, row: row, in: model)
        try #require(model.isPerformingAction)
        try await requireOwnedStart(gate, in: model)
        let original = try #require(model.action)
        var admitted: Set<Task<Void, Never>> = [original]
        var allRejected = true
        for _ in 0..<200 {
            model.close()
            model.open()
            allRejected = allRejected && !model.canBegin(kind, row: row)
            beginOwnedAction(kind, row: row, in: model)
            if let task = model.action { admitted.insert(task) }
        }
        #expect(allRejected)
        #expect(admitted.count == 1)
        await gate.release()
        for task in admitted { await task.value }
        #expect(await gate.calls == 1)
        #expect(model.canBegin(kind, row: row))
        beginOwnedAction(kind, row: row, in: model)
        await model.waitForAction()
        #expect(await gate.calls == 2)
        #expect(model.report.actionPanel?.phase == .result)
        await model.stop()
    }
    @Test @MainActor
    func shutdownClearsPendingRestartAndJoinsTheDrainingCollector() async throws {
        let gate = OwnershipGate()
        let model = MenuBarModel { _, _, _ in await gate.wait() }
        model.setLiveIcon(false)
        model.open()
        try await requireOwnedStart(gate, in: model)
        model.close()
        model.open()
        let (stopping, marker) = AsyncStream<Void>.makeStream()
        var finished = false
        let stop = Task { @MainActor in
            marker.yield(())
            await model.stop()
            finished = true
        }
        var signals = stopping.makeAsyncIterator()
        await signals.next()
        #expect(!finished)
        await gate.release()
        await stop.value
        #expect(finished)
        #expect(model.collection == nil)
        #expect(await gate.calls == 1)
    }

    @Test(arguments: [ProcessActionKind.focus, .terminate]) @MainActor
    func shutdownJoinsCancelledActionWork(kind: ProcessActionKind) async throws {
        let gate = OwnershipGate()
        let snapshot = try menuBarFixture()
        let model = MenuBarModel(actions: BlockedActions(gate: gate)) { _, _, receive in
            try await receive(snapshot)
        }
        model.open()
        await model.waitForCollection()
        beginOwnedAction(kind, row: .process(try #require(snapshot.findings.first).process), in: model)
        try #require(model.isPerformingAction)
        try await requireOwnedStart(gate, in: model)
        let (stopping, marker) = AsyncStream<Void>.makeStream()
        var finished = false
        let stop = Task { @MainActor in
            marker.yield(())
            await model.stop()
            finished = true
        }
        var signals = stopping.makeAsyncIterator()
        await signals.next()
        #expect(!finished)
        #expect(model.isPerformingAction)
        await gate.release()
        await stop.value
        #expect(finished)
        #expect(!model.isPerformingAction)
        #expect(model.action == nil)
    }

}

private actor OwnershipGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private(set) var calls = 0
    private let arrivals = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))

    func wait() async {
        calls += 1
        arrivals.continuation.yield(calls)
        if !released { await withCheckedContinuation { waiters.append($0) } }
    }

    func waitForCalls(_ expected: Int) async -> Bool {
        if calls >= expected { return true }
        for await count in arrivals.stream {
            if count >= expected { return true }
        }
        return false
    }

    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private struct BlockedActions: ProcessActions {
    let gate: OwnershipGate
    func prepareMessage(for process: HeavyProcess) async throws -> MessageDraft {
        Issue.record("Unexpected recipient preparation")
        throw ActionFailure(ProviderRuntimeAvailability.messagingUnavailableReason)
    }
    func terminate(_ process: HeavyProcess) async throws { await gate.wait() }
    func send(_ draft: MessageDraft, text: String, recipient: String) async throws {
        Issue.record("Unexpected send")
        throw ActionFailure(ProviderRuntimeAvailability.messagingUnavailableReason)
    }
    func focusTerminal(of process: HeavyProcess) async throws -> FocusOutcome {
        await gate.wait()
        return .session(application: "Fixture", tty: "fixture")
    }
}

@MainActor private func requireOwnedStart(_ gate: OwnershipGate, in model: MenuBarModel) async throws {
    let started = await gate.waitForCalls(1)
    if !started {
        await gate.release()
        await model.stop()
    }
    try #require(started)
}

@MainActor private func beginOwnedAction(
    _ kind: ProcessActionKind, row: LiveReportRowID, in model: MenuBarModel
) {
    model.begin(kind, row: row)
    if case .terminate = kind { model.input(.confirm) }
}

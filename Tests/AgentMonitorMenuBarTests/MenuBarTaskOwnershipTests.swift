import AgentMonitorActions
import AgentMonitorCore
import AgentMonitorPresentation
import Testing

@testable import AgentMonitorMenuBar

@Suite struct MenuBarTaskOwnershipTests {
    @Test(arguments: [false, true]) @MainActor
    func reopeningCoalescesTaskAdmissionUntilTheCollectorDrains(restart: Bool) async throws {
        let gate = OwnershipGate()
        let model = MenuBarModel { _, _, _ in await gate.wait() }
        model.setLiveIcon(false)
        model.open()
        var starts = gate.starts.makeAsyncIterator()
        #expect(await starts.next() == 1)
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

    @Test @MainActor
    func cancelledActionsRemainOwnedAcrossDismissalUntilTheyDrain() async throws {
        let gate = OwnershipGate()
        let snapshot = try menuBarFixture()
        let (ready, published) = AsyncStream<Void>.makeStream()
        let model = MenuBarModel(actions: BlockedActions(gate: gate)) { _, _, receive in
            try await receive(snapshot)
            published.yield(())
            try await Task.sleep(for: .seconds(3600))
        }
        model.open()
        var samples = ready.makeAsyncIterator()
        await samples.next()
        let row = LiveReportRowID.process(try #require(snapshot.findings.first).process)
        model.begin(.message, row: row)
        var starts = gate.starts.makeAsyncIterator()
        #expect(await starts.next() == 1)
        let original = try #require(model.action)
        var admitted: Set<Task<Void, Never>> = [original]
        var allRejected = true
        for _ in 0..<200 {
            model.close()
            model.open()
            allRejected = allRejected && !model.canBegin(.message, row: row)
            model.begin(.message, row: row)
            model.resumeMessage()
            if let task = model.action { admitted.insert(task) }
        }
        #expect(allRejected)
        #expect(admitted.count == 1)
        await gate.release()
        for task in admitted { await task.value }
        #expect(await gate.calls == 1)
        #expect(model.canBegin(.message, row: row))
        model.begin(.message, row: row)
        await model.waitForAction()
        #expect(await gate.calls == 2)
        #expect(model.report.actionPanel?.phase == .compose)
        await model.stop()
    }
    @Test @MainActor
    func shutdownClearsPendingRestartAndJoinsTheDrainingCollector() async throws {
        let gate = OwnershipGate()
        let model = MenuBarModel { _, _, _ in await gate.wait() }
        model.setLiveIcon(false)
        model.open()
        var starts = gate.starts.makeAsyncIterator()
        #expect(await starts.next() == 1)
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

    @Test @MainActor
    func shutdownJoinsCancelledActionWork() async throws {
        let gate = OwnershipGate()
        let snapshot = try menuBarFixture()
        let model = MenuBarModel(actions: BlockedActions(gate: gate)) { _, _, receive in
            try await receive(snapshot)
        }
        model.open()
        await model.waitForCollection()
        model.begin(.message, row: .process(try #require(snapshot.findings.first).process))
        var starts = gate.starts.makeAsyncIterator()
        #expect(await starts.next() == 1)
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
    nonisolated let starts: AsyncStream<Int>
    private let started: AsyncStream<Int>.Continuation
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private(set) var calls = 0

    init() { (starts, started) = AsyncStream<Int>.makeStream() }

    func wait() async {
        calls += 1
        started.yield(calls)
        if !released { await withCheckedContinuation { waiters.append($0) } }
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
        await gate.wait()
        return MessageDraft(
            process: process,
            recipients: MessageRecipients(
                root: AgentRecipient(id: "root", label: "Root agent"),
                selected: AgentRecipient(id: "root", label: "Root agent")))
    }
    func terminate(_ process: HeavyProcess) async throws { Issue.record("Unexpected termination") }
    func send(_ draft: MessageDraft, text: String, recipient: String) async throws {
        Issue.record("Unexpected send")
    }
    func focusTerminal(of process: HeavyProcess) async throws -> FocusOutcome {
        Issue.record("Unexpected focus")
        return .session(application: "Fixture", tty: "fixture")
    }
}

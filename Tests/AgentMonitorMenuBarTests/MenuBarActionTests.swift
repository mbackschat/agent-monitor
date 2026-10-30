import AgentMonitorActions
import AgentMonitorPresentation
import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore
@testable import AgentMonitorMenuBar

private final class FakeActions: ProcessActions, Sendable {
    let calls = Mutex<[String]>([])
    let focus: (@Sendable () async throws -> Void)?

    init(focus: (@Sendable () async throws -> Void)? = nil) { self.focus = focus }

    func terminate(_ process: HeavyProcess) async throws {
        calls.withLock { $0.append("terminate \(process.process.pid)") }
    }
    func focusTerminal(of process: HeavyProcess) async throws -> FocusOutcome {
        calls.withLock { $0.append("focus \(process.process.pid)") }
        try await focus?()
        return .session(application: "Terminal", tty: "/dev/ttys001")
    }
}

func menuBarFixture(
    pids: [Int32] = [42001], name: String = "swift-frontend", project: String = "sample-app",
    cpu: Double = 184.6, memoryBytes: UInt64 = 1_420_000_000,
    provider: String = "codex", sessionID: String = "11111111-1111-4111-8111-111111111111",
    sharedRuntime: Bool = false
) throws -> MonitoringSnapshot {
    let provider = try #require(AgentProvider(rawValue: provider))
    let rows = pids.map { pid in
        HeavyProcess(
            process: ProcessIdentity(pid: pid, startMicroseconds: 1),
            executable: "/fixture/" + name, name: name, cpuPercent: cpu, footprintBytes: memoryBytes,
            cwd: "/projects/" + project, command: nil, metadataStatus: .markerRead,
            attribution: Attribution(
                provider: provider, evidence: sharedRuntime ? .ambiguous : .marker,
                context: sharedRuntime ? .nonterminal : .terminal,
                threadID: sharedRuntime ? nil : sessionID, rootSessionID: nil,
                runtime: ProcessIdentity(pid: sharedRuntime ? pid : 41000, startMicroseconds: 1),
                terminal: "ttys001", runtimeDirectory: "/projects/" + project,
                candidateThreadIDs: sharedRuntime
                    ? ["11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222"]
                    : [], ancestry: []))
    }
    return MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
            unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1,
        cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
        sampledProcessCount: 42, unreadableProcessCount: 0, findings: rows)
}

@MainActor private func readyModel(_ actions: FakeActions) async throws -> MenuBarModel {
    let snapshot = try menuBarFixture()
    let model = MenuBarModel(actions: actions) { _, _, receive in try await receive(snapshot) }
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
            cpuAccounting: CPUAccounting(
                hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
                unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
            timestamp: Date(), intervalSeconds: 1,
            cpuThresholdPercent: 25, memoryThresholdBytes: 1, sampledProcessCount: 0,
            unreadableProcessCount: 0, findings: []))
    model.input(.confirm)
    model.input(.confirm)
    await model.waitForAction()
    #expect(actions.calls.withLock { $0 } == ["terminate 42001"])
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
    let events = Mutex<[String]>([])
    let actions = FakeActions(focus: {
        events.withLock { $0.append("started") }
        defer { events.withLock { $0.append("finished") } }
        try await Task.sleep(for: .seconds(3600))
    })
    let model = try await readyModel(actions)
    let row = try #require(model.report.rows.first)
    model.begin(.focus, row: .process(row.process))
    let focusing = model.report.actionPanel?.phase == .focusing
    if !focusing { await model.stop() }
    try #require(focusing)
    let deadline = ContinuousClock.now + .seconds(30)
    while events.withLock({ $0.isEmpty }), ContinuousClock.now < deadline {
        await Task.yield()
    }
    let started = events.withLock { $0 == ["started"] }
    if !started { await model.stop() }
    try #require(started)
    await model.stop()
    #expect(events.withLock { $0 } == ["started", "finished"])
    #expect(model.report.actionPanel == nil)
    #expect(actions.calls.withLock { $0 } == ["focus 42001"])
}

@Test @MainActor func unavailableNativeMessagingNeverStartsInjectedActions() async throws {
    let actions = FakeActions()
    let model = try await readyModel(actions)
    let row = try #require(model.report.rows.first)
    let target = LiveReportRowID.process(row.process)
    #expect(!model.canBegin(.message, row: target))
    model.begin(.message, row: target)
    await model.waitForAction()
    #expect(model.report.actionPanel == nil)
    #expect(actions.calls.withLock { $0.isEmpty })
    await model.stop()
}

@Test @MainActor func multiProcessSessionRequiresDisclosureAndTargetsTheChosenChild() async throws {
    let actions = FakeActions()
    let snapshot = try menuBarFixture(pids: [42001, 42002])
    let model = MenuBarModel(actions: actions) { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let process = try #require(model.report.rows.last)
    model.begin(.terminate, row: .process(process.process))
    #expect(model.report.actionPanel == nil)
    model.report.toggleDisclosure()
    model.begin(.terminate, row: .process(process.process))
    #expect(model.report.actionPanel?.processes.first?.process == process.process)
    model.input(.confirm)
    await model.waitForAction()
    #expect(actions.calls.withLock { $0 } == ["terminate 42002"])
    await model.stop()
}

@Test @MainActor func nativeSessionFocusUsesTheSharedVerifiedAction() async throws {
    let actions = FakeActions()
    let snapshot = try menuBarFixture(pids: [42001, 42002])
    let model = MenuBarModel(actions: actions) { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let group = try #require(model.report.groups.first)
    model.begin(.focus, row: .group(group.id))
    await model.waitForAction()
    #expect(actions.calls.withLock { $0 } == ["focus 42001"])
    #expect(model.report.actionPanel?.phase == .result)
    await model.stop()
}

@Test(arguments: [false, true])
@MainActor func returningFromInspectionRetainsTheSelectedRowForFocus(diagnosis: Bool) async throws {
    let snapshot = try menuBarFixture(pids: [42001, 42002])
    let actions = FakeActions()
    let model = MenuBarModel(
        actions: actions, diagnosisSource: { try await menuBarDiagnosisFixture() },
        source: { _, _, receive in try await receive(snapshot) })
    model.report.toggleGrouping()
    model.open()
    await model.waitForCollection()
    let selected = try #require(model.visibleRowIDs.last)
    model.selectRow(selected)
    if diagnosis {
        #expect(model.beginDiagnosis())
        await model.diagnosis.waitForCompletion()
        model.diagnosis.dismiss()
    } else {
        model.begin(.terminate, row: selected)
        try #require(model.report.actionPanel != nil)
        model.input(.escape)
    }
    var focus = MenuBarInitialFocus()
    #expect(focus.open(rows: model.visibleRowIDs, preferred: model.report.selection) == .row(selected))
    #expect(actions.calls.withLock { $0.isEmpty })
    await model.stop()
}

@Test @MainActor func contributorActionsRequireConfirmationWithoutNavigatingAway() async throws {
    let actions = FakeActions()
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel(actions: actions) { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let owner = try #require(model.report.overview.main.first)
    let target = try #require(model.report.contributorProcesses(for: owner).first)
    #expect(!model.canBegin(.message, contributor: owner, process: target.process))
    model.report.inspectContributorProcess(target.process, contributor: owner)
    model.begin(.terminate, contributor: owner, process: target.process)
    #expect(model.report.showsOverview)
    #expect(model.report.overview.inspectedProcess == target.process)
    #expect(actions.calls.withLock { $0.isEmpty })
    model.report.receive(snapshot)
    #expect(model.report.actionPanel?.processes == [target])
    model.input(.confirm)
    await model.waitForAction()
    #expect(actions.calls.withLock { $0 } == ["terminate \(target.process.pid)"])
    model.input(.escape)
    #expect(model.report.showsOverview)
    #expect(model.report.contributorProcessTarget?.process == target.process)
    await model.stop()
    #expect(!model.canBegin(.terminate, contributor: owner, process: target.process))
}

@Test @MainActor func contributorKeyboardReviewsFrozenTargetsBeforeTerminatingAll() async throws {
    let actions = FakeActions()
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel(actions: actions) { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let contributor = ContributorID.section(.remainder)
    model.report.overview.select(contributor)
    let targets = model.report.contributorProcesses(for: contributor)
    try #require(targets.count > 1)
    let inspected = try #require(targets.first)
    let menu = MenuBarContributorActions(
        model: model, node: try #require(model.report.overview.nodes[contributor]))
    for key in ["k", "f"] {
        #expect(menu.shortcut(key, process: inspected.process) == " (\(key) after inspection)")
    }
    model.report.inspectContributorProcess(inspected.process, contributor: contributor)
    for key in ["k", "f"] {
        #expect(menu.shortcut(key, process: inspected.process) == " (\(key))")
        #expect(menu.shortcut(key, process: targets[1].process) == " (\(key) after inspection)")
    }
    #expect(model.handleShortcut("k", row: nil))
    #expect(model.report.actionPanel?.processes == [inspected])
    model.input(.escape)
    model.report.overview.showContributorSummary()
    #expect(model.handleShortcut("k", row: nil))
    try #require(model.report.actionPanel != nil)
    #expect(actions.calls.withLock { $0.isEmpty })
    model.report.overview.select(.section(.recent))
    #expect(menu.shortcut("k", process: inspected.process) == " (k after inspection)")
    model.report.receive(try menuBarFixture(pids: [99001]))
    model.input(.confirm)
    await model.waitForAction()
    #expect(actions.calls.withLock { $0 } == targets.map { "terminate \($0.process.pid)" })
    model.input(.confirm)
    await model.waitForAction()
    #expect(actions.calls.withLock { $0.count } == targets.count)
    model.input(.escape)
    model.report.receive(snapshot)
    model.report.overview.select(.section(.recent))
    #expect(!model.handleShortcut("k", row: nil))
    await model.stop()
}

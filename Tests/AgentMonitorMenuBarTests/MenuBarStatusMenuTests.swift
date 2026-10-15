import AgentMonitorCore
import AppKit
import Testing

@testable import AgentMonitorMenuBar

@Test(arguments: [
    (NSEvent.EventType.leftMouseUp, NSEvent.ModifierFlags(), MenuBarActivation.panel),
    (.leftMouseUp, .control, .contextMenu),
    (.rightMouseUp, NSEvent.ModifierFlags(), .contextMenu),
    (.rightMouseUp, .option, .contextMenu),
    (.keyDown, NSEvent.ModifierFlags(), .panel),
])
func statusItemRoutesSecondaryClicksToTheContextMenu(
    type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags, expected: MenuBarActivation
) {
    #expect(MenuBarActivation(eventType: type, modifiers: modifiers) == expected)
}

@Test @MainActor func statusMenuExposesLoadAndActionsWithoutOpeningThePanel() async throws {
    _ = NSApplication.shared
    let fixture = try menuBarFixture(cpu: 50, memoryBytes: 2_000_000_000)
    let snapshot = MonitoringSnapshot(
        timestamp: fixture.timestamp, intervalSeconds: 15, cpuThresholdPercent: 999,
        memoryThresholdBytes: 1_000_000_000, sampledProcessCount: 1, unreadableProcessCount: 0,
        findings: fixture.findings, agentLoad: AgentLoadSummary(processes: fixture.findings))
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.start()
    await model.waitForCollection()
    let controller = MenuBarStatusMenu(model: model)
    let menu = controller.makeMenu()
    #expect(!model.isOpen)
    #expect(model.report.snapshot == nil)
    for line in model.indicator.statusLines {
        let item = try #require(menu.item(withTitle: line))
        #expect(!item.isEnabled)
    }
    #expect(menu.items.contains { $0.title.contains("1 heavy") })
    let options = try #require(menu.item(withTitle: "View options")?.submenu)
    #expect(options.item(withTitle: "Sessions")?.state == .on)
    #expect(options.item(withTitle: "View options") == nil)
    for (title, action) in [
        ("Open Agent Monitor", MenuBarStatusMenu.Action.open), ("Quit Agent Monitor", .quit),
    ] {
        let item = try #require(menu.item(withTitle: title))
        menu.performActionForItem(at: menu.index(of: item))
        #expect(controller.selectedAction == action)
    }
    #expect(menu.item(withTitle: "Quit Agent Monitor")?.keyEquivalent == "q")
    let next = controller.makeMenu()
    #expect(next !== menu)
    #expect(controller.selectedAction == nil)
    await model.stop()
}

@Test @MainActor func statusMenuKeepsDisplayedSummaryWhileSamplingContinues() async throws {
    let (samples, input) = AsyncStream<MonitoringSnapshot>.makeStream()
    let (received, output) = AsyncStream<Void>.makeStream()
    let model = MenuBarModel { _, _, receive in
        for await sample in samples {
            try await receive(sample)
            output.yield(())
        }
    }
    model.start()
    let controller = MenuBarStatusMenu(model: model)
    let heldMenu = controller.makeMenu()
    let heldItems = heldMenu.items
    var iterator = received.makeAsyncIterator()
    let fixture = try menuBarFixture(cpu: 80)
    input.yield(
        MonitoringSnapshot(
            timestamp: fixture.timestamp, intervalSeconds: 15, cpuThresholdPercent: 25,
            memoryThresholdBytes: 1_000_000_000, sampledProcessCount: 1, unreadableProcessCount: 0,
            findings: fixture.findings, agentLoad: AgentLoadSummary(processes: fixture.findings)))
    _ = await iterator.next()
    #expect(heldMenu.items == heldItems)
    #expect(heldMenu.items.contains { $0.title.contains("waiting") })
    #expect(controller.makeMenu().items.contains { $0.title.contains("1 heavy") })
    #expect(!model.isOpen)
    await model.stop()
}

@Test @MainActor func statusMenuDistinguishesWaitingFailureAndStaticMode() async {
    let model = MenuBarModel { _, _, _ in throw NSError(domain: "fixture", code: 1) }
    let controller = MenuBarStatusMenu(model: model)
    #expect(controller.makeMenu().items.contains { $0.title.contains("waiting") })
    model.start()
    await model.waitForCollection()
    #expect(controller.makeMenu().items.contains { $0.title.contains("unavailable") })
    model.setLiveIcon(false)
    let menu = controller.makeMenu()
    #expect(menu.items.contains { $0.title == "Live icon is off; sampling only while the panel is open" })
    #expect(!menu.items.contains { $0.title.contains("waiting") || $0.title.contains("0 heavy") })
    await model.stop()
}

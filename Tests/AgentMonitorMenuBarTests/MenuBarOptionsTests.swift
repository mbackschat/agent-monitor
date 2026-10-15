import AgentMonitorCore
import AgentMonitorPresentation
import AppKit
import SwiftUI
import Testing

@testable import AgentMonitorMenuBar

@Test @MainActor func viewOptionsIsReadyOnFirstLayoutWithFlatCheckedDisplayChoices() throws {
    _ = NSApplication.shared
    let model = MenuBarModel { _, _, _ in }
    let host = NSHostingView(rootView: MenuBarViewOptions(model: model))
    host.frame = NSRect(x: 0, y: 0, width: 150, height: 30)
    host.layoutSubtreeIfNeeded()
    let button = try #require(findOptionsButton(in: host))
    let menu = try #require(button.menu)
    #expect(button.isEnabled)
    #expect(button.acceptsFirstMouse(for: nil))
    #expect(button.pullsDown)
    #expect(menu.item(withTitle: "Sessions")?.state == .on)
    #expect(menu.item(withTitle: "Processes")?.state == .off)
    #expect(menu.item(withTitle: "Stable order")?.state == .on)
    #expect(menu.item(withTitle: "CPU")?.state == .off)
    #expect(menu.item(withTitle: "Ascending")?.isEnabled == false)
    #expect(menu.item(withTitle: "Footprint")?.state == .off)
    #expect(menu.item(withTitle: "PID")?.state == .off)
    #expect(menu.items.filter { $0.submenu != nil }.count == 3)
}

@MainActor private func findOptionsButton(in view: NSView) -> NSPopUpButton? {
    if let button = view as? NSPopUpButton, button.menu?.title == "View options" { return button }
    return view.subviews.lazy.compactMap { findOptionsButton(in: $0) }.first
}

@Test @MainActor func reportRefreshKeepsTheSameOptionsControlAndTrackingSubmenus() throws {
    _ = NSApplication.shared
    let model = MenuBarModel { _, _, _ in }
    let host = NSHostingView(rootView: MenuBarView(model: model))
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 560)
    host.layoutSubtreeIfNeeded()
    let button = try #require(findOptionsButton(in: host))
    let menu = try #require(button.menu)
    let controller = try #require(menu.delegate as? MenuBarOptionsController)
    let items = menu.items.compactMap(\.submenu).flatMap(\.items)
    controller.menuWillOpen(menu)
    for pids: [Int32] in [[], [42001], [42001, 42002], []] {
        model.report.receive(try menuBarFixture(pids: pids))
        host.layoutSubtreeIfNeeded()
        #expect(findOptionsButton(in: host) === button)
        #expect(button.menu === menu)
        #expect(menu.items.compactMap(\.submenu).flatMap(\.items) == items)
    }
    controller.menuDidClose(menu)
}

@Test @MainActor func samplingMenusContainValuesAndExactlyOneCurrentCheckmark() throws {
    let model = MenuBarModel { _, _, _ in }
    model.report = LiveReportState(
        thresholds: Thresholds(cpuPercent: 35, memoryBytes: 750_000_000), interval: 3)
    let controller = MenuBarOptionsController(model: model)
    let button = controller.makeButton()
    let menu = try #require(button.menu)
    let submenus = menu.items.compactMap(\.submenu)
    #expect(submenus.count == 3)
    for submenu in submenus {
        #expect(submenu.items.count >= 7)
        #expect(submenu.items.filter { $0.state == .on }.count == 1)
        #expect(!submenu.items.contains { $0.title.contains("Raise") || $0.title.contains("Lower") })
    }
    #expect(submenus[0].items.first { $0.state == .on }?.representedObject as? MenuBarOption == .cpu(35))
    #expect(
        submenus[1].items.first { $0.state == .on }?.representedObject as? MenuBarOption
            == .memory(750_000_000))
    #expect(submenus[2].items.first { $0.state == .on }?.representedObject as? MenuBarOption == .interval(3))
    let choice = try #require(submenus[0].items.first { $0.representedObject as? MenuBarOption == .cpu(50) })
    submenus[0].performActionForItem(at: submenus[0].index(of: choice))
    #expect(model.report.thresholds == Thresholds(cpuPercent: 50, memoryBytes: 750_000_000))
    let memory = try #require(
        submenus[1].items.first { $0.representedObject as? MenuBarOption == .memory(2_000_000_000) })
    submenus[1].performActionForItem(at: submenus[1].index(of: memory))
    #expect(model.report.thresholds == Thresholds(cpuPercent: 50, memoryBytes: 2_000_000_000))
    let interval = try #require(
        submenus[2].items.first { $0.representedObject as? MenuBarOption == .interval(15) })
    submenus[2].performActionForItem(at: submenus[2].index(of: interval))
    #expect(model.report.interval == 15)
}

@Test @MainActor func flatOptionsDispatchAndReopenWithTheCurrentSelection() throws {
    let model = MenuBarModel { _, _, _ in }
    let controller = MenuBarOptionsController(model: model)
    let button = controller.makeButton()
    let menu = try #require(button.menu)
    for title in ["Processes", "Footprint", "Ascending", "Keyboard shortcuts"] {
        let item = try #require(menu.item(withTitle: title))
        menu.performActionForItem(at: menu.index(of: item))
        controller.menuNeedsUpdate(menu)
        #expect(menu.item(withTitle: title)?.state == .on)
    }
    #expect(model.report.grouping == .none)
    #expect(model.report.sortKey == .memory)
    #expect(model.report.ascending)
    #expect(model.showsKeyboardHelp)
    let sameSort = try #require(menu.item(withTitle: "Footprint"))
    menu.performActionForItem(at: menu.index(of: sameSort))
    #expect(model.report.ascending)
}

@Test(arguments: [0.0, -1, .infinity, .nan])
func selectedIntervalRejectsNonPositiveOrNonFiniteValues(value: Double) {
    var report = LiveReportState(interval: 2)
    report.setInterval(value)
    #expect(report.interval == 2)
}

@Test(arguments: [-1.0, .infinity, .nan])
func selectedThresholdRejectsNegativeOrNonFiniteCPU(value: Double) {
    var report = LiveReportState()
    report.setThresholds(Thresholds(cpuPercent: value, memoryBytes: 500_000_000))
    #expect(report.thresholds == Thresholds())
}

@Test @MainActor func trackingRetainsMenuItemsAcrossSamplesAndRefreshesOnlyOnReopening() throws {
    let model = MenuBarModel { _, _, _ in }
    let controller = MenuBarOptionsController(model: model)
    let button = controller.makeButton()
    let menu = try #require(button.menu)
    for pids: [Int32] in [[], [42001], [42001, 42002]] {
        controller.menuNeedsUpdate(menu)
        let items = menu.items
        let children = items.compactMap(\.submenu).flatMap(\.items)
        controller.menuWillOpen(menu)
        model.report.receive(try menuBarFixture(pids: pids))
        model.report.adjustThreshold(.cpuUp)
        controller.menuNeedsUpdate(menu)
        #expect(menu.items == items)
        #expect(menu.items.compactMap(\.submenu).flatMap(\.items) == children)
        #expect(!model.report.frozen)
        controller.menuDidClose(menu)
        controller.menuNeedsUpdate(menu)
        let cpu = try #require(menu.items.compactMap(\.submenu).first)
        #expect(
            cpu.items.first { $0.state == .on }?.representedObject as? MenuBarOption
                == .cpu(model.report.thresholds.cpuPercent))
    }
}

@Test @MainActor func historySelectorRetainsTrackingAndChecksMetricAndRange() throws {
    let model = MenuBarModel { _, _, _ in }
    let controller = MenuBarOptionsController(model: model, placement: .history)
    let button = controller.makeButton()
    let menu = try #require(button.menu)
    #expect(button.title == "CPU · 10m")
    #expect(menu.item(withTitle: "CPU")?.state == .on)
    #expect(menu.item(withTitle: "Last 10 minutes")?.state == .on)
    let items = menu.items
    controller.menuWillOpen(menu)
    model.report.receive(try menuBarFixture())
    controller.menuNeedsUpdate(menu)
    controller.updateTitle(button)
    #expect(menu.items == items)
    controller.menuDidClose(menu)
    for title in ["Memory", "Last hour"] {
        let item = try #require(menu.item(withTitle: title))
        menu.performActionForItem(at: menu.index(of: item))
        controller.menuNeedsUpdate(menu)
        #expect(menu.item(withTitle: title)?.state == .on)
    }
    controller.updateTitle(button)
    #expect(button.title == "Memory · 1h")
    #expect(model.report.interval == 1)
}

@Test(arguments: HistoryMetric.allCases, HistoryWindow.allCases)
@MainActor func historyMenuTitleFitsItsCompactSlot(metric: HistoryMetric, window: HistoryWindow) {
    let model = MenuBarModel { _, _, _ in }
    model.report.historyMetric = metric
    model.report.historyWindow = window
    let controller = MenuBarOptionsController(model: model, placement: .history)
    let button = controller.makeButton()
    #expect(button.intrinsicContentSize.width <= 120)
}

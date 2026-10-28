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
    #expect(menu.item(withTitle: "Main contributors")?.state == .on)
    #expect(menu.item(withTitle: "Processes")?.state == .off)
    #expect(menu.item(withTitle: "Stable order")?.state == .on)
    #expect(menu.item(withTitle: "CPU")?.state == .off)
    #expect(menu.item(withTitle: "Ascending")?.isEnabled == false)
    #expect(menu.item(withTitle: "Footprint")?.state == .off)
    #expect(menu.item(withTitle: "PID")?.state == .off)
    #expect(menu.items.filter { $0.submenu != nil }.count == 5)
    #expect(menu.item(withTitle: "CPU filter: Off")?.submenu?.item(withTitle: "Off")?.state == .on)
    #expect(menu.item(withTitle: "Footprint filter: Off")?.submenu?.item(withTitle: "Off")?.state == .on)
}

@MainActor private func findOptionsButton(in view: NSView) -> NSPopUpButton? {
    if let button = view as? NSPopUpButton, button.menu?.title == "View options" { return button }
    return view.subviews.lazy.compactMap { findOptionsButton(in: $0) }.first
}

@Test @MainActor func displayFiltersAreSeparateFromSamplingControls() throws {
    let model = MenuBarModel { _, _, _ in }
    let menu = MenuBarOptionsController(model: model).makeMenu()
    let display = try #require(menu.items.firstIndex { $0.title == "Display filters" })
    let sampling = try #require(menu.items.firstIndex { $0.title == "Sampling" })
    for title in ["CPU filter: Off", "Footprint filter: Off"] {
        let index = try #require(menu.items.firstIndex { $0.title == title })
        #expect(display < index && index < sampling)
        #expect(menu.items[index].toolTip?.contains("totals") == true)
    }
    for option in [MenuBarOption.liveIcon, .interval(0.1)] {
        let index = try #require(
            menu.items.firstIndex {
                $0.representedObject as? MenuBarOption == option
                    || $0.submenu?.items.contains { $0.representedObject as? MenuBarOption == option } == true
            })
        #expect(index > sampling)
    }
}

@Test @MainActor func reportRefreshKeepsTheSameOptionsControlAndTrackingSubmenus() throws {
    _ = NSApplication.shared
    let model = MenuBarModel { _, _, _ in }
    let host = NSHostingView(rootView: MenuBarView(model: model))
    host.frame = NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: 560)
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
    let submenus = Array(menu.items.compactMap(\.submenu).prefix(3))
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

@Test @MainActor func samplingModeExplicitlyChoosesMaximumIntervalOrAdaptation() throws {
    _ = NSApplication.shared
    let model = MenuBarModel { _, _, _ in }
    let controller = MenuBarOptionsController(model: model)
    let menu = controller.makeMenu()
    let mode = try #require(menu.item(withTitle: "Mode: Use maximum interval")?.submenu)
    #expect(mode.item(withTitle: "Use maximum interval")?.state == .on)
    #expect(mode.item(withTitle: "Adaptive sampling")?.state == .off)
    let adaptive = try #require(mode.item(withTitle: "Adaptive sampling"))
    mode.performActionForItem(at: mode.index(of: adaptive))
    #expect(model.report.samplingSettings.enabled)
    controller.menuNeedsUpdate(menu)
    let updated = try #require(menu.item(withTitle: "Mode: Adaptive")?.submenu)
    #expect(updated.item(withTitle: "Adaptive sampling")?.state == .on)
    let maximum = try #require(updated.item(withTitle: "Use maximum interval"))
    updated.performActionForItem(at: updated.index(of: maximum))
    #expect(!model.report.samplingSettings.enabled)
    #expect(model.report.samplingSettings.minimum == 0.1)
    #expect(model.report.samplingSettings.visibleMaximum == 0.1)
    #expect(model.report.samplingSettings.closedMultiplier == 1)
}

@Test @MainActor func advancedSamplingMenusRetainCurrentValuesAndDisableInvalidCombinations() throws {
    _ = NSApplication.shared
    let model = MenuBarModel { _, _, _ in }
    var settings = SamplingSettings(
        enabled: true, minimum: 0.3, visibleMaximum: 4, closedMultiplier: 3, window: 45)
    let accepted = model.report.setSamplingSettings(settings)
    #expect(accepted)
    let controller = MenuBarOptionsController(model: model)
    let menu = controller.makeMenu()
    let maximum = try #require(menu.item(withTitle: "Maximum interval: 4 s")?.submenu)
    #expect(maximum.item(withTitle: "\(Double(0.25).formatted()) s")?.isEnabled == false)
    #expect(maximum.item(withTitle: "15 s")?.isEnabled == true)
    #expect(maximum.item(withTitle: "30 s")?.isEnabled == false)
    let advanced = try #require(menu.item(withTitle: "Advanced sampling")?.submenu)
    let minimum = try #require(
        advanced.item(withTitle: "Minimum interval: \(settings.minimum.formatted()) s")?.submenu)
    #expect(minimum.item(withTitle: "\(settings.minimum.formatted()) s")?.state == .on)
    #expect(minimum.item(withTitle: "5 s")?.isEnabled == false)
    let window = try #require(advanced.item(withTitle: "Activity window: 45 s")?.submenu)
    #expect(window.item(withTitle: "45 s")?.state == .on)
    let multiplier = try #require(advanced.item(withTitle: "Closed-panel multiplier: 3×")?.submenu)
    #expect(multiplier.item(withTitle: "3×")?.state == .on)
    let selected = try #require(window.item(withTitle: "120 s"))
    window.performActionForItem(at: window.index(of: selected))
    settings.window = 120
    #expect(model.report.samplingSettings == settings)
}

@Test @MainActor func trackedSamplingChoicePreservesSettingsChangedSinceMenuOpening() throws {
    _ = NSApplication.shared
    let model = MenuBarModel { _, _, _ in }
    let controller = MenuBarOptionsController(model: model)
    let menu = controller.makeMenu()
    let mode = try #require(menu.item(withTitle: "Mode: Use maximum interval")?.submenu)
    let adaptive = try #require(mode.item(withTitle: "Adaptive sampling"))
    controller.menuWillOpen(menu)
    model.setInterval(15)
    mode.performActionForItem(at: mode.index(of: adaptive))
    #expect(model.report.samplingSettings.enabled)
    #expect(model.report.interval == 15)
    controller.menuDidClose(menu)
}

@Test @MainActor func flatOptionsDispatchAndReopenWithTheCurrentSelection() throws {
    let model = MenuBarModel { _, _, _ in }
    let controller = MenuBarOptionsController(model: model)
    let button = controller.makeButton()
    let menu = try #require(button.menu)
    for title in ["Processes", "Footprint", "Ascending", "Help & glossary"] {
        let item = try #require(menu.item(withTitle: title))
        menu.performActionForItem(at: menu.index(of: item))
        controller.menuNeedsUpdate(menu)
        #expect(menu.item(withTitle: title)?.state == .on)
    }
    #expect(model.report.grouping == .none)
    #expect(model.report.sortKey == .memory)
    #expect(model.report.ascending)
    #expect(model.referencePage == .glossary)
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
    #expect(model.report.interval == 0.1)
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

@Test(arguments: [("Memory", "Memory · 10m"), ("Last hour", "CPU · 1h")])
@MainActor func historySelectionUpdatesTitleWhenTrackingEndsWithoutAnotherSample(
    itemTitle: String, expectedTitle: String
) throws {
    let model = MenuBarModel { _, _, _ in }
    let controller = MenuBarOptionsController(model: model, placement: .history)
    let button = controller.makeButton()
    let menu = try #require(button.menu)
    let items = menu.items
    controller.menuWillOpen(menu)
    let item = try #require(menu.item(withTitle: itemTitle))
    menu.performActionForItem(at: menu.index(of: item))
    controller.updateTitle(button)
    #expect(button.title == "CPU · 10m")
    #expect(menu.items == items)
    controller.menuDidClose(menu)
    #expect(button.title == expectedTitle)
    #expect(menu.items == items)
    #expect(model.report.snapshot == nil)
}

@Test @MainActor func unpinAllMenuClearsAbsentTargetsWithoutASelection() throws {
    _ = NSApplication.shared
    let model = MenuBarModel { _, _, _ in }
    model.report.overview.enabled = false
    model.report.receive(try menuBarFixture())
    let row = try #require(model.report.rows.first)
    model.report.togglePin(.process(row.process))
    model.report.receive(try menuBarFixture(pids: []))
    let controller = MenuBarOptionsController(model: model)
    let menu = controller.makeMenu()
    let item = try #require(menu.item(withTitle: "Unpin all"))
    #expect(item.isEnabled)
    menu.performActionForItem(at: menu.index(of: item))
    #expect(!model.report.hasPins)
    #expect(model.report.visibleRows.isEmpty)
    controller.menuNeedsUpdate(menu)
    #expect(menu.item(withTitle: "Unpin all")?.isEnabled == false)
}

@Test @MainActor func absentNativePinCanBeRemovedByRowOrGlobalShortcut() async throws {
    let model = MenuBarModel { _, _, _ in }
    model.open()
    await model.waitForCollection()
    model.report.overview.enabled = false
    for shortcut in [false, true] {
        model.report.receive(try menuBarFixture())
        let id = LiveReportRowID.process(try #require(model.report.rows.first).process)
        #expect(model.togglePin(id))
        model.report.receive(try menuBarFixture(pids: []))
        if shortcut {
            #expect(model.handleShortcut("u", row: nil))
        } else {
            #expect(model.togglePin(id))
        }
        #expect(!model.report.hasPins)
        #expect(model.report.visibleRows.isEmpty)
    }
    await model.stop()
}

@Test @MainActor func overviewMenuDirectionDoesNotChangeProcessSortState() async throws {
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let controller = MenuBarOptionsController(model: model)
    let menu = controller.makeMenu()
    for expected in [true, false] {
        let item = try #require(menu.item(withTitle: "Ascending"))
        #expect(item.isEnabled)
        menu.performActionForItem(at: menu.index(of: item))
        controller.menuNeedsUpdate(menu)
        #expect(model.report.overview.ascending == expected)
        #expect(menu.item(withTitle: "Ascending")?.state == (expected ? .on : .off))
        #expect(model.report.sortKey == .stable)
        #expect(!model.report.ascending)
    }
    let alphabetical = try #require(menu.item(withTitle: "Contributor"))
    menu.performActionForItem(at: menu.index(of: alphabetical))
    #expect(model.report.overview.order == .contributor)
    #expect(model.report.overview.ascending)
    await model.stop()
}

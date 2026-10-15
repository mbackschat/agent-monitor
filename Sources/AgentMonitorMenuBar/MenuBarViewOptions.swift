import AgentMonitorCore
import AgentMonitorPresentation
import AppKit
import SwiftUI

struct MenuBarViewOptions: NSViewRepresentable {
    let model: MenuBarModel

    func makeCoordinator() -> MenuBarOptionsController { MenuBarOptionsController(model: model) }

    func makeNSView(context: Context) -> NSPopUpButton { context.coordinator.makeButton() }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        // Samples invalidate the parent report. Menu tracking must retain its items until dismissal.
        // NSMenuDelegate.menuNeedsUpdate supplies fresh options at the next opening instead.
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

enum MenuBarOption: Equatable {
    case grouping(ReportGrouping)
    case sort(ReportSort)
    case ascending
    case cpu(Double)
    case memory(UInt64)
    case interval(Double)
    case liveIcon, keyboardHelp
}

@MainActor final class MenuBarOptionsController: NSObject, NSMenuDelegate {
    enum Placement { case pullDown, submenu }

    private let model: MenuBarModel
    private let placement: Placement
    private var tracking = false

    init(model: MenuBarModel, placement: Placement = .pullDown) {
        self.model = model
        self.placement = placement
    }

    func makeButton() -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.bezelStyle = .rounded
        button.preferredEdge = .minY
        button.setAccessibilityLabel("View options")
        button.toolTip = "Grouping, sort direction, CPU and footprint thresholds, and sampling interval"
        button.menu = makeMenu()
        return button
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "View options")
        menu.autoenablesItems = false
        menu.delegate = self
        menuNeedsUpdate(menu)
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) { tracking = true }
    func menuDidClose(_ menu: NSMenu) { tracking = false }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard !tracking else { return }
        menu.removeAllItems()
        switch placement {
        case .pullDown:
            // NSPopUpButton consumes its first item as the button title; a submenu does not.
            menu.addItem(withTitle: "View options", action: nil, keyEquivalent: "")
        case .submenu: break
        }
        menu.addItem(.sectionHeader(title: "Show"))
        add("Sessions", .grouping(.session), checked: model.report.grouping == .session, to: menu)
        add("Processes", .grouping(.none), checked: model.report.grouping == .none, to: menu)
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Sort by"))
        for sort in ReportSort.allCases {
            add(sort.rawValue, .sort(sort), checked: model.report.sortKey == sort, to: menu)
        }
        add("Ascending", .ascending, checked: model.report.ascending, to: menu)
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Sampling"))
        add("Live menu bar icon", .liveIcon, checked: model.liveIcon, to: menu)
        let cpu = model.report.thresholds.cpuPercent
        let cpuMenu = submenu("CPU > \(cpu.formatted())%", in: menu)
        for value in Set([0, 5, 10, 25, 50, 100, 200, 400, 800, cpu]).sorted() {
            add("\(value.formatted())%", .cpu(value), checked: value == cpu, to: cpuMenu)
        }
        let memory = model.report.thresholds.memoryBytes
        let memoryMenu = submenu("Footprint > \((Double(memory) / 1e9).formatted()) GB", in: menu)
        let memorySteps: [UInt64] = [
            0, 250_000_000, 500_000_000, 1_000_000_000, 2_000_000_000, 4_000_000_000, 8_000_000_000,
            16_000_000_000,
        ]
        for value in Set(memorySteps + [memory]).sorted() {
            add(
                "\((Double(value) / 1e9).formatted()) GB", .memory(value), checked: value == memory,
                to: memoryMenu)
        }
        let interval = model.report.interval
        let intervalMenu = submenu("Every \(interval.formatted()) seconds", in: menu)
        for value in Set(LiveReportState.intervalSteps + [15, interval]).sorted() {
            add("\(value.formatted()) s", .interval(value), checked: value == interval, to: intervalMenu)
        }
        menu.addItem(.separator())
        add("Keyboard shortcuts", .keyboardHelp, checked: model.showsKeyboardHelp, to: menu)
    }

    private func submenu(_ title: String, in menu: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let child = NSMenu(title: title)
        child.autoenablesItems = false
        item.submenu = child
        menu.addItem(item)
        return child
    }

    private func add(_ title: String, _ option: MenuBarOption, checked: Bool, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = option
        item.state = checked ? .on : .off
        menu.addItem(item)
    }

    @objc private func choose(_ item: NSMenuItem) {
        guard let option = item.representedObject as? MenuBarOption else { return }
        switch option {
        case .grouping(let grouping):
            if model.report.grouping != grouping { model.report.toggleGrouping() }
        case .sort(let sort):
            if model.report.sortKey != sort { model.report.sort(by: sort) }
        case .ascending: model.report.reverseSort()
        case .cpu(let value):
            model.report.setThresholds(
                Thresholds(cpuPercent: value, memoryBytes: model.report.thresholds.memoryBytes))
        case .memory(let value):
            model.report.setThresholds(
                Thresholds(cpuPercent: model.report.thresholds.cpuPercent, memoryBytes: value))
        case .interval(let value): model.setInterval(value)
        case .liveIcon: model.setLiveIcon(!model.liveIcon)
        case .keyboardHelp: model.showsKeyboardHelp.toggle()
        }
    }
}

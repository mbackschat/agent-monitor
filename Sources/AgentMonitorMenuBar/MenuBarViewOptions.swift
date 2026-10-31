import AgentMonitorCore
import AgentMonitorPresentation
import AppKit
import SwiftUI

struct MenuBarViewOptions: NSViewRepresentable {
    let model: MenuBarModel
    var placement: MenuBarOptionsController.Placement = .pullDown

    func makeCoordinator() -> MenuBarOptionsController {
        MenuBarOptionsController(model: model, placement: placement)
    }

    func makeNSView(context: Context) -> NSPopUpButton { context.coordinator.makeButton() }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        // Samples invalidate the parent report. Menu tracking must retain its items until dismissal.
        // NSMenuDelegate.menuNeedsUpdate supplies fresh options at the next opening instead.
        context.coordinator.updateTitle(button)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

enum MenuBarOption: Equatable {
    case view(ReportView)
    case sort(ReportSort)
    case contributorSort
    case ascending
    case chartRange(ContributorChartRange.Selection)
    case cpu(Double)
    case memory(UInt64)
    case interval(Double)
    case samplingMode(Bool)
    case samplingMinimum(Double)
    case samplingWindow(Double)
    case closedMultiplier(Double)
    case historyMetric(HistoryMetric)
    case historyWindow(HistoryWindow)
    case reference(MenuBarReferencePage)
    case liveIcon, unpinAll
    case hideNoLongerObserved

    func samplingSettings(from current: SamplingSettings) -> SamplingSettings? {
        var settings = current
        switch self {
        case .interval(let value): settings.visibleMaximum = value
        case .samplingMode(let enabled): settings.enabled = enabled
        case .samplingMinimum(let value): settings.minimum = value
        case .samplingWindow(let value): settings.window = value
        case .closedMultiplier(let value): settings.closedMultiplier = value
        default: return nil
        }
        return settings
    }
}

@MainActor final class MenuBarOptionsController: NSObject, NSMenuDelegate {
    enum Placement { case pullDown, submenu, history }

    private let model: MenuBarModel
    private let placement: Placement
    private var tracking = false
    private weak var button: NSPopUpButton?

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
        button.setAccessibilityLabel(placement == .history ? "History metric and time range" : "View options")
        button.toolTip = "View, sort, filters and sampling options"
        button.menu = makeMenu()
        if placement == .pullDown {
            button.imagePosition = .imageOnly
        }
        self.button = button
        updateTitle(button)
        return button
    }

    func updateTitle(_ button: NSPopUpButton) {
        guard placement == .history, !tracking else { return }
        let title = "\(model.report.historyMetric.rawValue) · \(model.report.historyWindow.rawValue)"
        if button.title != title { button.title = title }
        button.toolTip = "History metric (h) and time range (t)"
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: placement == .history ? "History" : "View options")
        menu.autoenablesItems = false
        menu.delegate = self
        menuNeedsUpdate(menu)
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) { tracking = true }
    func menuDidClose(_ menu: NSMenu) {
        tracking = false
        if let button { updateTitle(button) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard !tracking else { return }
        menu.removeAllItems()
        switch placement {
        case .pullDown:
            // NSPopUpButton consumes its first item as the button title; a submenu does not.
            menu.addItem(withTitle: "View options", action: nil, keyEquivalent: "")
            menu.items.last?.image = NSImage(
                systemSymbolName: "slider.horizontal.3", accessibilityDescription: "View options")
        case .history:
            menu.addItem(
                withTitle: "\(model.report.historyMetric.rawValue) · \(model.report.historyWindow.rawValue)",
                action: nil, keyEquivalent: "")
            for metric in HistoryMetric.allCases {
                add(
                    metric == .heavyCount ? "Heavy processes" : metric.rawValue, .historyMetric(metric),
                    checked: model.report.historyMetric == metric, to: menu)
            }
            menu.addItem(.separator())
            for window in HistoryWindow.allCases {
                add(
                    window == .tenMinutes ? "Last 10 minutes" : "Last hour", .historyWindow(window),
                    checked: model.report.historyWindow == window, to: menu)
            }
            return
        case .submenu: break
        }
        menu.addItem(.sectionHeader(title: "View"))
        for view in ReportView.allCases {
            add(
                model.report.title(for: view), .view(view), checked: model.report.view == view,
                enabled: !view.isOverview || model.report.canSelectOverview, to: menu)
        }
        menu.addItem(.separator())
        add("Unpin all", .unpinAll, checked: false, to: menu)
        menu.items.last?.isEnabled =
            model.report.hasPins && model.report.actionPanel == nil && !model.diagnosis.state.isVisible
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Sort by"))
        let overview = model.report.view.isOverview
        if overview {
            add(
                "Contributor", .contributorSort, checked: model.report.overview.order == .contributor,
                to: menu)
        }
        for sort in ReportSort.allCases where !overview || sort != .pid {
            add(
                sort.rawValue, .sort(sort),
                checked: overview
                    ? (sort == .stable && model.report.overview.order == .stable
                        || sort == .cpu && model.report.overview.order == .cpu
                        || sort == .memory && model.report.overview.order == .memory)
                    : model.report.sortKey == sort, to: menu)
        }
        add(
            "Ascending", .ascending,
            checked: overview ? model.report.overview.ascending : model.report.ascending,
            to: menu)
        menu.items.last?.isEnabled =
            overview ? model.report.overview.order != .stable : model.report.sortKey != .stable
        menu.addItem(.separator())
        if overview, let range = model.report.overview.chartRange {
            let rangeMenu = submenu(
                "CPU chart range: \(Int(range.upper))%", in: menu,
                help:
                    "Fixed display range (b cycles choices). Hardware default uses performance and super cores when identified; activity never changes it."
            )
            for choice in range.choices {
                add(
                    range.label(for: choice), .chartRange(choice), checked: range.selection == choice,
                    to: rangeMenu)
            }
            menu.addItem(.separator())
        }
        menu.addItem(.sectionHeader(title: "Display filters"))
        if overview {
            add(
                "Hide no longer observed", .hideNoLongerObserved,
                checked: model.report.overview.hideNoLongerObserved, to: menu)
        }
        let filterHelp = "Changes process rows; observed totals and recent activity stay unchanged."
        let cpu = model.report.thresholds.cpuPercent
        let cpuMenu = submenu(
            cpu == 0 ? "CPU filter: Off" : "CPU > \(cpu.formatted())%", in: menu,
            help: filterHelp + " 1 lowers, 2 raises the threshold.")
        for value in Set([0, 5, 10, 25, 50, 100, 200, 400, 800, cpu]).sorted() {
            add(value == 0 ? "Off" : "\(value.formatted())%", .cpu(value), checked: value == cpu, to: cpuMenu)
        }
        let memory = model.report.thresholds.memoryBytes
        let memoryMenu = submenu(
            memory == 0 ? "Footprint filter: Off" : "Footprint > \((Double(memory) / 1e9).formatted()) GB",
            in: menu, help: filterHelp + " 3 lowers, 4 raises the threshold.")
        let memorySteps: [UInt64] = [
            0, 250_000_000, 500_000_000, 1_000_000_000, 2_000_000_000, 4_000_000_000, 8_000_000_000,
            16_000_000_000,
        ]
        for value in Set(memorySteps + [memory]).sorted() {
            add(
                value == 0 ? "Off" : "\((Double(value) / 1e9).formatted()) GB", .memory(value),
                checked: value == memory,
                to: memoryMenu)
        }
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Sampling"))
        add("Live menu bar icon", .liveIcon, checked: model.liveIcon, to: menu)
        addSamplingOptions(to: menu)
        menu.addItem(.separator())
        for page in [MenuBarReferencePage.glossary, .keyboard, .diagnostics] {
            add(page.title, .reference(page), checked: model.referencePage == page, to: menu)
            menu.items.last?.image = NSImage(
                systemSymbolName: page.symbol, accessibilityDescription: page.title)
            menu.items.last?.preferredImageVisibility = .visible
            if page == .keyboard { menu.items.last?.title += " (?)" }
        }
    }

    private func addSamplingOptions(to menu: NSMenu) {
        let settings = model.report.samplingSettings
        let interval = settings.visibleMaximum
        let intervalMenu = submenu(
            "Maximum interval: \(interval.formatted()) s", in: menu,
            help: "Maximum while the panel is open. < slows acquisition, > speeds it up.")
        for value in Set(LiveReportState.intervalSteps + [15, interval]).sorted() {
            addSamplingChoice("\(value.formatted()) s", .interval(value), to: intervalMenu)
        }
        let modeMenu = submenu(
            settings.enabled ? "Mode: Adaptive" : "Mode: Use maximum interval", in: menu,
            help: "Choose fixed or activity-based sampling")
        addSamplingChoice("Use maximum interval", .samplingMode(false), to: modeMenu)
        addSamplingChoice("Adaptive sampling", .samplingMode(true), to: modeMenu)
        let advanced = submenu("Advanced sampling", in: menu, help: "Sampling bounds and activity window")
        let minimumMenu = submenu(
            "Minimum interval: \(settings.minimum.formatted()) s", in: advanced,
            help: "Fastest permitted sampling interval")
        for value in Set(LiveReportState.intervalSteps + [15, settings.minimum]).sorted() {
            addSamplingChoice("\(value.formatted()) s", .samplingMinimum(value), to: minimumMenu)
        }
        let windowMenu = submenu(
            "Activity window: \(settings.window.formatted()) s", in: advanced,
            help: "Recent activity used to adjust sampling")
        for value in Set([1, 5, 10, 30, 60, 120, 300, settings.window]).sorted() {
            addSamplingChoice("\(value.formatted()) s", .samplingWindow(value), to: windowMenu)
        }
        let multiplierMenu = submenu(
            "Closed-panel multiplier: \(settings.closedMultiplier.formatted())×", in: advanced,
            help: "Multiply the maximum interval while the panel is closed")
        for value in Set([1, 1.5, 2, 2.5, 4, 5, 10, settings.closedMultiplier]).sorted() {
            addSamplingChoice("\(value.formatted())×", .closedMultiplier(value), to: multiplierMenu)
        }
    }

    private func addSamplingChoice(_ title: String, _ option: MenuBarOption, to menu: NSMenu) {
        let current = model.report.samplingSettings
        guard let settings = option.samplingSettings(from: current) else { return }
        add(title, option, checked: settings == current, enabled: settings.isValid, to: menu)
    }

    private func submenu(_ title: String, in menu: NSMenu, help: String? = nil) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.toolTip = help
        let child = NSMenu(title: title)
        child.autoenablesItems = false
        item.submenu = child
        menu.addItem(item)
        return child
    }

    private func add(
        _ title: String, _ option: MenuBarOption, checked: Bool, enabled: Bool = true, to menu: NSMenu
    ) {
        let item = NSMenuItem(
            title: title, action: #selector(choose(_:)), keyEquivalent: shortcut(for: option))
        item.keyEquivalentModifierMask = []
        item.allowsKeyEquivalentWhenHidden = false
        item.target = self
        item.representedObject = option
        let help =
            switch option {
            case .view: "Show " + title
            case .sort, .contributorSort: "Sort by " + title
            case .ascending: "Reverse the current sort direction"
            case .chartRange: "Set fixed CPU chart range: " + title
            case .cpu: "Set CPU display filter: " + title + "; totals unchanged"
            case .memory: "Set memory display filter: " + title + "; totals unchanged"
            case .interval: "Set maximum sampling interval: " + title
            case .samplingMode: "Sampling mode: " + title
            case .samplingMinimum: "Set minimum sampling interval: " + title
            case .samplingWindow: "Set sampling activity window: " + title
            case .closedMultiplier: "Set closed-panel interval multiplier: " + title
            case .historyMetric: "Show " + title + " history"
            case .historyWindow: "Show history: " + title
            case .reference: "Open " + title
            case .liveIcon: "Toggle live icon and closed-panel collection"
            case .unpinAll: "Remove all pins"
            case .hideNoLongerObserved: "Hide historical rows; measured totals stay unchanged"
            }
        item.toolTip = help + (item.keyEquivalent.isEmpty ? "" : " (" + item.keyEquivalent + ")")
        item.state = checked ? .on : .off
        item.isEnabled = enabled
        menu.addItem(item)
    }

    private func shortcut(for option: MenuBarOption) -> String {
        switch option {
        case .sort(let sort):
            switch sort {
            case .cpu: return ReportShortcut.cpu.rawValue
            case .memory: return ReportShortcut.memory.rawValue
            case .pid: return ReportShortcut.pid.rawValue
            case .stable: return ReportShortcut.stable.rawValue
            }
        case .ascending: return ReportShortcut.reverse.rawValue
        case .unpinAll: return ReportShortcut.unpinAll.rawValue
        case .view(let view):
            for shortcut in [ReportShortcut.allContributors, .overview, .grouping] {
                var report = model.report
                report.apply(shortcut)
                if report.view != model.report.view, report.view == view { return shortcut.rawValue }
            }
            return ""
        case .historyMetric(let metric):
            return metric == model.report.historyMetric.next ? ReportShortcut.historyMetric.rawValue : ""
        case .historyWindow(let window):
            return window == model.report.historyWindow.next ? ReportShortcut.historyWindow.rawValue : ""
        default: return ""
        }
    }

    @objc private func choose(_ item: NSMenuItem) {
        guard let option = item.representedObject as? MenuBarOption else { return }
        switch option {
        case .unpinAll: model.unpinAll()
        case .hideNoLongerObserved: model.report.overview.hideNoLongerObserved.toggle()
        case .view(let view): model.report.view = view
        case .sort(let sort): model.report.sortCurrentView(by: sort)
        case .contributorSort:
            if model.report.view.isOverview { model.report.overview.sort(by: .contributor, ascending: true) }
        case .ascending: model.report.reverseCurrentSort()
        case .chartRange(let choice):
            if model.report.view.isOverview { model.report.overview.setChartRange(choice) }
        case .cpu(let value):
            model.report.setThresholds(
                Thresholds(cpuPercent: value, memoryBytes: model.report.thresholds.memoryBytes))
        case .memory(let value):
            model.report.setThresholds(
                Thresholds(cpuPercent: model.report.thresholds.cpuPercent, memoryBytes: value))
        case .interval, .samplingMode, .samplingMinimum, .samplingWindow, .closedMultiplier:
            if let settings = option.samplingSettings(from: model.report.samplingSettings) {
                model.report.setSamplingSettings(settings)
            }
        case .liveIcon: model.setLiveIcon(!model.liveIcon)
        case .reference(let page): model.referencePage = page
        case .historyMetric(let metric): model.report.historyMetric = metric
        case .historyWindow(let window): model.report.historyWindow = window
        }
    }
}

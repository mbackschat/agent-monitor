import AgentMonitorPresentation
import AppKit
import SwiftUI

struct MenuBarContributorTable: View {
    @Bindable var model: MenuBarModel
    var focus: FocusState<MenuBarFocus?>.Binding

    private var acceptsInteraction: Bool {
        model.isOpen && model.report.showsOverview && !model.diagnosis.state.isVisible
            && model.report.actionPanel == nil
    }

    var body: some View {
        let overview = model.report.overview
        Table(
            of: ContributorNode.self,
            selection: Binding(
                get: { model.report.overview.selection },
                set: { id in
                    if acceptsInteraction, let id { model.report.overview.select(id) }
                }),
            sortOrder: Binding(
                get: {
                    [
                        MenuBarContributorSort(
                            field: overview.order, order: overview.ascending ? .forward : .reverse)
                    ]
                },
                set: { sorts in
                    guard acceptsInteraction, let sort = sorts.first else { return }
                    model.report.overview.sort(by: sort.field, ascending: sort.order == .forward)
                })
        ) {
            TableColumn(
                "Contributor", sortUsing: MenuBarContributorSort(field: .contributor, order: .forward)
            ) { node in
                MenuBarContributorTableCell(node: node, model: model) { activate(node) }
            }.width(min: 130, ideal: 172)
            TableColumn("CPU", sortUsing: MenuBarContributorSort(field: .cpu)) { node in
                Button {
                    activate(node)
                } label: {
                    metric(node: node, kind: .cpu).frame(maxHeight: .infinity).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityHint(
                        node.children.isEmpty ? "Select row" : "Select row and toggle children")
            }.width(74)
            TableColumn("Memory", sortUsing: MenuBarContributorSort(field: .memory)) { node in
                Button {
                    activate(node)
                } label: {
                    metric(node: node, kind: .memory).frame(maxHeight: .infinity).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityHint(
                        node.children.isEmpty ? "Select row" : "Select row and toggle children")
            }.width(88)
        } rows: {
            MenuBarContributorRows(
                model: model, ids: overview.topLevel, acceptsInteraction: acceptsInteraction)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .accessibilityLabel("Main contributors")
        .frame(minHeight: 120, maxHeight: .infinity)
        .focused(focus, equals: .overview)
        .background {
            MenuBarTableState(
                rows: overview.visibleRows.map(\.id), selection: overview.selection,
                active: acceptsInteraction)
        }
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: .down) { _ in
            !acceptsInteraction || overview.detailsVisible ? .handled : .ignored
        }
        .onKeyPress(keys: MenuBarKeyboard.keys, phases: .down) { key in
            guard acceptsInteraction, MenuBarKeyboard.accepts(key.characters, modifiers: key.modifiers)
            else { return .ignored }
            if key.characters == "q" {
                NSApplication.shared.terminate(nil)
                return .handled
            }
            return model.handleShortcut(key.characters, row: nil) ? .handled : .ignored
        }
        .contextMenu(forSelectionType: ContributorID.self) { ids in
            if acceptsInteraction, let id = ids.first {
                Button("Details…") {
                    guard selectContextTarget(id) else { return }
                    if !model.report.overview.detailsVisible { model.report.overview.toggleDetails() }
                }
                Button("Pin / unpin session") {
                    guard selectContextTarget(id) else { return }
                    model.report.overview.togglePin()
                }
            }
        }
    }

    private func activate(_ node: ContributorNode) {
        guard acceptsInteraction else { return }
        model.report.overview.activateRow(node.id)
    }

    private func selectContextTarget(_ id: ContributorID) -> Bool {
        guard acceptsInteraction, model.report.overview.visibleRows.contains(where: { $0.id == id }) else {
            return false
        }
        model.report.overview.select(id)
        return true
    }

    private enum Metric { case cpu, memory }

    @ViewBuilder private func metric(node: ContributorNode, kind: Metric) -> some View {
        let overview = model.report.overview
        switch kind {
        case .memory:
            MenuBarContributorMetric(
                value: node.stats.memoryText, fraction: overview.memoryMeterFraction(node.stats)
            )
            .font(.caption)
            .help(
                "Current physical footprint; bar scale is physical RAM. \(node.stats.missingMemory) readings unavailable. Historical peaks are in details."
            )
        case .cpu:
            VStack(alignment: .trailing, spacing: 3) {
                MenuBarContributorMetric(
                    value: node.stats.cpuText(duration: overview.duration),
                    fraction: overview.cpuMeterFraction(node.stats)
                )
                .help(
                    "CPU over \(overview.duration.formatted()) s. Bar: 100% is one core. Session ownership is point evidence."
                )
                Text("Recent " + node.stats.recentCPUText).monospacedDigit().lineLimit(1)
                    .font(.caption2).modifier(MenuBarContributorTextStyle(secondary: true))
                    .help("Measured CPU-seconds in the recent range, including workers no longer observed.")
            }.font(.caption).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct MenuBarContributorRows: TableRowContent {
    let model: MenuBarModel
    let ids: [ContributorID]
    let acceptsInteraction: Bool

    private func visibleNodes(_ ids: [ContributorID]) -> [ContributorNode] {
        ids.compactMap { model.report.overview.nodes[$0] }.filter {
            $0.process == nil || $0.stats.filtered.isEmpty
        }
    }

    @TableRowBuilder<ContributorNode> var tableRowBody: some TableRowContent<ContributorNode> {
        ForEach(visibleNodes(ids)) { node in
            let children = visibleNodes(node.children.filter { !model.report.overview.pinned.contains($0) })
                .map(\.id)
            if children.isEmpty {
                TableRow(node)
            } else {
                DisclosureTableRow(
                    node,
                    isExpanded: Binding(
                        get: { model.report.overview.isExpanded(node.id) },
                        set: {
                            if acceptsInteraction {
                                model.report.overview.setDisclosure(expanded: $0, for: node.id)
                            }
                        })
                ) {
                    MenuBarContributorRows(
                        model: model, ids: children, acceptsInteraction: acceptsInteraction)
                }
            }
        }
    }
}

private struct MenuBarContributorTableCell: View {
    let node: ContributorNode
    @Bindable var model: MenuBarModel
    let activate: () -> Void

    private var isSelected: Bool { model.report.overview.selection == node.id }

    private var detailsPresented: Binding<Bool> {
        Binding(
            get: {
                model.report.showsOverview && !model.diagnosis.state.isVisible
                    && model.report.actionPanel == nil
                    && model.report.overview.selection == node.id && model.report.overview.detailsVisible
            },
            set: { presented in
                if !presented, model.report.overview.selection == node.id,
                    model.report.overview.detailsVisible
                {
                    model.report.overview.toggleDetails()
                }
            })
    }

    var body: some View {
        Button(action: activate) {
            MenuBarContributorCellContent(node: node, pinned: model.report.overview.pinned.contains(node.id))
                .frame(maxHeight: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(node.children.isEmpty ? "Select row" : "Select row and toggle children")
        .overlay(alignment: .bottomTrailing) {
            if isSelected { detailsButton.padding(.bottom, 3) }
        }
    }

    private var detailsButton: some View {
        Button {
            guard model.report.overview.visibleRows.contains(where: { $0.id == node.id }) else {
                return
            }
            model.report.overview.select(node.id)
            model.report.overview.toggleDetails()
        } label: {
            Image(systemName: "info.circle").frame(width: 24, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(MenuBarContributorTextStyle(link: true))
        .accessibilityLabel("Details for " + node.title)
        .help("Inspect this contributor (i); disclosure reveals children")
        .popover(isPresented: detailsPresented) {
            MenuBarContributorInspection(
                node: node, duration: model.report.overview.duration,
                canInspect: node.process.map { identity in
                    model.report.snapshot?.findings.contains {
                        $0.process == identity && !$0.isHistorical
                    } == true
                } ?? false,
                inspect: {
                    if model.report.overview.detailsVisible { model.report.overview.toggleDetails() }
                    model.report.inspectOverviewProcess()
                })
        }
    }
}

private struct MenuBarContributorCellContent: View {
    let node: ContributorNode
    let pinned: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 5) {
                if let symbol = node.id.summarySymbol {
                    Image(systemName: symbol).font(.caption)
                        .accessibilityLabel("Summary group")
                        .help("Summary group; not an individual agent session")
                }
                MenuBarContributorTableLabel(label: node.label)
            }
            HStack(spacing: 6) {
                if pinned { Image(systemName: "pin.fill").accessibilityHidden(true) }
                Text(node.stats.currentAvailable ? "Processes \(node.stats.current.count)" : "Processes —")
                    .modifier(MenuBarContributorTextStyle(secondary: true)).help(node.stats.census)
                Spacer(minLength: 0)
                Image(systemName: "info.circle").frame(width: 24, height: 20).hidden().accessibilityHidden(
                    true)
            }.font(.caption2)
        }
        .padding(.vertical, 3)
        .help(node.title + ". " + node.stats.census)
    }
}

struct MenuBarContributorTableLabel: View {
    let label: ContributorLabel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch label {
            case .text(let title):
                titleText(title)
            case .session(let identity, let name, let directory):
                titleText(identity)
                if let name { contextText(name) }
                if let directory { contextText(directory) }
            case .workload(let name, let directory):
                titleText(name)
                if let directory { contextText(directory) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func titleText(_ value: String) -> some View {
        Text(TextReport.safe(value)).font(.caption.weight(.medium))
            .modifier(MenuBarContributorTextStyle())
            .lineLimit(1).truncationMode(.middle)
    }

    private func contextText(_ value: String) -> some View {
        Text(TextReport.safe(value)).font(.caption2)
            .modifier(MenuBarContributorTextStyle(secondary: true))
            .lineLimit(1).truncationMode(.middle)
    }
}

private struct MenuBarContributorMetric: View {
    @Environment(\.backgroundProminence) private var prominence
    let value: String
    let fraction: Double

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value).monospacedDigit().lineLimit(1).modifier(MenuBarContributorTextStyle())
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(
                        prominence == .increased ? Color.white.opacity(0.25) : Color.secondary.opacity(0.2))
                    Capsule().fill(prominence == .increased ? Color.white : Color.accentColor.opacity(0.65))
                        .frame(width: geometry.size.width * min(1, max(0, fraction)))
                }
            }.frame(height: 2)
        }.frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct MenuBarContributorTextStyle: ViewModifier {
    @Environment(\.backgroundProminence) private var prominence
    var secondary = false
    var link = false

    func body(content: Content) -> some View {
        content.foregroundStyle(
            prominence == .increased
                ? Color(nsColor: .alternateSelectedControlTextColor)
                : (link ? Color.accentColor : (secondary ? Color.secondary : Color.primary)))
    }
}

struct MenuBarContributorSort: SortComparator {
    let field: ContributorOrder
    var order: SortOrder = .reverse

    func compare(_ lhs: ContributorNode, _ rhs: ContributorNode) -> ComparisonResult {
        let result: ComparisonResult
        switch field {
        case .contributor:
            result =
                lhs.title == rhs.title
                ? .orderedSame : (lhs.title < rhs.title ? .orderedAscending : .orderedDescending)
        case .cpu:
            result =
                lhs.stats.currentCPU == rhs.stats.currentCPU
                ? .orderedSame
                : (lhs.stats.currentCPU < rhs.stats.currentCPU ? .orderedAscending : .orderedDescending)
        case .memory:
            result =
                lhs.stats.memoryBytes == rhs.stats.memoryBytes
                ? .orderedSame
                : (lhs.stats.memoryBytes < rhs.stats.memoryBytes ? .orderedAscending : .orderedDescending)
        }
        return order == .forward ? result : ComparisonResult(rawValue: -result.rawValue)!
    }
}

extension ContributorID {
    var summarySymbol: String? {
        switch self {
        case .section(let section):
            switch section {
            case .recent: "clock.arrow.circlepath"
            case .remainder: "square.stack.3d.up"
            case .uncertain: "questionmark.folder"
            case .shared: "square.stack.3d.up.fill"
            case .released: "archivebox"
            }
        case .more: "ellipsis.rectangle"
        case .collapsed: "archivebox"
        case .provider: "square.stack.3d.up"
        case .session, .executable, .process: nil
        }
    }
}

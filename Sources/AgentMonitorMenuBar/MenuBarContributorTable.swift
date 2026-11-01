import AgentMonitorPresentation
import AppKit
import SwiftUI

struct MenuBarContributorTable: View {
    @State private var hovered: ContributorID?
    @Bindable var model: MenuBarModel
    var focus: FocusState<MenuBarFocus?>.Binding

    private var acceptsInteraction: Bool {
        model.isOpen && model.report.showsOverview && !model.report.overview.tableCollapsed
            && model.isReportUnobstructed
    }

    var body: some View {
        let overview = model.report.overview
        let active = acceptsInteraction
        let selectedIdentity = overview.selection
        let inspecting = overview.detailsVisible
        let rows = overview.visibleRows
        let positions = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
        var group = -1
        var currentSection = ContributorTableSection.sessions
        var sections: [ContributorID: ContributorTableSection] = [:]
        var ancestorLast: [Bool] = []
        var continuations: [ContributorID: [Int]] = [:]
        let groupIndices = rows.map { row in
            if row.depth == 0 {
                group += 1
                currentSection = overview.tableSection(for: row.id)
            }
            sections[row.id] = currentSection
            ancestorLast = Array(ancestorLast.prefix(row.depth))
            continuations[row.id] = ancestorLast.indices.filter { $0 > 0 && !ancestorLast[$0] }
            ancestorLast.append(row.isLastSibling)
            return group
        }
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                sortButton("Contributor", field: .contributor)
                Spacer(minLength: 0)
                Text("CPU history · " + overview.activity.scaleLabel).font(.system(size: 11)).foregroundStyle(
                    .secondary)
                sortButton("CPU", field: .cpu).frame(width: 80, alignment: .trailing)
                sortButton("Memory", field: .memory).frame(width: 88, alignment: .trailing)
            }.padding(.horizontal, 14).padding(.vertical, 7)
            Table(
                of: ContributorNode.self,
                selection: Binding(
                    get: { model.report.overview.selectionIsVisible ? model.report.overview.selection : nil },
                    set: { id in if acceptsInteraction, let id { model.report.overview.select(id) } }
                )
            ) {
                TableColumn("Contributor") { node in
                    let index = positions[node.id] ?? 0
                    let depth = positions[node.id].map { rows[$0].depth } ?? 0
                    MenuBarContributorRow(
                        node: node, overview: overview, depth: depth,
                        showGroupHelp: { entry in
                            if acceptsInteraction { model.showGlossary(entry) }
                        },
                        toggleDisclosure: node.children.allSatisfy {
                            !overview.includesInTable($0) || overview.pinned.contains($0)
                        }
                            ? nil
                            : {
                                if acceptsInteraction { model.report.overview.activateRow(node.id) }
                            }
                    )
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .padding(.leading, CGFloat(depth) * 18)
                    .overlay(alignment: .leading) {
                        if depth == 0 && sections[node.id] == .pinned {
                            RoundedRectangle(cornerRadius: 2).fill(Color.accentColor)
                                .frame(width: 3).padding(.vertical, 8).accessibilityHidden(true)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        HStack(spacing: 2) {
                            if let target = overview.pinTarget(for: node.id), target == node.id {
                                MenuBarContributorPin(
                                    pinned: overview.pinned.contains(target),
                                    revealed: hovered == node.id,
                                    shortcutAvailable: overview.selection == node.id
                                ) {
                                    guard acceptsInteraction else { return }
                                    model.report.overview.togglePin(for: node.id)
                                }
                            }
                            MenuBarContributorActions(model: model, node: node)
                            Button {
                                guard acceptsInteraction else { return }
                                model.report.overview.select(node.id)
                                model.report.overview.toggleDetails()
                            } label: {
                                Image(systemName: "info.circle").frame(width: 24, height: 28)
                            }
                            .buttonStyle(.borderless).help(
                                "Contributor details" + (overview.selection == node.id ? " (i)" : "")
                            )
                            .accessibilityLabel("Details for " + node.label.headline)
                        }.padding(.trailing, 4).padding(.bottom, 4)
                    }
                    .background(
                        MenuBarRowBackground(
                            tint: (sections[node.id] == .pinned ? Color.accentColor : Color.primary).opacity(
                                groupIndices.indices.contains(index) && groupIndices[index].isMultiple(of: 2)
                                    ? 0.09 : 0),
                            headlineOffset: 20, depth: depth,
                            last: positions[node.id].map { rows[$0].isLastSibling } ?? true,
                            continuations: continuations[node.id] ?? [])
                    ).onHover { inside in
                        if inside { hovered = node.id } else if hovered == node.id { hovered = nil }
                    }.padding(.top, depth == 0 && index > 0 ? 8 : 0)
                }.width(min: 280, ideal: 560)
            } rows: {
                ForEach(ContributorTableSection.allCases, id: \.self) { section in
                    let ids = overview.topLevel.filter {
                        overview.tableSection(for: $0) == section
                    }
                    if !ids.isEmpty {
                        Section(
                            isExpanded: Binding(
                                get: { !model.report.overview.collapsedSections.contains(section) },
                                set: {
                                    if acceptsInteraction {
                                        model.report.overview.setSectionExpanded($0, section: section)
                                    }
                                }
                            )
                        ) {
                            MenuBarContributorRows(
                                model: model, ids: ids, acceptsInteraction: acceptsInteraction)
                        } header: {
                            MenuBarContributorHeading(section: section) {
                                if acceptsInteraction { model.showGlossary(ReportGlossary.otherObservedWork) }
                            }
                            .help(
                                (overview.collapsedSections.contains(section) ? "Expand " : "Collapse ")
                                    + section.rawValue + " (" + section.shortcut + ")"
                            )
                            .padding(.bottom, 4)
                            .background(MenuBarRowBackground())
                        }
                    }
                }
            }
            .tableColumnHeaders(.hidden)
            .tableStyle(.inset)
            .alternatingRowBackgrounds(.enabled)
            .scrollContentBackground(.hidden)
            .accessibilityLabel(overview.title)
            .frame(minHeight: 0, maxHeight: .infinity)
            .focused(focus, equals: .overview)
            .background {
                MenuBarTableState(
                    rows: rows.map(\.id), selection: overview.selection,
                    active: active, inspecting: inspecting,
                    isCurrent: {
                        model.report.overview.selection == selectedIdentity && acceptsInteraction == active
                            && model.report.overview.detailsVisible == inspecting
                    })
            }
            .contextMenu(forSelectionType: ContributorID.self) { ids in
                if acceptsInteraction, let id = ids.first {
                    Button("Details…") {
                        model.report.overview.select(id)
                        if !model.report.overview.detailsVisible { model.report.overview.toggleDetails() }
                    }
                    .help("Contributor details" + (overview.selection == id ? " (i)" : ""))
                    if let target = overview.pinTarget(for: id) {
                        Button(
                            overview.pinned.contains(target) ? "Unpin session" : "Pin session",
                            systemImage: "pin"
                        ) {
                            model.report.overview.togglePin(for: id)
                        }
                        .help("Pin or unpin session" + (overview.selection == id ? " (.)" : ""))
                    }
                }
            }
        }
    }

    private func sortButton(_ title: String, field: ContributorOrder) -> some View {
        Button {
            guard acceptsInteraction else { return }
            let overview = model.report.overview
            model.report.overview.sort(
                by: field, ascending: overview.order == field ? !overview.ascending : field == .contributor)
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if model.report.overview.order == field {
                    Image(systemName: model.report.overview.ascending ? "chevron.up" : "chevron.down").font(
                        .caption2)
                }
            }.font(.system(size: 11, weight: .semibold))
        }.buttonStyle(.plain)
            .accessibilityIdentifier("contributor-sort-" + title.lowercased())
            .accessibilityLabel("Sort by " + title)
            .accessibilityValue(
                model.report.overview.order == field
                    ? (model.report.overview.ascending ? "Ascending" : "Descending") : "Not sorted"
            )
            .help(
                "Sort by " + title + (field == .cpu ? " (c)" : field == .memory ? " (m)" : "")
                    + "; click again or press r to reverse")
    }
}

private struct MenuBarContributorRows: TableRowContent {
    let model: MenuBarModel
    let ids: [ContributorID]
    let acceptsInteraction: Bool

    private func visibleNodes(_ ids: [ContributorID]) -> [ContributorNode] {
        ids.filter { model.report.overview.includesInTable($0) }.compactMap {
            model.report.overview.nodes[$0]
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

struct MenuBarContributorRow: View {
    @Environment(\.backgroundProminence) private var prominence
    let node: ContributorNode
    let overview: ContributorOverview
    var depth = 0
    var showGroupHelp: ((ReportGlossary.Entry) -> Void)? = nil
    var toggleDisclosure: (() -> Void)? = nil

    private var processCountHelp: String {
        MenuBarContributorCounts(stats: node.stats).help
            + (overview.hideNoLongerObserved ? " Past rows are hidden." : "")
    }

    private var workloadText: AttributedString {
        overview.workloadParts(for: node).reduce(into: AttributedString()) { result, part in
            if case .status = part { return }
            var text = AttributedString(TextReport.safe(part.text))
            if case .executable = part {
                text.font = .system(size: 12, weight: .bold)
                text.foregroundColor = prominence == .increased ? .white : .primary
            }
            result += text
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(
                        systemName: node.id.summarySymbol
                            ?? (node.process == nil ? "bubble.left" : "terminal")
                    )
                    .foregroundStyle(node.id == .section(.uncertain) ? Color.orange : Color.secondary)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TextReport.safe(node.label.headline))
                            .font(
                                .system(
                                    size: depth == 0 ? 14 : 13,
                                    weight: node.stats.isNoLongerObserved ? .regular : .semibold)
                            )
                            .italic(node.stats.isNoLongerObserved)
                    }.lineLimit(1).truncationMode(.middle).help(
                        "Full identity and paths are available in Details")
                    if let entry = node.id.groupExplanation, let showGroupHelp {
                        MenuBarGroupHelp(entry: entry) { showGroupHelp(entry) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                MenuBarContributorLane(activity: overview.activity, id: node.id).frame(width: 100, height: 32)
                Text(node.stats.cpuText(duration: overview.duration)).font(
                    .system(size: 17, weight: .semibold)
                )
                .frame(width: 80, alignment: .trailing).accessibilityLabel(
                    "CPU: " + node.stats.cpuText(duration: overview.duration))
                Text(node.stats.currentMemoryText).font(.system(size: 15, weight: .medium))
                    .frame(width: 88, alignment: .trailing).accessibilityLabel(
                        "Memory: " + node.stats.currentMemoryText)
            }.monospacedDigit()
                .opacity(node.stats.isNoLongerObserved ? (prominence == .increased ? 0.65 : 0.55) : 1)
            HStack(spacing: 6) {
                Text(workloadText)
                    .lineLimit(2).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                if let status = MenuBarContributorPresence(stats: node.stats) {
                    Image(systemName: status.symbol)
                        .frame(width: 24, height: 28).contentShape(Rectangle())
                        .help(status.help)
                        .accessibilityLabel(status.help)
                }
                if let toggleDisclosure {
                    Button(action: toggleDisclosure) {
                        HStack(spacing: 4) {
                            MenuBarContributorCounts(stats: node.stats)
                            Image(systemName: overview.isExpanded(node.id) ? "chevron.down" : "chevron.right")
                                .frame(width: 8)
                        }.font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 6).frame(width: 62, height: 32)
                            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }.buttonStyle(.borderless).accessibilityIdentifier("contributor-disclosure")
                        .accessibilityLabel(
                            (overview.isExpanded(node.id) ? "Collapse " : "Expand ") + node.label.headline
                        )
                        .help(
                            MenuBarContributorCounts(stats: node.stats).tooltip
                                + (overview.isExpanded(node.id)
                                    ? " — collapse" : " — expand")
                                + (overview.selection == node.id
                                    ? (overview.isExpanded(node.id) ? " (←)" : " (→)") : "")
                        )
                        .accessibilityValue(processCountHelp)
                } else {
                    MenuBarContributorCounts(stats: node.stats)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(minWidth: 32, minHeight: 32)
                        .accessibilityLabel(processCountHelp).help(
                            MenuBarContributorCounts(stats: node.stats).tooltip)
                }
            }.font(.system(size: 12)).foregroundStyle(
                prominence == .increased ? Color.white.opacity(0.85) : Color.secondary
            ).padding(.trailing, 84)
        }.foregroundStyle(prominence == .increased ? Color.white : Color.primary)
    }
}

struct MenuBarContributorCounts: View {
    @Environment(\.backgroundProminence) private var prominence
    let stats: ContributorStats

    static func countText(_ count: Int) -> String { count > 99 ? "99+" : String(count) }

    var tooltip: String {
        guard stats.currentAvailable else { return "Process counts unavailable" }
        return "\(stats.current.count) current"
            + (pastCount > 0 ? " · \(pastCount) no longer observed" : " processes")
    }

    var pastCount: Int {
        stats.processes.subtracting(stats.current).subtracting(stats.membershipChanged).count
    }

    var help: String {
        guard stats.currentAvailable else { return "Current and past process counts unavailable" }
        let current = stats.current.count
        var text = "\(current) currently observed \(current == 1 ? "process" : "processes")"
        if pastCount > 0 { text += "; \(pastCount) no longer observed. Exit not confirmed." }
        if stats.collapsedProcesses != nil { text += " Some retained history lacks process identities." }
        return text
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 3) {
                if stats.currentAvailable {
                    Text(Self.countText(stats.current.count))
                    Image(systemName: "circle.fill").font(.system(size: 6))
                        .frame(width: 8).accessibilityHidden(true)
                } else {
                    Text("—")
                }
            }.frame(height: 15)
            if stats.currentAvailable && pastCount > 0 {
                HStack(spacing: 2) {
                    Text(Self.countText(pastCount))
                    Image(systemName: "archivebox").frame(width: 8).accessibilityHidden(true)
                }.font(.system(size: 8, weight: .regular))
                    .foregroundStyle(prominence == .increased ? Color.white.opacity(0.7) : Color.secondary)
                    .frame(height: 11)
            }
        }.frame(width: 38, height: 28, alignment: .trailing).monospacedDigit()
            .accessibilityElement(children: .ignore).accessibilityLabel(help)
    }
}

enum MenuBarContributorPresence {
    case unavailable, changedOwnership

    init?(stats: ContributorStats) {
        if !stats.currentAvailable, stats.hasContributions {
            self = .unavailable
        } else if stats.current.isEmpty, !stats.membershipChanged.isEmpty {
            self = .changedOwnership
        } else {
            return nil
        }
    }

    var symbol: String {
        switch self {
        case .unavailable: "eye.slash"
        case .changedOwnership: "arrow.triangle.branch"
        }
    }

    var help: String {
        switch self {
        case .unavailable:
            "Current presence unavailable; see Diagnostics"
        case .changedOwnership:
            "Ownership changed; see Details"
        }
    }
}

struct MenuBarContributorLane: View {
    let activity: ContributorActivity
    var id: ContributorID? = nil
    @Environment(\.backgroundProminence) private var prominence
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            let color: Color = prominence == .increased ? .white : .accentColor
            guard !activity.spans.isEmpty else { return }
            // Equal widths represent whole intervals, not equal elapsed time
            // (architecture.md, Resource history).
            let step = floor(size.width * displayScale / Double(activity.spans.count)) / displayScale
            let leading = (size.width - step * Double(activity.spans.count)) / 2
            let gap = 1 / displayScale
            let samples = id.map { activity.samples[$0] ?? [] } ?? activity.totalSamples
            for (index, sample) in samples.enumerated() {
                let span = activity.spans[index]
                let x = leading + Double(index) * step
                guard let value = sample?.percent(in: span) else { continue }
                let height = max(1, min(1, value / activity.ceiling) * size.height)
                let bar = Path(
                    CGRect(
                        x: x + gap, y: size.height - height, width: max(gap, step - gap), height: height))
                context.fill(bar, with: .color(color.opacity(sample?.qualified == true ? 0.45 : 0.8)))
                if value > activity.ceiling {
                    let cap = Path(CGRect(x: x, y: 0, width: step, height: 2))
                    context.fill(cap, with: .color(.orange))
                }
            }
        }
        .accessibilityLabel(
            (id == nil ? "Overall contributor CPU history, " : "CPU history, ") + activity.scaleLabel + ", "
                + activity.intervalLabel
        )
        .help(
            id == nil
                ? "All contributors, including hidden rows; not whole-Mac CPU"
                : "Recent CPU averages; gaps mean unmeasured")
    }
}

extension ContributorID {
    var groupExplanation: ReportGlossary.Entry? {
        switch self {
        case .section(let section): ReportGlossary.contributorGroup(section)
        case .collapsed: ReportGlossary.contributorGroup(.released)
        case .session, .provider, .executable, .more, .process: nil
        }
    }

    var summarySymbol: String? {
        switch self {
        case .section(let section):
            switch section {
            case .recent: "tray"
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

extension ContributorTableSection {
    var symbol: String {
        switch self {
        case .pinned: "pin.fill"
        case .sessions: "bubble.left.and.bubble.right"
        case .other: "square.stack.3d.up"
        }
    }

}

private struct MenuBarContributorPin: View {
    @FocusState private var focused: Bool
    let pinned: Bool
    let revealed: Bool
    let shortcutAvailable: Bool
    let toggle: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { pinned }, set: { if $0 != pinned { toggle() } })) {
            Image(systemName: pinned ? "pin.fill" : "pin").frame(width: 24, height: 28)
        }.toggleStyle(.button).buttonStyle(.borderless)
            .focused($focused)
            .opacity(pinned || revealed || focused ? 1 : 0)
            .accessibilityLabel("Pin session").accessibilityIdentifier("contributor-pin")
            .help(
                (pinned ? "Unpin this session" : "Pin this session")
                    + (shortcutAvailable ? " (.)" : ""))
    }
}

private struct MenuBarContributorHeading: View {
    let section: ContributorTableSection
    let showGroupHelp: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Label(section.rawValue, systemImage: section.symbol)
            if section == .other {
                MenuBarGroupHelp(entry: ReportGlossary.otherObservedWork, open: showGroupHelp)
            }
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(section == .pinned ? Color.accentColor : Color.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

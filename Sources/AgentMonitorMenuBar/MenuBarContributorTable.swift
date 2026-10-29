import AgentMonitorPresentation
import AppKit
import SwiftUI

struct MenuBarContributorTable: View {
    @State private var hovered: ContributorID?
    @Bindable var model: MenuBarModel
    var focus: FocusState<MenuBarFocus?>.Binding

    private var acceptsInteraction: Bool {
        model.isOpen && model.report.showsOverview && !model.diagnosis.state.isVisible
            && model.report.actionPanel == nil
    }

    var body: some View {
        let overview = model.report.overview
        let active = acceptsInteraction
        let selectedIdentity = overview.selection
        let inspecting = overview.detailsVisible
        let rows = overview.visibleRows
        let positions = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
        var group = -1
        var currentSection = MenuBarContributorSection.sessions
        var lastSection: MenuBarContributorSection?
        var sections: [ContributorID: MenuBarContributorSection] = [:]
        var headings: [ContributorID: MenuBarContributorSection] = [:]
        let groupIndices = rows.map { row in
            if row.depth == 0 {
                group += 1
                currentSection =
                    overview.pinned.contains(row.id)
                    ? .pinned : (row.id.summarySymbol == nil ? .sessions : .other)
                if lastSection != currentSection {
                    headings[row.id] = currentSection
                }
                lastSection = currentSection
            }
            sections[row.id] = currentSection
            return group
        }
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                sortButton("Contributor", field: .contributor)
                Spacer(minLength: 0)
                Text("CPU history · " + overview.activity.scaleLabel).font(.caption).foregroundStyle(
                    .secondary)
                sortButton("CPU", field: .cpu).frame(width: 80, alignment: .trailing)
                sortButton("Memory", field: .memory).frame(width: 88, alignment: .trailing)
            }.padding(.horizontal, 14).padding(.vertical, 7)
            Table(
                of: ContributorNode.self,
                selection: Binding(
                    get: { model.report.overview.selection },
                    set: { id in if acceptsInteraction, let id { model.report.overview.select(id) } }
                )
            ) {
                TableColumn("Contributor") { node in
                    let index = positions[node.id] ?? 0
                    let depth = positions[node.id].map { rows[$0].depth } ?? 0
                    VStack(alignment: .leading, spacing: 6) {
                        if let heading = headings[node.id] {
                            MenuBarContributorHeading(section: heading)
                                .padding(.top, index > 0 ? 10 : 2)
                        }
                        MenuBarContributorRow(
                            node: node, overview: overview, depth: depth,
                            toggleDisclosure: node.children.isEmpty
                                ? nil
                                : {
                                    if acceptsInteraction { model.report.overview.activateRow(node.id) }
                                }
                        )
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .padding(.leading, CGFloat(depth) * 18)
                        .background(
                            (sections[node.id] == .pinned ? Color.accentColor : Color.primary).opacity(
                                sections[node.id] == .other
                                    ? 0.075
                                    : ((groupIndices.indices.contains(index)
                                        && groupIndices[index].isMultiple(of: 2)) ? 0.055 : 0.025)),
                            in: Rectangle()
                        )
                        .overlay(alignment: .leading) {
                            if depth > 0 {
                                MenuBarContributorBranch(last: rows[index].isLastSibling)
                                    .frame(width: 14).padding(.leading, CGFloat(depth) * 18 - 12)
                                    .allowsHitTesting(false).accessibilityHidden(true)
                            } else if sections[node.id] == .pinned {
                                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor)
                                    .frame(width: 3).padding(.vertical, 8).accessibilityHidden(true)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            HStack(spacing: 2) {
                                if let target = overview.pinTarget(for: node.id), target == node.id {
                                    MenuBarContributorPin(
                                        pinned: overview.pinned.contains(target),
                                        revealed: hovered == node.id
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
                                .buttonStyle(.borderless).help("Contributor details (i)")
                                .accessibilityLabel("Details for " + node.label.headline)
                            }.padding(.trailing, 4).padding(.bottom, 4)
                        }
                    }.background(MenuBarRowBackground()).onHover { inside in
                        if inside { hovered = node.id } else if hovered == node.id { hovered = nil }
                    }.padding(.top, depth == 0 && index > 0 && headings[node.id] == nil ? 8 : 0)
                }.width(min: 280, ideal: 560)
            } rows: {
                MenuBarContributorRows(
                    model: model, ids: overview.topLevel, acceptsInteraction: acceptsInteraction)
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
            .onKeyPress(keys: MenuBarKeyboard.keys, phases: .down) { key in
                guard acceptsInteraction, MenuBarKeyboard.accepts(key.characters, modifiers: key.modifiers)
                else { return .ignored }
                if key.characters == "q" {
                    NSApplication.shared.terminate(nil)
                    return .handled
                }
                return model.handleShortcut(key.characters, row: nil) ? .handled : .ignored
            }
            .background(
                Color(nsColor: .windowBackgroundColor).opacity(0.92), in: RoundedRectangle(cornerRadius: 8)
            )
            .contextMenu(forSelectionType: ContributorID.self) { ids in
                if acceptsInteraction, let id = ids.first {
                    Button("Details…") {
                        model.report.overview.select(id)
                        if !model.report.overview.detailsVisible { model.report.overview.toggleDetails() }
                    }
                    if let target = overview.pinTarget(for: id) {
                        Button(
                            overview.pinned.contains(target) ? "Unpin session" : "Pin session",
                            systemImage: "pin"
                        ) {
                            model.report.overview.togglePin(for: id)
                        }
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
            }.font(.caption.weight(.semibold))
        }.buttonStyle(.plain)
            .accessibilityIdentifier("contributor-sort-" + title.lowercased())
            .accessibilityLabel("Sort by " + title)
            .accessibilityValue(
                model.report.overview.order == field
                    ? (model.report.overview.ascending ? "Ascending" : "Descending") : "Not sorted"
            )
            .help("Sort by " + title + "; click again to reverse")
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

struct MenuBarContributorRow: View {
    @Environment(\.backgroundProminence) private var prominence
    let node: ContributorNode
    let overview: ContributorOverview
    var depth = 0
    var toggleDisclosure: (() -> Void)? = nil

    private var processCountHelp: String {
        guard node.stats.currentAvailable else { return "Current process count unavailable" }
        let count = node.stats.current.count
        return "\(count) currently observed \(count == 1 ? "process" : "processes") in this contributor"
    }

    private var workloadText: AttributedString {
        overview.workloadParts(for: node).reduce(into: AttributedString()) { result, part in
            var text = AttributedString(TextReport.safe(part.text))
            if case .executable = part {
                text.font = .system(size: 13, weight: .bold)
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
                                .system(size: depth == 0 ? 15 : 14, weight: .semibold))
                    }.lineLimit(1).truncationMode(.middle)
                }.frame(maxWidth: .infinity, alignment: .leading)
                MenuBarContributorLane(activity: overview.activity, id: node.id).frame(width: 100, height: 32)
                Text(node.stats.cpuText(duration: overview.duration)).font(
                    .system(size: 18, weight: .semibold)
                )
                .frame(width: 80, alignment: .trailing).accessibilityLabel(
                    "CPU: " + node.stats.cpuText(duration: overview.duration))
                Text(node.stats.currentMemoryText).font(.system(size: 16, weight: .medium))
                    .frame(width: 88, alignment: .trailing).accessibilityLabel(
                        "Memory: " + node.stats.currentMemoryText)
            }.monospacedDigit()
            HStack(spacing: 6) {
                Text(workloadText)
                    .lineLimit(2).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                if let toggleDisclosure {
                    Button(action: toggleDisclosure) {
                        HStack(spacing: 5) {
                            Text(node.stats.currentAvailable ? "\(node.stats.current.count)" : "—")
                            Image(systemName: overview.isExpanded(node.id) ? "chevron.down" : "chevron.right")
                        }.font(.system(size: 13, weight: .semibold)).frame(minWidth: 44, minHeight: 32)
                            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.borderless).accessibilityIdentifier("contributor-disclosure")
                        .accessibilityLabel(
                            (overview.isExpanded(node.id) ? "Collapse " : "Expand ") + node.label.headline
                        )
                        .help(
                            processCountHelp
                                + (overview.isExpanded(node.id)
                                    ? " — click to collapse" : " — click to expand")
                        )
                        .accessibilityValue(processCountHelp)
                } else {
                    Text(node.stats.currentAvailable ? "\(node.stats.current.count)" : "—")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(minWidth: 32, minHeight: 32)
                        .accessibilityLabel(processCountHelp).help(processCountHelp)
                }
            }.font(.system(size: 13)).foregroundStyle(
                prominence == .increased ? Color.white.opacity(0.85) : Color.secondary
            ).padding(.trailing, 84)
        }.foregroundStyle(prominence == .increased ? Color.white : Color.primary).help(
            node.title + ". " + node.stats.census)
    }
}

private struct MenuBarContributorBranch: View {
    let last: Bool

    var body: some View {
        Canvas { context, size in
            var branch = Path()
            branch.move(to: CGPoint(x: 1, y: 0))
            branch.addLine(to: CGPoint(x: 1, y: last ? size.height / 2 : size.height))
            branch.move(to: CGPoint(x: 1, y: size.height / 2))
            branch.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(branch, with: .foreground, lineWidth: 1.5)
        }.foregroundStyle(.secondary.opacity(0.6))
    }
}

struct MenuBarContributorLane: View {
    let activity: ContributorActivity
    let id: ContributorID
    @Environment(\.backgroundProminence) private var prominence
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            let color: Color = prominence == .increased ? .white : .accentColor
            guard !activity.spans.isEmpty else { return }
            // Whole intervals are ordinal bars, with pixel-aligned equal widths; unequal durations
            // remain explicit in the caption (architecture.md, Resource history).
            let step = floor(size.width * displayScale / Double(activity.spans.count)) / displayScale
            let leading = (size.width - step * Double(activity.spans.count)) / 2
            let gap = 1 / displayScale
            for (index, sample) in (activity.samples[id] ?? []).enumerated() {
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
        .accessibilityLabel("CPU history, " + activity.scaleLabel + ", " + activity.intervalLabel)
        .help(
            "CPU history · " + activity.scaleLabel + " · " + activity.intervalLabel
                + ". Fixed display range; 100% is one CPU-second per elapsed second. Change it in View options or with b. Equal-width bars are whole interval averages, oldest left and newest right, regardless of duration. Gaps are unmeasured; shaded spans have incomplete observations or reduced detail. An orange cap marks values above the fixed ceiling; open contributor details for actual interval values."
        )
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

private enum MenuBarContributorSection: String {
    case pinned = "Pinned"
    case sessions = "Sessions"
    case other = "Other observed work"

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
    let toggle: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { pinned }, set: { if $0 != pinned { toggle() } })) {
            Image(systemName: pinned ? "pin.fill" : "pin").frame(width: 24, height: 28)
        }.toggleStyle(.button).buttonStyle(.borderless)
            .focused($focused)
            .opacity(pinned || revealed || focused ? 1 : 0)
            .accessibilityLabel("Pin session").accessibilityIdentifier("contributor-pin")
            .help(pinned ? "Unpin session" : "Pin session")
    }
}

private struct MenuBarContributorHeading: View {
    @Environment(\.backgroundProminence) private var prominence
    let section: MenuBarContributorSection

    var body: some View {
        Label(section.rawValue, systemImage: section.symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(
                prominence == .increased
                    ? Color.white : (section == .pinned ? Color.accentColor : Color.secondary)
            )
            .accessibilityAddTraits(.isHeader)
    }
}

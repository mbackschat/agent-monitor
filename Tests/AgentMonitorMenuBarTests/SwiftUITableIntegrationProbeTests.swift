import AgentMonitorPresentation
import AppKit
import SwiftUI
import Testing

@testable import AgentMonitorMenuBar

@Test(
    .enabled(if: ProcessInfo.processInfo.environment["SWIFTUI_TABLE_TRIAGE"] == "1"),
    arguments: [false, true])
@MainActor func swiftUITableProductionOverviewFollowingRootReproduction(constant: Bool) async throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, _ in }
    model.report.receive(snapshot)
    let section = ContributorID.section(.remainder)
    model.report.overview.setDisclosure(expanded: true, for: section)
    let session = try #require(model.report.overview.nodes[section]?.children.last)
    model.report.overview.setDisclosure(expanded: true, for: session)
    let contributor = try #require(model.report.overview.nodes[session]?.children.first)
    model.report.overview.setDisclosure(expanded: true, for: contributor)
    let process = try #require(model.report.overview.nodes[contributor]?.children.first)
    try #require(model.report.overview.topLevel.last != section)
    let expandedIDs = model.report.overview.open
    let host = NSHostingView(
        rootView: IntegrationTable(model: model, constant: constant))
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 240)
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    for phase in IntegrationPhase.allCases {
        switch phase {
        case .collapse: model.report.overview.setDisclosure(expanded: false, for: section)
        case .reopen: model.report.overview.setDisclosure(expanded: true, for: section)
        case .refresh: model.report.receive(snapshot)
        case .initial: break
        }
        let expected = model.report.overview.visibleRows
        let deadline = ContinuousClock.now + .seconds(2)
        while integrationOutline(in: host)?.numberOfRows != expected.count, ContinuousClock.now < deadline {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        host.layoutSubtreeIfNeeded()
        let table = try #require(integrationOutline(in: host))
        let levels = (0..<table.numberOfRows).map { table.level(forRow: $0) }
        if phase == .initial {
            // The standalone following-root arm isolates this initial-reconciliation failure; see
            // docs/research/native-menu-design.md#swiftui-following-root-triage--2026-10-27.
            let knownFailureLevels = expected.filter { $0.depth < 2 }.map(\.depth)
            withKnownIssue(
                "SwiftUI initially omits expanded descendants before a following root",
                { #expect(levels == expected.map(\.depth)) },
                matching: { _ in levels == knownFailureLevels })
        } else {
            #expect(levels == expected.map(\.depth))
        }
        if phase != .collapse { #expect(model.report.overview.open == expandedIDs) }
        if let row = expected.firstIndex(where: { $0.id == process }), levels == expected.map(\.depth) {
            table.deselectAll(nil)
            table.scrollRowToVisible(row)
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            #expect(model.report.overview.selection == process)
        }
    }
}

private enum IntegrationPhase: CaseIterable {
    case initial, collapse, reopen, refresh
}

private struct IntegrationTable: View {
    @Bindable var model: MenuBarModel
    let constant: Bool

    var body: some View {
        let overview = model.report.overview
        Table(
            of: ContributorNode.self,
            selection: Binding(
                get: { model.report.overview.selection },
                set: { if let id = $0 { model.report.overview.select(id) } }
            )
        ) {
            TableColumn("Contributor") { node in MenuBarContributorTableLabel(label: node.label) }
            TableColumn("CPU") { node in Text(node.stats.cpuText(duration: overview.duration)) }
            TableColumn("Memory") { node in Text(node.stats.memoryText) }
        } rows: {
            IntegrationRows(model: model, ids: overview.topLevel, constant: constant)
        }
    }
}

private struct IntegrationRows: TableRowContent {
    let model: MenuBarModel
    let ids: [ContributorID]
    let constant: Bool

    @TableRowBuilder<ContributorNode> var tableRowBody: some TableRowContent<ContributorNode> {
        ForEach(ids.compactMap { model.report.overview.nodes[$0] }) { node in
            if node.children.isEmpty {
                TableRow(node)
            } else {
                DisclosureTableRow(
                    node,
                    isExpanded: constant
                        ? .constant(model.report.overview.isExpanded(node.id))
                        : Binding(
                            get: { model.report.overview.isExpanded(node.id) },
                            set: { model.report.overview.setDisclosure(expanded: $0, for: node.id) }
                        )
                ) {
                    IntegrationRows(model: model, ids: node.children, constant: constant)
                }
            }
        }
    }
}

@MainActor private func integrationOutline(in view: NSView) -> NSOutlineView? {
    if let table = view as? NSOutlineView { return table }
    return view.subviews.lazy.compactMap { integrationOutline(in: $0) }.first
}

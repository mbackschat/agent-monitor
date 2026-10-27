import AgentMonitorPresentation
import AppKit
import SwiftUI
import Testing

@testable import AgentMonitorMenuBar

@Test(.enabled(if: ProcessInfo.processInfo.environment["SWIFTUI_TABLE_RETENTION"] == "1"))
@MainActor func retainedSwiftUITableSurvivesCoveredInspection() async throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, _ in }
    model.report.receive(snapshot)
    let surface = RetainedTableSurface()
    let host = NSHostingView(rootView: RetainedTableProbe(model: model, surface: surface))
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 240)
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    let original = try #require(integrationOutline(in: host))
    let section = ContributorID.section(.remainder)
    model.report.overview.setDisclosure(expanded: true, for: section)
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    let session = try #require(model.report.overview.nodes[section]?.children.last)
    model.report.overview.setDisclosure(expanded: true, for: session)
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    let contributor = try #require(model.report.overview.nodes[session]?.children.first)
    model.report.overview.setDisclosure(expanded: true, for: contributor)
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    let process = try #require(model.report.overview.nodes[contributor]?.children.first)
    let expected = model.report.overview.visibleRows
    try #require(original.numberOfRows == expected.count)
    let selectedRow = try #require(expected.firstIndex { $0.id == process })
    original.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
    original.scrollRowToVisible(selectedRow)
    let scroll = try #require(original.enclosingScrollView)
    let open = model.report.overview.open
    for screen in [RetainedTableSurface.Screen.diagnosis, .review] {
        let before = try await retentionFrame(host)
        let origin = scroll.contentView.bounds.origin
        surface.screen = screen
        await settleContributorTable(in: host, expectedRows: expected.count)
        #expect(integrationOutline(in: host) === original)
        model.report.receive(snapshot)
        surface.screen = .report
        await settleContributorTable(in: host, expectedRows: expected.count)
        let after = try await retentionFrame(host)
        #expect(integrationOutline(in: host) === original)
        #expect((0..<original.numberOfRows).map { original.level(forRow: $0) } == expected.map(\.depth))
        #expect(original.selectedRow == selectedRow)
        #expect(model.report.overview.selection == process)
        #expect(model.report.overview.open == open)
        #expect(scroll.contentView.bounds.origin == origin)
        #expect(before == after)
    }
}

@Observable @MainActor private final class RetainedTableSurface {
    enum Screen { case report, diagnosis, review }
    var screen: Screen = .report
}

private struct RetainedTableProbe: View {
    let model: MenuBarModel
    let surface: RetainedTableSurface

    var body: some View {
        let active = surface.screen == .report
        ZStack {
            IntegrationTable(model: model, constant: false)
                .opacity(active ? 1 : 0)
                .disabled(!active)
                .allowsHitTesting(active)
                .accessibilityHidden(!active)
            if !active {
                Color(nsColor: .windowBackgroundColor).overlay { Text("Inspection") }
            }
        }
    }
}

@MainActor private func retentionFrame(_ view: NSView) async throws -> Data {
    var previous = Data()
    var stablePasses = 0
    let deadline = ContinuousClock.now + .seconds(2)
    while stablePasses < 2, ContinuousClock.now < deadline {
        await Task.yield()
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let current = Data(
            bytes: try #require(bitmap.bitmapData), count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        stablePasses = current == previous ? stablePasses + 1 : 0
        previous = current
    }
    try #require(stablePasses == 2)
    return previous
}

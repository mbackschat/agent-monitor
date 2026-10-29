import AgentMonitorPresentation
import AppKit
import SwiftUI
import Testing

@testable import AgentMonitorMenuBar

@Test @MainActor func nativeContributorTableSurvivesInspectionAndProcessViews() async throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel(
        diagnosisSource: { try await menuBarDiagnosisFixture() },
        source: { _, _, receive in try await receive(snapshot) })
    model.open()
    await model.waitForCollection()
    let host = NSHostingView(
        rootView: MenuBarView(model: model).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.frame = NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: 560)
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    let original = try #require(contributorOutline(in: host))
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
    #expect(original.level(forRow: selectedRow) == 3)
    original.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
    original.scrollRowToVisible(selectedRow)
    let scroll = try #require(original.enclosingScrollView)
    let open = model.report.overview.open
    for screen in [InspectionScreen.diagnosis, .process, .review] {
        _ = try await retentionFrame(host)
        let before = try await retentionFrame(scroll)
        let origin = scroll.contentView.bounds.origin
        switch screen {
        case .diagnosis:
            try #require(model.beginDiagnosis())
            await model.diagnosis.waitForCompletion()
        case .process, .review:
            model.report.inspectOverviewProcess()
            try #require(!model.report.showsOverview)
            if screen == .review {
                let row = try #require(model.report.selection)
                model.begin(.terminate, row: row)
                try #require(model.report.actionPanel != nil)
            }
        }
        _ = try await retentionFrame(host)
        #expect(contributorOutline(in: host) === original)
        #expect(window.firstResponder !== original, "Hidden table retained focus during \(screen)")
        model.report.receive(snapshot)
        switch screen {
        case .diagnosis: model.diagnosis.dismiss()
        case .process: model.report.overview.enabled = true
        case .review:
            model.input(.escape)
            model.report.overview.enabled = true
        }
        _ = try await retentionFrame(host)
        #expect(contributorOutline(in: host) === original)
        #expect((0..<original.numberOfRows).map { original.level(forRow: $0) } == expected.map(\.depth))
        #expect(original.selectedRow == selectedRow)
        #expect(model.report.overview.selection == process)
        #expect(model.report.overview.open == open)
        #expect(abs(scroll.contentView.bounds.origin.y - origin.y) <= 1)
        let after = try await retentionFrame(scroll)
        #expect(before == after)
    }
    model.report.overview.toggleDetails()
    try #require(model.beginDiagnosis())
    await model.diagnosis.waitForCompletion()
    model.report.overview.toggleDetails()
    _ = try await retentionFrame(host)
    #expect(window.firstResponder !== original, "Hidden details change stole focus")
    model.diagnosis.dismiss()
    for order in [ContributorOrder.memory, .cpu] {
        model.report.overview.sort(by: order)
        await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
        _ = try await retentionFrame(host)
        let rows = model.report.overview.visibleRows
        #expect((0..<original.numberOfRows).map { original.level(forRow: $0) } == rows.map(\.depth))
        #expect(original.selectedRow == rows.firstIndex { $0.id == process })
    }
    let controller = MenuBarOptionsController(model: model)
    let menu = controller.makeMenu()
    let stable = try #require(menu.item(withTitle: "Stable order"))
    let stableRows = model.report.overview.visibleRows
    let stableOpen = model.report.overview.open
    menu.performActionForItem(at: menu.index(of: stable))
    _ = try await retentionFrame(host)
    #expect(model.report.showsOverview)
    #expect(contributorOutline(in: host) === original)
    #expect(model.report.overview.visibleRows == stableRows)
    #expect(model.report.overview.open == stableOpen)
    #expect(model.report.overview.selection == process)
    for _ in 0..<2 {
        let changed = model.report.overview.togglePin()
        try #require(changed)
        await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
        _ = try await retentionFrame(host)
        let rows = model.report.overview.visibleRows
        #expect((0..<original.numberOfRows).map { original.level(forRow: $0) } == rows.map(\.depth))
        #expect(model.report.overview.selection == process)
        #expect(original.selectedRow == rows.firstIndex { $0.id == process })
    }
    await model.stop()
}

private enum InspectionScreen { case diagnosis, process, review }

@Test @MainActor func queuedTableReconciliationPreservesNewerNativeSelection() async throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let host = NSHostingView(rootView: MenuBarView(model: model))
    host.frame = NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: 560)
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    let outline = try #require(contributorOutline(in: host))
    let ids = model.report.overview.visibleRows.map(\.id)
    try #require(ids.count >= 2)
    outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    let anchor = NSView()
    host.addSubview(anchor)
    let coordinator = MenuBarTableState.Coordinator()
    coordinator.update(
        MenuBarTableState(
            rows: ids, selection: ids[0], active: true, inspecting: false,
            isCurrent: { model.report.overview.selection == ids[0] }), view: anchor)
    outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    try #require(model.report.overview.selection == ids[1])
    await coordinator.pending?.value
    #expect(outline.selectedRow == 1)
    #expect(model.report.overview.selection == ids[1])
    await model.stop()
}

@MainActor private func retentionFrame(_ view: NSView) async throws -> Data {
    var previous = Data()
    var stablePasses = 0
    // Count rendered frames: concurrent MainActor OCR can consume a wall-clock deadline before
    // this task gets a second frame (ledger native-suite run, 2026-10-28).
    for _ in 0..<120 {
        if stablePasses == 2 { break }
        try await Task.sleep(for: .milliseconds(16))
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

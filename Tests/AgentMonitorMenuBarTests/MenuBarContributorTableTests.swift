import AgentMonitorPresentation
import AppKit
import SwiftUI
import Testing

@testable import AgentMonitorMenuBar

@Test @MainActor func nativeOverviewUsesAnOutlineTableWithSharedIdentityAndDisclosure() async throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let host = NSHostingView(rootView: MenuBarView(model: model))
    host.frame = NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: 720)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = host
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    let parent = try #require(model.report.overview.main.first)
    model.report.overview.toggle(parent)
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    let contributor = try #require(model.report.overview.nodes[parent]?.children.first)
    model.report.overview.setDisclosure(expanded: true, for: contributor)
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    let outline = try #require(contributorOutline(in: host))
    let columnCount = outline.numberOfColumns
    let rowCount = outline.numberOfRows
    let levels = (0..<min(3, rowCount)).map { outline.level(forRow: $0) }
    let contributorExpanded = rowCount > 1 && outline.isItemExpanded(outline.item(atRow: 1))
    let processExpandable = rowCount > 2 && outline.isExpandable(outline.item(atRow: 2))
    #expect(columnCount == 1)
    #expect(outline.headerView == nil)
    #expect(rowCount == model.report.overview.visibleRows.count)
    #expect(levels == [0, 1, 2])
    #expect(contributorExpanded)
    #expect(!processExpandable)
    #expect(outline.usesAlternatingRowBackgroundColors)
    outline.enumerateAvailableRowViews { row, _ in
        #expect(row.backgroundColor.alphaComponent == 0)
    }
    let selectedRow = try #require(outline.rowView(atRow: outline.selectedRow, makeIfNecessary: true))
    #expect(selectedRow.isSelected)
    #expect(
        outline.bounds.width <= MenuBarLayout.width - 28,
        "Column widths \(outline.tableColumns.map(\.width)); viewport \(String(describing: outline.enclosingScrollView?.contentSize))"
    )
    window.contentView = nil
    await model.stop()
}

@MainActor func contributorOutline(in view: NSView) -> NSOutlineView? {
    if let outline = view as? NSOutlineView { return outline }
    return view.subviews.lazy.compactMap { contributorOutline(in: $0) }.first
}

@Test @MainActor func nativeContributorTableSelectionAndDisclosureRemainIndependent() async throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let parent = try #require(model.report.overview.main.first)
    let other = try #require(model.report.overview.main.last)
    try #require(parent != other)
    let host = NSHostingView(rootView: MenuBarView(model: model))
    host.frame = NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: 720)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = host
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    let outline = try #require(contributorOutline(in: host))
    let otherRow = try #require(model.report.overview.visibleRows.firstIndex { $0.id == other })
    outline.selectRowIndexes(IndexSet(integer: otherRow), byExtendingSelection: false)
    #expect(model.report.overview.selection == other)
    #expect(!model.report.overview.open.contains(other))
    outline.expandItem(outline.item(atRow: 0))
    host.layoutSubtreeIfNeeded()
    #expect(model.report.overview.open.contains(parent))
    #expect(model.report.overview.selection == other)
    #expect(outline.numberOfRows == model.report.overview.visibleRows.count)
    window.contentView = nil
    await model.stop()
}

@MainActor func settleContributorTable(in host: NSView, expectedRows: Int) async {
    for _ in 0..<20 {
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        if contributorOutline(in: host)?.numberOfRows == expectedRows { return }
    }
}

@Test @MainActor func nativeContributorNavigationSelectsOnceAndTabsAway() async throws {
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
    let expected = try #require(model.report.overview.visibleRows.dropFirst().first?.id)
    let focusDeadline = ContinuousClock.now + .seconds(2)
    while window.firstResponder !== outline, ContinuousClock.now < focusDeadline {
        host.layoutSubtreeIfNeeded()
        await Task.yield()
    }
    #expect(window.firstResponder === outline)
    window.makeFirstResponder(outline)
    outline.keyDown(with: try contributorKey("\u{F701}", code: 125, window: window))
    #expect(model.report.overview.selection == expected)
    #expect(outline.selectedRow == 1)
    let next = try #require(contributorOptions(in: host))
    outline.nextKeyView = next
    outline.keyDown(with: try contributorKey("\t", code: 48, window: window))
    #expect(window.firstResponder !== outline)
    await model.stop()
}

@MainActor private func contributorKey(_ characters: String, code: UInt16, window: NSWindow) throws -> NSEvent
{
    try #require(
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
}

@MainActor private func contributorOptions(in view: NSView) -> NSPopUpButton? {
    if let button = view as? NSPopUpButton, button.menu?.title == "View options" { return button }
    return view.subviews.lazy.compactMap { contributorOptions(in: $0) }.first
}

@Test @MainActor func nativeContributorRefreshKeepsItemsSelectionDisclosureAndScroll() async throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    model.report.overview.setDisclosure(expanded: true, for: .section(.remainder))
    let selected = try #require(model.report.overview.selection)
    let open = model.report.overview.open
    let host = NSHostingView(rootView: MenuBarView(model: model))
    host.frame = NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: 560)
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    let outline = try #require(contributorOutline(in: host))
    let scroll = try #require(outline.enclosingScrollView)
    outline.scrollRowToVisible(outline.numberOfRows - 1)
    let origin = scroll.contentView.bounds.origin
    model.report.receive(snapshot)
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    host.layoutSubtreeIfNeeded()
    #expect(contributorOutline(in: host) === outline)
    #expect(model.report.overview.selection == selected)
    #expect(model.report.overview.open == open)
    #expect(abs(scroll.contentView.bounds.origin.y - origin.y) <= 1)
    #expect(outline.selectedRow == model.report.overview.visibleRows.firstIndex { $0.id == selected })
    model.report.overview.sort(by: .memory)
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    host.layoutSubtreeIfNeeded()
    #expect(model.report.overview.selection == selected)
    #expect(outline.selectedRow == model.report.overview.visibleRows.firstIndex { $0.id == selected })
    #expect(model.report.overview.open == open)
    await model.stop()
}

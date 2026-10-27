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
    let parent = try #require(model.report.overview.main.first)
    model.report.overview.toggle(parent)
    let contributor = try #require(model.report.overview.nodes[parent]?.children.first)
    model.report.overview.setDisclosure(expanded: true, for: contributor)
    let host = NSHostingView(rootView: MenuBarView(model: model))
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 720)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = host
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    let outline = try #require(contributorOutline(in: host))
    let columnCount = outline.numberOfColumns
    let rowCount = outline.numberOfRows
    let levels = (0..<min(3, rowCount)).map { outline.level(forRow: $0) }
    let contributorExpanded = rowCount > 1 && outline.isItemExpanded(outline.item(atRow: 1))
    let processExpandable = rowCount > 2 && outline.isExpandable(outline.item(atRow: 2))
    #expect(columnCount == 3)
    #expect(rowCount == model.report.overview.visibleRows.count)
    #expect(levels == [0, 1, 2])
    #expect(contributorExpanded)
    #expect(!processExpandable)
    #expect(outline.usesAlternatingRowBackgroundColors)
    let selectedRow = try #require(outline.rowView(atRow: outline.selectedRow, makeIfNecessary: true))
    #expect(selectedRow.isSelected)
    for row in 0..<min(rowCount, 3) {
        let frame = outline.rect(ofRow: row)
        for column in 0..<columnCount {
            let cell = try #require(outline.view(atColumn: column, row: row, makeIfNecessary: true))
            let hosting = try #require(contributorHosting(in: cell))
            let contentHeight = hosting.fittingSize.height
            #expect(contentHeight <= frame.height + 1)
            #expect(hosting.frame.height <= frame.height + 1)
        }
        if row > 0 { #expect(outline.rect(ofRow: row - 1).maxY <= frame.minY) }
    }
    #expect(
        outline.bounds.width <= 392,
        "Column widths \(outline.tableColumns.map(\.width)); viewport \(String(describing: outline.enclosingScrollView?.contentSize))"
    )
    window.contentView = nil
    await model.stop()
}

@MainActor private func contributorOutline(in view: NSView) -> NSOutlineView? {
    if let outline = view as? NSOutlineView { return outline }
    return view.subviews.lazy.compactMap { contributorOutline(in: $0) }.first
}

@MainActor private func contributorHosting(in view: NSView) -> NSHostingView<AnyView>? {
    if let hosting = view as? NSHostingView<AnyView> { return hosting }
    return view.subviews.lazy.compactMap { contributorHosting(in: $0) }.first
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
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 720)
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
        if contributorOutline(in: host)?.numberOfRows == expectedRows { return }
        await Task.yield()
    }
}

@Test @MainActor func nativeContributorKeysSelectOnceInspectTheSelectedIdentityAndPause() async throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let host = NSHostingView(rootView: MenuBarView(model: model))
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 560)
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    let outline = try #require(contributorOutline(in: host))
    let expected = try #require(model.report.overview.visibleRows.dropFirst().first?.id)
    let focusDeadline = ContinuousClock.now + .seconds(30)
    while window.firstResponder !== outline, ContinuousClock.now < focusDeadline {
        host.layoutSubtreeIfNeeded()
        await Task.yield()
    }
    #expect(window.firstResponder === outline)
    window.makeFirstResponder(outline)
    outline.keyDown(with: try contributorKey("\u{F701}", code: 125, window: window))
    #expect(model.report.overview.selection == expected)
    #expect(outline.selectedRow == 1)
    outline.keyDown(with: try contributorKey("i", code: 34, window: window))
    #expect(model.report.overview.selection == expected)
    #expect(model.report.overview.detailsVisible)
    for (characters, code) in [
        ("\u{F700}", UInt16(126)), ("\u{F701}", 125), ("\u{F702}", 123), ("\u{F703}", 124),
    ] {
        outline.keyDown(with: try contributorKey(characters, code: code, window: window))
        #expect(model.report.overview.selection == expected)
        #expect(model.report.overview.detailsVisible)
    }
    outline.keyDown(with: try contributorKey("i", code: 34, window: window))
    #expect(!model.report.overview.detailsVisible)
    outline.keyDown(with: try contributorKey("p", code: 35, window: window))
    #expect(model.report.frozen)
    outline.keyDown(with: try contributorKey("p", code: 35, window: window))
    #expect(!model.report.frozen)
    outline.keyDown(with: try contributorKey(".", code: 47, window: window))
    #expect(model.report.overview.pinned.contains(expected))
    outline.keyDown(with: try contributorKey(".", code: 47, window: window))
    #expect(!model.report.overview.pinned.contains(expected))
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

@Test @MainActor func nativeContributorOutlineHonorsFocusRequestedBeforeItsFirstUpdate() async throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let configuration = MenuBarContributorOutline(
        model: model, overview: model.report.overview, focused: true, focusChanged: { _ in },
        cell: { node, _ in AnyView(Text(node.title)) }, height: { _, _ in 44 })
    let coordinator = configuration.makeCoordinator()
    let scroll = configuration.makeScrollView(coordinator: coordinator)
    scroll.frame = NSRect(x: 0, y: 0, width: 392, height: 300)
    let window = NSWindow(
        contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = scroll
    let outline = try #require(contributorOutline(in: scroll))
    #expect(window.firstResponder === outline)
    coordinator.update(configuration, scroll: scroll)
    #expect(window.firstResponder === outline)
    await model.stop()
}

@Test @MainActor func nativeContributorTableRestoresOffscreenExpansionBeforeKeyboardSelection() async throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let section = ContributorID.section(.remainder)
    model.report.overview.setDisclosure(expanded: true, for: section)
    let session = try #require(model.report.overview.nodes[section]?.children.last)
    model.report.overview.setDisclosure(expanded: true, for: session)
    let contributor = try #require(model.report.overview.nodes[session]?.children.first)
    model.report.overview.setDisclosure(expanded: true, for: contributor)
    let process = try #require(model.report.overview.nodes[contributor]?.children.first)
    let host = NSHostingView(rootView: MenuBarView(model: model))
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 560)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = host
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    let outline = try #require(contributorOutline(in: host))
    try #require(outline.numberOfRows == model.report.overview.visibleRows.count)
    let row = try #require(model.report.overview.visibleRows.firstIndex { $0.id == process })
    #expect(outline.level(forRow: row) == 3)
    outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    #expect(model.report.overview.selection == process)
    window.contentView = nil
    await model.stop()
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
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 560)
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    let outline = try #require(contributorOutline(in: host))
    let scroll = try #require(outline.enclosingScrollView)
    let item = outline.item(atRow: outline.selectedRow) as AnyObject
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
    #expect(outline.item(atRow: outline.selectedRow) as AnyObject === item)
    model.report.overview.sort(by: .memory)
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    host.layoutSubtreeIfNeeded()
    #expect(model.report.overview.selection == selected)
    #expect(outline.item(atRow: outline.selectedRow) as AnyObject === item)
    #expect(model.report.overview.open == open)
    await model.stop()
}

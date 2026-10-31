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
    let dataRows = outline.contributorRowIndexes
    let rowCount = dataRows.count
    let levels = dataRows.prefix(3).map { outline.level(forRow: $0) }
    let contributorExpanded = rowCount > 1 && outline.isItemExpanded(outline.item(atRow: dataRows[1]))
    let processExpandable = rowCount > 2 && outline.isExpandable(outline.item(atRow: dataRows[2]))
    #expect(columnCount == 1)
    #expect(outline.headerView == nil)
    #expect(rowCount == model.report.overview.visibleRows.count)
    #expect(levels == [1, 2, 3])
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
    model.report.overview.togglePin(for: parent)
    let host = NSHostingView(rootView: MenuBarView(model: model))
    host.frame = NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: 720)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = host
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    let outline = try #require(contributorOutline(in: host))
    let headings = (0..<outline.numberOfRows).filter { row in
        guard let item = outline.item(atRow: row) else { return false }
        return outline.delegate?.outlineView?(outline, isGroupItem: item) == true
    }
    try #require(headings.count == 3, "Pinned, Sessions and Other observed work need independent headers")
    for row in headings {
        let item = try #require(outline.item(atRow: row))
        #expect(outline.delegate?.outlineView?(outline, shouldSelectItem: item) == false)
    }
    let otherIndex = try #require(model.report.overview.visibleRows.firstIndex { $0.id == other })
    let otherRow = outline.contributorRowIndexes[otherIndex]
    outline.selectRowIndexes(IndexSet(integer: otherRow), byExtendingSelection: false)
    #expect(model.report.overview.selection == other)
    #expect(!model.report.overview.open.contains(other))
    outline.expandItem(outline.item(atRow: outline.contributorRowIndexes[0]))
    host.layoutSubtreeIfNeeded()
    #expect(model.report.overview.open.contains(parent))
    #expect(model.report.overview.selection == other)
    #expect(outline.contributorRowIndexes.count == model.report.overview.visibleRows.count)
    let rowOrder = model.report.overview.visibleRows.map(\.id)
    for _ in 0..<2 {
        model.report.overview.togglePin(for: other)
        await settleContributorTable(in: host, expectedRows: rowOrder.count)
        #expect(model.report.overview.visibleRows.map(\.id) == rowOrder)
        #expect(contributorOutline(in: host) === outline)
        #expect(model.report.overview.selection == other)
        let selectedIndex = try #require(rowOrder.firstIndex(of: other))
        #expect(outline.selectedRow == outline.contributorRowIndexes[selectedIndex])
    }
    let currentHeaders = Set(0..<outline.numberOfRows).subtracting(outline.contributorRowIndexes)
    for row in currentHeaders {
        let heading = try #require(outline.rowView(atRow: row, makeIfNecessary: true))
        #expect(!heading.isSelected)
    }
    let controller = MenuBarOptionsController(model: model)
    let menu = controller.makeMenu()
    let filterIndex = try #require(menu.items.firstIndex { $0.title == "Hide no longer observed" })
    let totals = model.report.overview.totals
    menu.performActionForItem(at: filterIndex)
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    #expect(model.report.overview.hideNoLongerObserved)
    #expect(model.report.overview.hiddenHistoricalRowCount > 0)
    #expect(outline.contributorRowIndexes.count == model.report.overview.visibleRows.count)
    #expect(model.report.overview.visibleRows.allSatisfy { !$0.node.stats.isNoLongerObserved })
    #expect(model.report.overview.totals == totals)
    #expect(contributorOutline(in: host) === outline)
    controller.menuNeedsUpdate(menu)
    #expect(menu.item(withTitle: "Hide no longer observed")?.state == .on)
    menu.performActionForItem(at: filterIndex)
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    #expect(!model.report.overview.hideNoLongerObserved)
    window.contentView = nil
    await model.stop()
}

@MainActor func settleContributorTable(in host: NSView, expectedRows: Int) async {
    for _ in 0..<20 {
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        if contributorOutline(in: host)?.contributorRowIndexes.count == expectedRows { return }
    }
}

@Test @MainActor func nativeContributorNavigationSelectsOnceAndTabsAway() async throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    model.report.overview.togglePin(for: try #require(model.report.overview.main.first))
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
    #expect(outline.selectedRow == outline.contributorRowIndexes[1])
    outline.keyDown(with: try contributorKey("\u{F700}", code: 126, window: window))
    #expect(model.report.overview.selection == model.report.overview.visibleRows.first?.id)
    #expect(outline.selectedRow == outline.contributorRowIndexes[0])
    outline.keyDown(with: try contributorKey("\u{F701}", code: 125, window: window))
    #expect(model.report.overview.selection == expected)
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
    #expect(
        outline.selectedRow
            == model.report.overview.visibleRows.firstIndex { $0.id == selected }.map {
                outline.contributorRowIndexes[$0]
            })
    model.report.overview.sort(by: .memory)
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    host.layoutSubtreeIfNeeded()
    #expect(model.report.overview.selection == selected)
    #expect(
        outline.selectedRow
            == model.report.overview.visibleRows.firstIndex { $0.id == selected }.map {
                outline.contributorRowIndexes[$0]
            })
    #expect(model.report.overview.open == open)
    await model.stop()
}

@Test @MainActor func nativeContributorSectionFoldingPreservesTableAndSelection() async throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let host = NSHostingView(rootView: MenuBarView(model: model))
    host.frame = NSRect(x: 0, y: 0, width: 620, height: 560)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = host
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    let table = try #require(contributorOutline(in: host))
    let id = try #require(model.report.overview.main.first)
    model.report.overview.select(id)
    model.report.overview.setDisclosure(expanded: true, for: id)
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    func save(_ name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["MENUBAR_FOLD_PREVIEW_DIRECTORY"] else {
            return
        }
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }
    try save("overall-and-sections")
    let rows = model.report.overview.visibleRows
    let expanded = model.report.overview.open
    #expect(model.handleShortcut("6", row: nil))
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    #expect(table.contributorRowIndexes.count == model.report.overview.visibleRows.count)
    #expect(model.report.overview.selection == id)
    #expect(!model.report.overview.selectionIsVisible)
    #expect(table.selectedRow == -1)
    let collapsedHeader = table.rect(ofRow: 0)
    let panelMask = try #require((table.layer?.mask as? CAShapeLayer)?.path)
    #expect(panelMask.contains(table.convertToLayer(NSPoint(x: table.bounds.midX, y: collapsedHeader.midY))))
    #expect(
        !panelMask.contains(table.convertToLayer(NSPoint(x: table.bounds.midX, y: collapsedHeader.maxY + 2))))
    try save("sessions-folded")
    #expect(model.handleShortcut("6", row: nil))
    await settleContributorTable(in: host, expectedRows: rows.count)
    #expect(contributorOutline(in: host) === table)
    #expect(model.report.overview.visibleRows == rows)
    #expect(model.report.overview.open == expanded)
    #expect(model.handleShortcut("8", row: nil))
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    #expect(contributorOutline(in: host) === table)
    #expect(!model.report.overview.selectionIsVisible)
    try save("table-folded")
    #expect(model.handleShortcut("8", row: nil))
    await settleContributorTable(in: host, expectedRows: rows.count)
    #expect(model.report.overview.selection == id)
    #expect(model.report.overview.visibleRows == rows)
    window.contentView = nil
    await model.stop()
}

@Test @MainActor func nativeSectionDecorationFollowsMovingRows() async throws {
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let host = NSHostingView(rootView: MenuBarView(model: model))
    host.frame = NSRect(x: 0, y: 0, width: 620, height: 720)
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    let table = try #require(contributorOutline(in: host))
    func anchor(in view: NSView) -> MenuBarTableState.Anchor? {
        if let anchor = view as? MenuBarTableState.Anchor { return anchor }
        return view.subviews.lazy.compactMap { anchor(in: $0) }.first
    }
    let bridge = try #require(anchor(in: host)).contentClip
    let heading = try #require(
        (0..<table.numberOfRows).dropFirst().first { row in
            guard let item = table.item(atRow: row) else { return false }
            return table.delegate?.outlineView?(table, isGroupItem: item) == true
        })
    let row = try #require(table.rowView(atRow: heading, makeIfNecessary: true))
    let final = row.frame
    let gap = table.rect(ofRow: heading).minY - table.rect(ofRow: heading - 1).maxY
    try #require(gap > 4)
    // A hidden offscreen window skips AppKit's animation. Supply intermediate native frames
    // to verify the clipping invariant observed in the user's 2026-10-31 recording.
    for offset in [-40.0, -20.0, 0.0, 20.0, 40.0, 0.0] {
        row.setFrameOrigin(NSPoint(x: final.minX, y: final.minY + offset))
        bridge.refresh()
        let mask = try #require((table.layer?.mask as? CAShapeLayer)?.path)
        let x = table.bounds.midX
        #expect(mask.contains(table.convertToLayer(NSPoint(x: x, y: row.frame.minY + 4))))
        #expect(
            !mask.contains(table.convertToLayer(NSPoint(x: x, y: row.frame.minY - gap / 2))),
            "The gap must travel with the following section, not clip its moving heading")
    }
    let rowLayer = try #require(row.layer)
    let animation = CABasicAnimation(keyPath: "position")
    animation.fromValue = NSValue(point: NSPoint(x: rowLayer.position.x, y: rowLayer.position.y - 40))
    animation.toValue = NSValue(point: rowLayer.position)
    animation.duration = 1
    animation.beginTime = 0.0001
    animation.fillMode = .both
    animation.isRemovedOnCompletion = false
    rowLayer.speed = 0
    rowLayer.timeOffset = 0.5
    rowLayer.add(animation, forKey: "synthetic-section-motion")
    CATransaction.flush()
    let presented = try #require(rowLayer.presentation())
    try #require(abs(presented.frame.minY - rowLayer.frame.minY) > 10)
    bridge.refresh()
    let mask = try #require((table.layer?.mask as? CAShapeLayer)?.path)
    let movingTop = presented.frame.minY
    #expect(mask.contains(table.convertToLayer(NSPoint(x: table.bounds.midX, y: movingTop + 4))))
    #expect(!mask.contains(table.convertToLayer(NSPoint(x: table.bounds.midX, y: movingTop - gap / 2))))
    rowLayer.removeAllAnimations()
    rowLayer.speed = 1
    rowLayer.timeOffset = 0
    bridge.refresh()
    await model.stop()
}

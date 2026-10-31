import AgentMonitorPresentation
import AppKit
import SwiftUI
import Testing

@testable import AgentMonitorMenuBar

@Test @MainActor func panelExposesAResizeGripBeforeDetachment() async throws {
    let model = MenuBarModel { _, _, _ in }
    let host = NSHostingView(rootView: MenuBarView(model: model, maximumHeight: 900))
    host.frame.size = host.fittingSize
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    let control = try #require(resizeGrip(in: host))
    #expect(control.frame.height >= 12)
    #expect(!control.mouseDownCanMoveWindow)
    #expect(control.toolTip?.contains("Drag") == true)
    #expect(control.accessibilityPerformIncrement())
    #expect(model.panelHeight > MenuBarPanelSize.standard.height)
    #expect(control.accessibilityPerformDecrement())
    #expect(model.panelHeight == MenuBarPanelSize.standard.height)
    try dragResizeGrip(control, delta: 100)
    #expect(model.panelHeight == 660)
    try dragResizeGrip(control, delta: 2000)
    #expect(model.panelHeight == 900)
    try dragResizeGrip(control, delta: -2000)
    #expect(model.panelHeight == 420)
    model.panelSize = .standard
    #expect(model.customPanelHeight == nil)
}

@MainActor private func resizeGrip(in view: NSView) -> NSView? {
    if view.accessibilityIdentifier() == "panel-height-resize" { return view }
    return view.subviews.lazy.compactMap { resizeGrip(in: $0) }.first
}

@MainActor private func dragResizeGrip(_ control: NSView, delta: CGFloat) throws {
    let window = try #require(control.window)
    let origin = window.convertPoint(
        toScreen: control.convert(NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil))
    func event(_ type: NSEvent.EventType, delta: CGFloat) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: type,
                location: window.convertPoint(fromScreen: NSPoint(x: origin.x, y: origin.y - delta)),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
    }
    control.mouseDown(with: try event(.leftMouseDown, delta: 0))
    control.mouseDragged(with: try event(.leftMouseDragged, delta: delta / 2))
    control.mouseDragged(with: try event(.leftMouseDragged, delta: delta))
    control.mouseUp(with: try event(.leftMouseUp, delta: delta))
}

@Test @MainActor func detachedWindowResizesWithoutReplacingTheTableOrResettingInspection() async throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let host = NSHostingController(rootView: MenuBarView(model: model, maximumHeight: 1000))
    host.sizingOptions = [.intrinsicContentSize]
    host.view.setFrameSize(host.view.fittingSize)
    let window = ResizeRecordingWindow(
        contentRect: host.view.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = host
    let sizing = MenuBarWindowSizing(model: model, host: host, window: window)
    defer {
        sizing.stop()
        window.close()
    }
    #expect(window.styleMask.contains(.resizable))
    await settleContributorTable(in: host.view, expectedRows: model.report.overview.visibleRows.count)
    let original = try #require(contributorOutline(in: host.view))
    let selected = try #require(model.report.overview.selection)
    model.report.overview.toggle(selected)
    model.report.overview.toggleDetails()
    model.toggleFreeze()
    for height: CGFloat in [800, 460, 675] {
        window.setContentSize(NSSize(width: MenuBarLayout.width, height: height))
        await settleContributorTable(in: host.view, expectedRows: model.report.overview.visibleRows.count)
        #expect(abs(host.view.bounds.height - height) < 1)
        #expect(model.panelHeight == height)
        #expect(model.report.overview.selection == selected)
        #expect(model.report.overview.detailsVisible)
        #expect(model.report.overview.isExpanded(selected))
        #expect(model.report.frozen)
        #expect(contributorOutline(in: host.view) === original)
    }
    let top = window.frame.maxY
    let grip = try #require(resizeGrip(in: host.view))
    try dragResizeGrip(grip, delta: 100)
    await settleContributorTable(in: host.view, expectedRows: model.report.overview.visibleRows.count)
    #expect(model.panelHeight == 775)
    #expect(abs(host.view.bounds.height - 775) < 1)
    #expect(abs(window.frame.maxY - top) < 1)
    #expect(model.report.overview.selection == selected)
    #expect(model.report.overview.detailsVisible)
    #expect(model.report.overview.isExpanded(selected))
    #expect(contributorOutline(in: host.view) === original)
    for _ in 0..<2 {
        model.report.overview.toggleTable()
        await settleWindowSize(in: host.view)
        #expect(window.requestedAnimation == !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        #expect(host.view.bounds.height < 300)
        #expect(host.view.bounds.height > 150)
        let summaryHeight = host.view.bounds.height
        model.report.overview.hideNoLongerObserved = true
        await settleWindowSize(in: host.view)
        #expect(host.view.bounds.height > summaryHeight)
        #expect(host.view.bounds.height < 300)
        model.report.overview.hideNoLongerObserved = false
        await settleWindowSize(in: host.view)
        #expect(abs(host.view.bounds.height - summaryHeight) < 1)
        #expect(model.panelHeight == 775)
        #expect(abs(window.frame.maxY - top) < 1)
        #expect(contributorOutline(in: host.view) === original)
        model.report.overview.toggleTable()
        await settleWindowSize(in: host.view)
        #expect(window.requestedAnimation == !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        #expect(abs(host.view.bounds.height - 775) < 1)
        #expect(model.panelHeight == 775)
        #expect(model.report.overview.selection == selected)
        #expect(model.report.overview.isExpanded(selected))
        #expect(contributorOutline(in: host.view) === original)
    }
    model.panelSize = .compact
    host.view.layoutSubtreeIfNeeded()
    #expect(abs(host.view.bounds.height - 420) < 1)
    #expect(model.customPanelHeight == nil)
    sizing.stop()
    #expect(host.sizingOptions == [.intrinsicContentSize])
    await model.stop()
}

@Test @MainActor func attachedSummaryFitsContentAndRestoresCustomHeight() async throws {
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    model.rememberPanelHeight(675)
    let popover = NSPopover()
    var sizing = MenuBarPopoverSizing()
    let controller = NSHostingController(
        rootView: MenuBarView(model: model, maximumHeight: 900) { size in
            sizing.update(popover, size: size, summary: model.isSummaryOnly)
        })
    controller.sizingOptions = [.intrinsicContentSize]
    let host = controller.view
    host.frame.size = host.fittingSize
    popover.contentViewController = controller
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height == 675)
    model.report.overview.toggleTable()
    for _ in 0..<20 {
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        await Task.yield()
    }
    #expect(host.fittingSize.height < 300)
    #expect(host.fittingSize.height > 150)
    #expect(popover.contentSize.height == host.fittingSize.height)
    #expect(popover.animates == !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    if let path = ProcessInfo.processInfo.environment["MENUBAR_COLLAPSED_PREVIEW_PATH"] {
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: path))
    }
    #expect(model.panelHeight == 675)
    model.report.view = .processes
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height == 675)
    model.report.view = .mainContributors
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height < 300)
    model.report.overview.toggleTable()
    await settleWindowSize(in: host)
    #expect(host.fittingSize.height == 675)
    #expect(popover.contentSize.height == 675)
    #expect(popover.animates == !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    await model.stop()
}

@MainActor private func settleWindowSize(in host: NSView) async {
    for _ in 0..<20 {
        host.layoutSubtreeIfNeeded()
        await Task.yield()
    }
}

@MainActor private final class ResizeRecordingWindow: NSWindow {
    var requestedAnimation = false

    override func animator() -> Self {
        requestedAnimation = true
        #expect(NSAnimationContext.current.duration == 0.18)
        return self
    }
}

@Test @MainActor func popoverSummaryResizeRequestsBriefAnimation() {
    let popover = NSPopover()
    var sizing = MenuBarPopoverSizing()
    sizing.update(popover, size: NSSize(width: 620, height: 675), summary: false, reduceMotion: false)
    #expect(!popover.animates)
    for summary in [true, false] {
        let size = NSSize(width: 620, height: summary ? 200 : 675)
        sizing.update(popover, size: size, summary: summary, reduceMotion: false)
        #expect(popover.animates)
        #expect(popover.contentSize == size)
    }
    sizing.update(popover, size: NSSize(width: 620, height: 200), summary: true, reduceMotion: true)
    #expect(!popover.animates)
    sizing.update(popover, size: NSSize(width: 620, height: 230), summary: true, reduceMotion: false)
    #expect(!popover.animates, "Notice changes must not repeatedly animate the window")
}

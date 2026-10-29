import AgentMonitorPresentation
import AppKit
import SwiftUI
import Testing

@testable import AgentMonitorMenuBar

@Test @MainActor func detachedWindowResizesWithoutReplacingTheTableOrResettingInspection() async throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let host = NSHostingController(rootView: MenuBarView(model: model, maximumHeight: 1000))
    host.sizingOptions = [.intrinsicContentSize]
    host.view.setFrameSize(host.view.fittingSize)
    let window = NSWindow(
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
    model.panelSize = .compact
    host.view.layoutSubtreeIfNeeded()
    #expect(abs(host.view.bounds.height - 420) < 1)
    #expect(model.customPanelHeight == nil)
    sizing.stop()
    #expect(host.sizingOptions == [.intrinsicContentSize])
    await model.stop()
}

import AgentMonitorCore
import AgentMonitorPresentation
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import AgentMonitorMenuBar

@Test(.enabled(if: ProcessInfo.processInfo.environment["MENUBAR_PREVIEW_PATH"] != nil))
@MainActor func menuBarNativeLayoutRendersAtPopoverSize() async throws {
    let output = try #require(ProcessInfo.processInfo.environment["MENUBAR_PREVIEW_PATH"])
    let findings = try [
        menuBarFixture(name: "node", project: "sample-graph", provider: "claude"),
        menuBarFixture(
            pids: [42002], name: "swift-frontend", project: "sample-editor",
            sessionID: "22222222-2222-4222-8222-222222222222"),
        menuBarFixture(
            pids: [42003], name: "java", project: "sample-graph", provider: "claude",
            sessionID: "33333333-3333-4333-8333-333333333333"),
    ].flatMap(\.findings)
    let snapshot = MonitoringSnapshot(
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1,
        cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
        sampledProcessCount: 42, unreadableProcessCount: 0, findings: findings)
    let model = MenuBarModel { receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    _ = NSApplication.shared
    let host = NSHostingView(
        rootView: MenuBarView(model: model).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.frame = NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: 560)
    host.layoutSubtreeIfNeeded()
    host.frame.size = host.fittingSize
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: output))
    await model.stop()
}

@Test(arguments: [320.0, 376.0], [false, true])
@MainActor func processSummaryFitsTwoLines(width: Double, showsSession: Bool) throws {
    let snapshot = try menuBarFixture(
        name: "swift-frontend-with-a-long-process-name", project: "a-project-with-a-long-directory-name")
    let process = try #require(snapshot.findings.first)
    let session = try #require(SessionGrouping.groups(snapshot.findings).first)
    _ = NSApplication.shared
    let host = NSHostingView(
        rootView: MenuBarProcessLabel(
            process: process, session: showsSession ? session : nil, cpuText: "184.6%",
            footprintText: "1.4 GB"
        ).frame(width: width))
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height <= 36)
    #expect(abs(host.fittingSize.width - width) < 0.5)
}

@Test @MainActor func sparseNativePanelFitsItsContent() async throws {
    let snapshot = try menuBarFixture()
    let model = MenuBarModel { receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    _ = NSApplication.shared
    let host = NSHostingView(rootView: MenuBarView(model: model))
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 560)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height < 400)
    #expect(host.fittingSize.height > 180)
    await model.stop()
}

@Test @MainActor func nativePanelGrowsForDisclosureAndCapsOverflow() async throws {
    let snapshot = try menuBarFixture(pids: Array(42001...42030))
    let model = MenuBarModel { receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    _ = NSApplication.shared
    let host = NSHostingView(rootView: MenuBarView(model: model, maximumBodyHeight: 300))
    host.frame = NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: 560)
    host.layoutSubtreeIfNeeded()
    let collapsed = host.fittingSize.height
    model.report.toggleDisclosure()
    host.layoutSubtreeIfNeeded()
    let expanded = host.fittingSize.height
    #expect(expanded > collapsed)
    #expect(expanded <= 420)
    model.report.toggleDisclosure()
    host.layoutSubtreeIfNeeded()
    #expect(abs(host.fittingSize.height - collapsed) < 1)
    await model.stop()
}

@Test @MainActor func popoverTracksContentGeometryWithoutAVisibleWindow() async throws {
    let snapshot = try menuBarFixture()
    let model = MenuBarModel { receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    _ = NSApplication.shared
    let popover = NSPopover()
    let host = NSHostingController(
        rootView: MenuBarView(model: model) { size in
            if popover.contentSize != size { popover.contentSize = size }
        })
    host.sizingOptions = [.intrinsicContentSize]
    host.view.setFrameSize(host.view.fittingSize)
    popover.contentViewController = host
    host.view.layoutSubtreeIfNeeded()
    #expect(abs(popover.contentSize.width - MenuBarLayout.width) < 1)
    #expect(popover.contentSize.height > 180)
    #expect(popover.contentSize.height < 400)
    let row = try #require(snapshot.findings.first)
    model.begin(.terminate, row: .process(row.process))
    host.view.layoutSubtreeIfNeeded()
    let fitted = host.view.fittingSize
    host.view.layoutSubtreeIfNeeded()
    #expect(popover.contentSize == fitted)
    await model.stop()
}

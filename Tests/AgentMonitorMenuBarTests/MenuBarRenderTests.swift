import AgentMonitorCore
import AgentMonitorPresentation
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import AgentMonitorMenuBar

@Test(arguments: [false, true])
@MainActor func pinControlHasAnEasyPointerTarget(pinned: Bool) {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: MenuBarPinButton(pinned: pinned) { true })
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize == NSSize(width: 32, height: 32))
}

@Test(arguments: [MenuBarRowDisclosure.process, .group(count: 6), .group(count: 60), .group(count: 600)])
@MainActor func rowAccessoriesHaveAnAlignedLargeTarget(disclosure: MenuBarRowDisclosure) {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: MenuBarRowAccessory(disclosure: disclosure))
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize == NSSize(width: 40, height: 32))
}

@Test @MainActor func groupBadgePreservesLargeCountsWithoutClipping() {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: MenuBarRowAccessory(disclosure: .group(count: 12345)))
    let number = NSHostingView(
        rootView: Text("12345").font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
    )
    host.layoutSubtreeIfNeeded()
    number.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width >= number.fittingSize.width + 8)
    #expect(host.fittingSize.height == 32)
}

@Test(
    .enabled(if: ProcessInfo.processInfo.environment["MENUBAR_PREVIEW_PATH"] != nil),
    arguments: [false, true])
@MainActor func menuBarNativeLayoutRendersAtPopoverSize(dark: Bool) async throws {
    let baseOutput = try #require(ProcessInfo.processInfo.environment["MENUBAR_PREVIEW_PATH"])
    let output =
        dark ? URL(fileURLWithPath: baseOutput).deletingPathExtension().path + "-dark.png" : baseOutput
    let findings = try [
        menuBarFixture(
            pids: [42001, 42004], name: "node", project: "sample-graph", cpu: 63.7, memoryBytes: 320_000_000,
            provider: "claude"),
        menuBarFixture(
            pids: [42002], name: "swift-frontend", project: "sample-editor",
            sessionID: "22222222-2222-4222-8222-222222222222"),
        menuBarFixture(
            pids: [42003], name: "java", project: "sample-server", cpu: 0.2, memoryBytes: 1_900_000_000,
            provider: "claude",
            sessionID: "33333333-3333-4333-8333-333333333333"),
        menuBarFixture(
            pids: [42005], name: "python", project: "sample-analysis", cpu: 46.2, memoryBytes: 610_000_000,
            sessionID: "44444444-4444-4444-8444-444444444444"),
    ].flatMap(\.findings)
    let snapshot = MonitoringSnapshot(
        timestamp: Date(timeIntervalSince1970: 52_496), intervalSeconds: 1,
        cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
        sampledProcessCount: 42, unreadableProcessCount: 0, findings: findings,
        agentLoad: AgentLoadSummary(processes: findings))
    let model = MenuBarModel { _, _, receive in
        for tick in 0..<40 {
            let historyFindings = Array(findings.prefix(1 + tick % findings.count))
            try await receive(
                MonitoringSnapshot(
                    timestamp: snapshot.timestamp.addingTimeInterval(Double(tick - 40) * 15),
                    intervalSeconds: 15, cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
                    sampledProcessCount: 42, unreadableProcessCount: 0, findings: findings,
                    agentLoad: AgentLoadSummary(processes: historyFindings)))
        }
        try await receive(snapshot)
    }
    model.open()
    await model.waitForCollection()
    model.toggleFreeze()
    let group = try #require(model.report.groups.first { $0.processes.count > 1 })
    model.report.select(.group(group.id))
    model.report.togglePin(.group(group.id))
    model.report.toggleDisclosure()
    _ = NSApplication.shared
    let host = NSHostingView(
        rootView: MenuBarView(model: model).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.frame = NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: 560)
    host.layoutSubtreeIfNeeded()
    host.frame.size = host.fittingSize
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2),
            pixelsHigh: Int(host.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.size = host.bounds.size
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: output))
    if !dark, let icons = ProcessInfo.processInfo.environment["MENUBAR_ICON_PREVIEW_PATH"] {
        try renderLoadIcons(to: icons)
    }
    await model.stop()
}

@MainActor private func renderLoadIcons(to path: String) throws {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 92))
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.white.cgColor
    for dark in [false, true] {
        let row = NSView(frame: NSRect(x: 0, y: dark ? 0 : 46, width: 300, height: 46))
        row.wantsLayer = true
        row.layer?.backgroundColor = (dark ? NSColor.black : NSColor.white).cgColor
        row.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.addSubview(row)
        for (index, label) in ["Starting", "0 heavy", "1 heavy", "12 heavy", "99+ heavy"].enumerated() {
            let button = NSButton(frame: NSRect(x: index * 60 + 18, y: 20, width: 24, height: 24))
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.image = MenuBarStatusImage.make(
                level: index == 0 ? nil : index - 1,
                heavyCount: [nil, 0, 1, 12, 100][index])
            button.contentTintColor = dark ? .white : .black
            row.addSubview(button)
            let title = NSTextField(labelWithString: label)
            title.font = .systemFont(ofSize: 10)
            title.textColor = dark ? .white : .black
            title.alignment = .center
            title.frame = NSRect(x: index * 60, y: 3, width: 60, height: 14)
            row.addSubview(title)
        }
    }
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 184, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.size = view.bounds.size
    view.layoutSubtreeIfNeeded()
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
}

@Test @MainActor func nativePanelInheritsChangingSystemAppearance() throws {
    _ = NSApplication.shared
    let model = MenuBarModel { _, _, _ in }
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 560))
    let host = NSHostingView(
        rootView: MenuBarView(model: model).background(Color(nsColor: .windowBackgroundColor)))
    host.frame = container.bounds
    container.addSubview(host)
    #expect(host.appearance == nil)
    for dark in [false, true, false] {
        container.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize == NSSize(width: 420, height: 560))
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let background = try #require(bitmap.colorAt(x: 5, y: 5)?.usingColorSpace(.deviceRGB))
        #expect(dark ? background.redComponent < 0.3 : background.redComponent > 0.8)
    }
}

@Test(arguments: [244.0, 280.0, 320.0, 376.0], [false, true])
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

@Test @MainActor func sparseNativePanelKeepsStandardHeight() async throws {
    let snapshot = try menuBarFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    _ = NSApplication.shared
    let host = NSHostingView(rootView: MenuBarView(model: model))
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 560)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height == 560)
    await model.stop()
}

@Test @MainActor func nativePanelKeepsHeightAcrossDisclosureAndOverflow() async throws {
    let snapshot = try menuBarFixture(pids: Array(42001...42030))
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    _ = NSApplication.shared
    let host = NSHostingView(rootView: MenuBarView(model: model))
    host.frame = NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: 560)
    host.layoutSubtreeIfNeeded()
    let collapsed = host.fittingSize.height
    model.report.toggleDisclosure()
    host.layoutSubtreeIfNeeded()
    let expanded = host.fittingSize.height
    #expect(expanded == collapsed)
    #expect(expanded == 560)
    model.report.toggleDisclosure()
    host.layoutSubtreeIfNeeded()
    #expect(abs(host.fittingSize.height - collapsed) < 1)
    await model.stop()
}

@Test @MainActor func popoverKeepsHeightWhenOpeningActionReview() async throws {
    let snapshot = try menuBarFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
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
    #expect(popover.contentSize.height == 560)
    let row = try #require(snapshot.findings.first)
    model.begin(.terminate, row: .process(row.process))
    host.view.layoutSubtreeIfNeeded()
    let fitted = host.view.fittingSize
    host.view.layoutSubtreeIfNeeded()
    #expect(popover.contentSize == fitted)
    #expect(fitted.height == 560)
    model.panelSize = .tall
    host.view.layoutSubtreeIfNeeded()
    #expect(popover.contentSize.height == 720)
    await model.stop()
}

@Test(arguments: MenuBarPanelSize.allCases)
@MainActor func userChoosesPanelHeightWithAScreenLimit(size: MenuBarPanelSize) async throws {
    let snapshot = try menuBarFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    _ = NSApplication.shared
    let host = NSHostingView(rootView: MenuBarView(model: model, maximumHeight: 600))
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 560)
    host.layoutSubtreeIfNeeded()
    model.panelSize = size
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height == min(size.height, 600))
    model.toggleFreeze()
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height == min(size.height, 600))
    await model.stop()
}

@Test @MainActor func keyboardHelpFitsInsideTheFixedPanelAndSurvivesDismissal() async throws {
    let model = MenuBarModel { _, _, _ in }
    model.showsKeyboardHelp = true
    _ = NSApplication.shared
    let host = NSHostingView(rootView: MenuBarView(model: model))
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 560)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize == NSSize(width: 420, height: 560))
    let help = NSHostingView(rootView: MenuBarKeyboardHelp { model.showsKeyboardHelp = false })
    help.frame.size.width = 388
    help.layoutSubtreeIfNeeded()
    #expect(help.fittingSize.height < 230)
    #expect(help.fittingSize.width <= 388)
    model.close()
    #expect(model.showsKeyboardHelp)
    await model.stop()
}

@Test(arguments: [false, true])
@MainActor func arrivalHighlightAdaptsToSystemAppearance(dark: Bool) throws {
    _ = NSApplication.shared
    var brightness: [CGFloat] = []
    for highlighted in [false, true] {
        let host = NSHostingView(
            rootView:
                Text("New process").padding(12)
                .frame(width: 160, height: 40)
                .background(MenuBarArrivalBackground(highlighted: highlighted))
                .background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.setFrameSize(NSSize(width: 160, height: 40))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let color = try #require(bitmap.colorAt(x: 12, y: 12)?.usingColorSpace(.deviceRGB))
        brightness.append((color.redComponent + color.greenComponent + color.blueComponent) / 3)
        if highlighted, let base = ProcessInfo.processInfo.environment["MENUBAR_PREVIEW_PATH"] {
            let path =
                URL(fileURLWithPath: base).deletingPathExtension().path
                + (dark ? "-arrival-dark.png" : "-arrival.png")
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: path))
        }
    }
    #expect(dark ? brightness[1] > brightness[0] : brightness[1] < brightness[0])
    #expect(abs(brightness[1] - brightness[0]) > 0.08)
}

@Test(arguments: HistoryMetric.allCases, HistoryWindow.allCases)
@MainActor func historyStripFitsOneSlimRow(metric: HistoryMetric, window: HistoryWindow) {
    _ = NSApplication.shared
    let model = MenuBarModel { _, _, _ in }
    model.report.historyMetric = metric
    model.report.historyWindow = window
    let host = NSHostingView(rootView: MenuBarHistoryStrip(model: model).frame(width: 392))
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize == NSSize(width: 392, height: 28))
}

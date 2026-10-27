import AgentMonitorPresentation
import AppKit
import SwiftUI
import Testing

@testable import AgentMonitorMenuBar

@Test(arguments: [ReportReferencePage.glossary, .diagnostics], [false, true])
@MainActor func nativeReferencePagesKeepLongContentInABoundedScrollView(
    page: ReportReferencePage, dark: Bool
) async throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture(unreadable: 5)
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let host = NSHostingView(
        rootView: MenuBarReferenceContent(model: model, page: page, dismiss: {})
            .background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 480),
        styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host
    host.frame.size = NSSize(width: 400, height: 480)
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    host.layoutSubtreeIfNeeded()
    let scroll = try #require(referenceScrollView(in: host))
    let document = try #require(scroll.documentView)
    #expect(scroll.contentSize.width <= 400)
    #expect(scroll.contentSize.height < 480)
    #expect(document.frame.height > scroll.contentSize.height)
    #expect(document.frame.width <= scroll.contentSize.width + 1)
    if let directory = ProcessInfo.processInfo.environment["MENUBAR_REFERENCE_PREVIEW_DIRECTORY"] {
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let name = "\(page == .glossary ? "help" : "diagnostics")-\(dark ? "dark" : "light").png"
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
    await model.stop()
}

@MainActor private func referenceScrollView(in view: NSView) -> NSScrollView? {
    if let scroll = view as? NSScrollView { return scroll }
    return view.subviews.lazy.compactMap { referenceScrollView(in: $0) }.first
}

import AgentMonitorPresentation
import AppKit
import SwiftUI
import Testing

@testable import AgentMonitorMenuBar

@Test(arguments: [MenuBarReferencePage.glossary, .diagnostics, .keyboard], [false, true])
@MainActor func nativeReferencePagesKeepLongContentInABoundedScrollView(
    page: MenuBarReferencePage, dark: Bool
) async throws {
    _ = NSApplication.shared
    if page == .glossary {
        let titles = Set(ReportGlossary.entries.map(\.title))
        for section in [ContributorSection.recent, .remainder, .uncertain, .shared, .released] {
            let explanation = try #require(ContributorID.section(section).groupExplanation)
            #expect(ReportGlossary.entries.contains(explanation))
        }
        #expect(ContributorID.session(provider: "test", session: "test", root: nil).groupExplanation == nil)
        for title in [
            "Other observed work", "Recent contributors", "More processes",
            "Unresolved / uncertain", "Shared agent runtimes", "Older work · detail released",
        ] {
            #expect(titles.contains(title), "Help must explain the visible group: \(title)")
        }
    }
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
    if page != .keyboard { #expect(document.frame.height > scroll.contentSize.height) }
    #expect(document.frame.width <= scroll.contentSize.width + 1)
    if let directory = ProcessInfo.processInfo.environment["MENUBAR_REFERENCE_PREVIEW_DIRECTORY"] {
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let name = "\(page.rawValue)-\(dark ? "dark" : "light").png"
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
    await model.stop()
}

@MainActor private func referenceScrollView(in view: NSView) -> NSScrollView? {
    if let scroll = view as? NSScrollView { return scroll }
    return view.subviews.lazy.compactMap { referenceScrollView(in: $0) }.first
}

@Test @MainActor func keyboardHelpHasItsOwnMenuEntry() throws {
    _ = NSApplication.shared
    let model = MenuBarModel { _, _, _ in }
    let controller = MenuBarOptionsController(model: model)
    let menu = controller.makeMenu()
    for page in [MenuBarReferencePage.glossary, .keyboard, .diagnostics] {
        let item = try #require(menu.item(withTitle: page == .keyboard ? page.title + " (?)" : page.title))
        menu.performActionForItem(at: menu.index(of: item))
        #expect(model.referencePage == page)
    }
    model.close()
    #expect(model.referencePage == nil)
}

@Test @MainActor func contextualGlossaryScrollsToRequestedTopicAndGeneralHelpReturnsToTop() async throws {
    _ = NSApplication.shared
    let model = MenuBarModel { _, _, _ in }
    let topic = ReportGlossary.contributorGroup(.released)
    model.showGlossary(topic)
    #expect(model.referencePage == .glossary)
    #expect(model.glossaryTopic == topic.id)
    let host = NSHostingView(
        rootView: MenuBarReferenceContent(model: model, page: .glossary, dismiss: {})
            .background(Color(nsColor: .windowBackgroundColor)))
    host.frame.size = NSSize(width: 400, height: 480)
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    await Task.yield()
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let scroll = try #require(referenceScrollView(in: host))
    #expect(scroll.contentView.bounds.minY > 0)
    if let directory = ProcessInfo.processInfo.environment["MENUBAR_REFERENCE_PREVIEW_DIRECTORY"] {
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: directory).appendingPathComponent("contextual-glossary.png"))
    }
    model.showGlossary()
    #expect(model.referencePage == .glossary)
    #expect(model.glossaryTopic == nil)
    await Task.yield()
    host.layoutSubtreeIfNeeded()
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let resetScroll = try #require(referenceScrollView(in: host))
    #expect(abs(resetScroll.contentView.bounds.minY) < 1)
    model.referencePage = nil
    #expect(model.glossaryTopic == nil)
}

import AgentMonitorPresentation
import AppKit
import SwiftUI
import Testing

@testable import AgentMonitorMenuBar

@Test @MainActor func inspectionFieldsWrapCompletePathsAndIdentifiersDespiteInheritedRowLimits() async throws
{
    _ = NSApplication.shared
    let fields = [
        InspectionField(
            "Directory",
            "/Users/fixture/Library/Application Support/LongProject/Services/BuildWorkers/Documentation/Checkout/WORKSPACE-END"
        ),
        InspectionField(
            "Executable",
            "/Users/fixture/Library/Application Support/LongProject/Tools/LanguageServers/Versions/Current/EXECUTABLE-END"
        ),
        InspectionField("Exact session", "claude/0aeb8793-41d0-445d-a102-27a87127bd99"),
    ]
    let host = NSHostingView(
        rootView: MenuBarInspectionFields(fields: fields)
            .frame(width: 372).padding(14).lineLimit(1)
            .background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    host.frame.size = host.fittingSize
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    #expect(host.bounds.width == 400)
    #expect(host.bounds.height > 120)
    let bitmap = try detailBitmap(host)
    let recognized = try await nativeRecognizedText(in: #require(bitmap.cgImage))
    let text = recognized.map(\.text).joined(separator: " ")
    #expect(text.contains("WORKSPACE-END"), "\(text)")
    #expect(text.contains("EXECUTABLE-END"), "\(text)")
    #expect(text.contains("27a87127bd99"), "\(text)")
    #expect(!text.contains("…"), "\(text)")
    if let output = ProcessInfo.processInfo.environment["MENUBAR_DETAIL_PREVIEW_DIRECTORY"] {
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: output).appendingPathComponent("full-paths.png"))
    }
}

@Test(arguments: [false, true]) @MainActor
func contributorLedgerKeepsChromeLightAndContentReadableOverBackdrop(dark: Bool) async throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let pinned = try #require(model.report.overview.main.first)
    model.report.overview.togglePin(for: pinned)
    model.report.overview.select(pinned)
    let host = NSHostingView(rootView: ContributorTableBackdrop(model: model))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.frame.size = NSSize(width: 620, height: 300)
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    let bitmap = try detailBitmap(host)
    for point in [NSPoint(x: 610, y: 12), NSPoint(x: 3, y: 100)] {
        let x = Int(point.x * CGFloat(bitmap.pixelsWide) / host.bounds.width)
        let y = Int(point.y * CGFloat(bitmap.pixelsHigh) / host.bounds.height)
        let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        if point.y < 30 {
            #expect(color.blueComponent > 0.8 && color.redComponent < 0.2, "Chrome lost its backdrop")
        } else {
            #expect(
                abs(color.blueComponent - color.redComponent) < 0.15,
                "Reading surface must suppress the saturated backdrop")
            #expect(
                dark
                    ? color.redComponent < 0.4
                    : (0.7...0.86).contains(color.redComponent),
                "Reading surface must stay subdued rather than form a bright white surround: \(color)")
        }
    }
    if let output = ProcessInfo.processInfo.environment["MENUBAR_DETAIL_PREVIEW_DIRECTORY"] {
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: output).appendingPathComponent(
                dark ? "table-backdrop-dark.png" : "table-backdrop-light.png"))
    }
    await model.stop()
}

private struct ContributorTableBackdrop: View {
    let model: MenuBarModel
    @FocusState private var focus: MenuBarFocus?

    var body: some View {
        MenuBarContributorTable(model: model, focus: $focus)
            .background(Color(red: 0, green: 0, blue: 1))
    }
}

@MainActor private func detailBitmap(_ view: NSView) throws -> NSBitmapImageRep {
    view.layoutSubtreeIfNeeded()
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return bitmap
}

@Test @MainActor func compactProcessInspectorKeepsWindowHeaderInsideBounds() async throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture(unreadable: 3)
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    model.panelSize = .compact
    let host = NSHostingView(
        rootView: MenuBarView(model: model).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.frame = NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: 420)
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    let session = try #require(model.report.overview.main.first)
    model.report.overview.setDisclosure(expanded: true, for: session)
    let workload = try #require(model.report.overview.nodes[session]?.children.first)
    model.report.overview.setDisclosure(expanded: true, for: workload)
    let process = try #require(model.report.overview.nodes[workload]?.children.first)
    model.report.overview.select(process)
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    let outline = try #require(contributorOutline(in: host))
    let row = try #require(model.report.overview.visibleRows.firstIndex { $0.id == process })
    outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    outline.scrollRowToVisible(row)
    model.report.overview.toggleDetails()
    await Task.yield()
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    let bitmap = try detailBitmap(host)
    let selectedRect = outline.rect(ofRow: row)
    #expect(outline.visibleRect.intersects(selectedRect))
    #expect(selectedRect.minY >= outline.visibleRect.minY - 1)
    let recognized = try await nativeRecognizedText(in: #require(bitmap.cgImage))
    let heading = try #require(
        recognized.first { $0.text == "Agent Monitor" })
    #expect(heading.bounds.maxY < 0.99)
    #expect(heading.bounds.minY > 0.85)
    if let directory = ProcessInfo.processInfo.environment["MENUBAR_DETAIL_PREVIEW_DIRECTORY"] {
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: directory).appendingPathComponent("compact-process-inspector.png"))
    }
    await model.stop()
}

@Test(arguments: [false, true], [false, true]) @MainActor
func historicalDirectoryTruncatesWithoutPresenceText(dark: Bool, selected: Bool) async throws {
    let path =
        "/Users/fixture/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/very-long-workspace/jsonschema-0.58.6"
    let snapshot = try nativeOverviewFixture(historicalDirectory: path)
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let node = try #require(
        model.report.overview.nodes.values.first {
            if case .executable = $0.id { return $0.stats.isNoLongerObserved }
            return false
        })
    #expect(node.inspectionFields.contains { $0.label == "Directory" && $0.value == path })
    let host = NSHostingView(
        rootView:
            MenuBarContributorRow(node: node, overview: model.report.overview)
            .environment(\.backgroundProminence, selected ? .increased : .standard)
            .padding(12).frame(width: 590, height: 180).background {
                if selected { Color.accentColor } else { MenuBarReadingSurface() }
            })
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.frame.size = host.fittingSize
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    let bitmap = try detailBitmap(host)
    let recognized = try await nativeRecognizedText(in: #require(bitmap.cgImage))
    let text = recognized.map(\.text).joined(separator: " ")
    #expect(text.contains("java"), "\(text)")
    #expect(!text.contains("observed"), "Presence must not form part of a truncated path: \(text)")
    if let directory = ProcessInfo.processInfo.environment["MENUBAR_DETAIL_PREVIEW_DIRECTORY"] {
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: directory).appendingPathComponent(
                "historical-path-\(dark ? "dark" : "light")\(selected ? "-selected" : "").png"))
    }
    await model.stop()
}

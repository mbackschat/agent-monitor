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
func contributorLedgerKeepsNeutralSurfaceAndSeparatesGroups(dark: Bool) async throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    model.report.overview.select(.section(.uncertain))
    let host = NSHostingView(rootView: ContributorTableBackdrop(model: model))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.frame.size = NSSize(width: 620, height: 900)
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
    let outline = try #require(contributorOutline(in: host))
    outline.scroll(.zero)
    host.layoutSubtreeIfNeeded()
    var bitmap = try detailBitmap(host)
    func color(at point: NSPoint) throws -> NSColor {
        let x = Int(point.x * CGFloat(bitmap.pixelsWide) / host.bounds.width)
        let y = Int(point.y * CGFloat(bitmap.pixelsHigh) / host.bounds.height)
        return try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
    }
    func difference(_ left: NSColor, _ right: NSColor) -> CGFloat {
        max(
            abs(left.redComponent - right.redComponent),
            abs(left.greenComponent - right.greenComponent),
            abs(left.blueComponent - right.blueComponent))
    }
    let surround = try color(at: NSPoint(x: 3, y: 100))
    #expect(
        abs(surround.blueComponent - surround.redComponent) < 0.15,
        "The reading surface must suppress desktop colors")
    #expect(
        dark ? surround.redComponent < 0.2 : surround.redComponent > 0.9,
        "Restore the original system reading surface without gray tint: \(surround)")
    let roots = model.report.overview.visibleRows.enumerated().filter { $0.element.depth == 0 }
    try #require(roots.count >= 2)
    let bands = try roots.prefix(2).map { row in
        let rect = outline.rect(ofRow: outline.contributorRowIndexes[row.offset])
        return try color(at: host.convert(NSPoint(x: rect.midX, y: rect.maxY - 5), from: outline))
    }
    #expect(
        difference(bands[0], bands[1]) >= 0.05 - 1.0 / 255,
        "Adjacent session bands must differ visibly, not by a nearly invisible tint: \(bands)")
    func checkEmptyViewport() throws {
        let last = outline.rect(ofRow: outline.numberOfRows - 1)
        try #require(outline.visibleRect.maxY - last.maxY > 72)
        for y in stride(from: last.maxY + 12, to: outline.visibleRect.maxY - 8, by: 12) {
            let empty = try color(at: host.convert(NSPoint(x: outline.bounds.midX, y: y), from: outline))
            #expect(
                difference(empty, surround) < 0.02,
                "Empty viewport must show the surround without native filler stripes at y=\(y): \(empty)")
        }
    }
    try checkEmptyViewport()
    for expanded in [true, false] {
        model.report.overview.setDisclosure(expanded: expanded, for: roots[0].element.id)
        window.setContentSize(NSSize(width: 620, height: expanded ? 1000 : 760))
        await settleContributorTable(in: host, expectedRows: model.report.overview.visibleRows.count)
        #expect(contributorOutline(in: host) === outline)
        bitmap = try detailBitmap(host)
        try checkEmptyViewport()
    }
    if let output = ProcessInfo.processInfo.environment["MENUBAR_DETAIL_PREVIEW_DIRECTORY"] {
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: output).appendingPathComponent(
                "table-backdrop-\(dark ? "dark" : "light").png"))
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
    let index = try #require(model.report.overview.visibleRows.firstIndex { $0.id == process })
    let row = outline.contributorRowIndexes[index]
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
    let status = try #require(recognized.first { $0.text == "Live updates" })
    #expect(abs(status.bounds.midY - heading.bounds.midY) < 0.015)
    #expect(status.bounds.minX > heading.bounds.maxX)
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
    #expect(MenuBarContributorPresence(stats: node.stats) == nil)
    #expect(MenuBarContributorCounts.countText(99) == "99")
    #expect(MenuBarContributorCounts.countText(100) == "99+")
    #expect(MenuBarContributorCounts.countText(133) == "99+")
    var mixed = node.stats
    mixed.current = Set(model.report.overview.totals.current.prefix(1))
    mixed.processes.formUnion(mixed.current)
    #expect(MenuBarContributorPresence(stats: mixed) == nil)
    #expect(MenuBarContributorCounts(stats: mixed).pastCount == node.stats.processes.count)
    mixed.membershipChanged = node.stats.processes
    #expect(MenuBarContributorCounts(stats: mixed).pastCount == 0)
    mixed.currentAvailable = false
    #expect(MenuBarContributorCounts(stats: mixed).help.contains("unavailable"))
    var manyPast = node.stats
    manyPast.current = []
    manyPast.membershipChanged = []
    manyPast.processes = Set((1...133).map { .init(pid: Int32($0), startMicroseconds: 1) })
    #expect(MenuBarContributorCounts(stats: manyPast).help.contains("133 no longer observed"))
    let countVariants =
        [(7, 13), (99, 133), (0, 18), (7, 0), (0, 0)].map { current, past in
            var stats = node.stats
            stats.current = Set((0..<current).map { .init(pid: Int32($0), startMicroseconds: 1) })
            stats.processes = Set((0..<(current + past)).map { .init(pid: Int32($0), startMicroseconds: 1) })
            return stats
        } + [mixed]
    let countSizes = countVariants.map { stats in
        NSHostingView(rootView: MenuBarContributorCounts(stats: stats).font(.system(size: 12))).fittingSize
    }
    #expect(
        countSizes.allSatisfy { $0 == countSizes[0] },
        "Counts must not move as populations change: \(countSizes)")
    #expect(countSizes.allSatisfy { $0.width <= 40 && $0.height <= 32 })
    if let directory = ProcessInfo.processInfo.environment["MENUBAR_DETAIL_PREVIEW_DIRECTORY"] {
        let countsHost = NSHostingView(
            rootView: HStack(spacing: 12) {
                ForEach(countVariants.indices, id: \.self) { index in
                    MenuBarContributorCounts(stats: countVariants[index])
                        .font(.system(size: 12, weight: .semibold))
                        .padding(6).background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }
            }.padding(12).background(Color(nsColor: .windowBackgroundColor)))
        countsHost.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        countsHost.frame.size = countsHost.fittingSize
        let countsWindow = await mountOffscreenNativePreview(countsHost)
        defer { countsWindow.close() }
        try #require(detailBitmap(countsHost).representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: directory).appendingPathComponent(
                "stacked-counts-\(dark ? "dark" : "light").png"))
    }
    let host = NSHostingView(
        rootView:
            MenuBarContributorRow(node: node, overview: model.report.overview)
            .environment(\.backgroundProminence, selected ? .increased : .standard)
            .padding(12).frame(width: 590, height: 180).background {
                if selected { Color.accentColor } else { MenuBarReadingSurface() }
            }.background(Color(nsColor: .windowBackgroundColor)))
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

import AgentMonitorPresentation
import AppKit
import SwiftUI
import Testing
import Vision

@testable import AgentMonitorMenuBar

@Test @MainActor func simultaneousCoverageWarningsRemainVisibleWithoutDisclosure() throws {
    _ = NSApplication.shared
    let status = CoverageStatus(notes: [
        .init("Collapsed detail · 5–60 s before window end", .warning, help: "Frozen CPU is retained."),
        .init("Read failures: 12 same-user PIDs", .warning, help: "Readings are missing."),
        .init("40 overruns · max gap 1182 ms", .warning, help: "Short workers can be missed."),
        .init("7 memory unavailable", .warning, help: "Memory is a lower bound."),
        .init("3 excluded", .warning, help: "Counters were unavailable."),
    ])
    let host = NSHostingView(
        rootView: MenuBarCoverageStatus(status: status)
            .padding(8).frame(width: 400).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    host.frame.size = host.fittingSize
    #expect(host.fittingSize.height <= 150)
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2),
            pixelsHigh: Int(host.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.size = host.bounds.size
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: #require(bitmap.cgImage)).perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    for pattern in [
        #"Collapsed deta[il]l\s*[·.•]?\s*5[–-]60 s before"#,
        #"Read fa[il]lures:\s*12 same-user PIDs"#,
        #"40 overruns\s*[·.•]?\s*max gap 1182 ms"#,
        #"7 memory unava[il]lable"#, #"3 excluded"#,
    ] {
        // Vision can confuse caption2's i/l glyphs; numeric values and their labels stay exact.
        #expect(text.range(of: pattern, options: .regularExpression) != nil, "Missing \(pattern): \(text)")
    }
    if let path = ProcessInfo.processInfo.environment["MENUBAR_STATUS_PREVIEW_PATH"] {
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: path))
    }
}

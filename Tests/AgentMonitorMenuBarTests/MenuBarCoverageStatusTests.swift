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
    for expected in ["Collapsed", "12", "40", "1182", "excluded"] {
        #expect(text.contains(expected), "Missing \(expected) in rendered coverage: \(text)")
    }
    // Vision reads caption2's "il" as "ll" in the 2026-10-26 offscreen render.
    #expect(text.range(of: "memory unava[il]lable", options: .regularExpression) != nil, "\(text)")
    if let path = ProcessInfo.processInfo.environment["MENUBAR_STATUS_PREVIEW_PATH"] {
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: path))
    }
}

import AgentMonitorPresentation
import AppKit
import Foundation
import SwiftUI
import Testing
import Vision

@testable import AgentMonitorCore
@testable import AgentMonitorMenuBar

@Test(arguments: [false, true])
@MainActor func compactNativeSessionLabelsKeepMatchingNamesAndDistinctIdentitiesVisible(dark: Bool) throws {
    _ = NSApplication.shared
    let overview = try namedSessionOverview()
    for (index, id) in overview.main.enumerated() {
        let node = try #require(overview.nodes[id])
        let host = NSHostingView(
            rootView: MenuBarContributorSummary(node: node, overview: overview, expanded: false)
                .frame(width: 376)
                .background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.layoutSubtreeIfNeeded()
        host.frame.size = host.fittingSize
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2),
                pixelsHigh: Int(host.bounds.height * 2), bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: #require(bitmap.cgImage)).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ").lowercased()
        #expect(text.contains(index == 0 ? "abcdabcd" : "12345678"), "\(text)")
        #expect(text.contains("claude"), "\(text)")
        #expect(text.contains("build indexing"), "\(text)")
        #expect(text.contains(index == 0 ? "work" : "tmp"), "\(text)")
        #expect(text.contains("alpha/project"), "\(text)")
        #expect(host.bounds.height <= 44)
        if let output = ProcessInfo.processInfo.environment["MENUBAR_SESSION_LABEL_PREVIEW_PATH"] {
            let base = URL(fileURLWithPath: output).deletingPathExtension().path
            let path = base + (dark ? "-dark" : "") + "-\(index + 1).png"
            try #require(bitmap.representation(using: .png, properties: [:])).write(
                to: URL(fileURLWithPath: path))
        }
    }
}

@Test(arguments: [false, true])
@MainActor func nativeProcessSessionHeadingsKeepLongNamesAndDistinctIdentitiesVisible(dark: Bool) async throws
{
    _ = NSApplication.shared
    let snapshot = try namedSessionSnapshot(workersPerSession: 2, directories: ["/work/backend", "/tmp/web"])
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    model.report.overview.enabled = false
    #expect(model.report.groups.count == 2)
    let host = NSHostingView(
        rootView: MenuBarView(model: model).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 560)
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 840, pixelsHigh: 1120, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.size = host.bounds.size
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: #require(bitmap.cgImage)).perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: " ").lowercased()
    #expect(text.contains("abcdabcd"), "\(text)")
    #expect(text.contains("12345678"), "\(text)")
    #expect(text.contains("build indexing"), "\(text)")
    #expect(text.contains("work/backend"), "\(text)")
    #expect(text.contains("tmp/web"), "\(text)")
    if let output = ProcessInfo.processInfo.environment["MENUBAR_PROCESS_SESSION_LABEL_PREVIEW_PATH"] {
        let path = dark ? URL(fileURLWithPath: output).deletingPathExtension().path + "-dark.png" : output
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: path))
    }
    await model.stop()
}

@Test @MainActor func nativeGroupedProcessRowsKeepTheirOwnDirectoriesVisible() async throws {
    _ = NSApplication.shared
    let snapshot = try namedSessionSnapshot(
        workersPerSession: 2, directories: ["/work/api", "/tmp/web"], directoriesByWorker: true)
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    model.report.overview.enabled = false
    for group in model.report.groups {
        model.report.select(.group(group.id))
        model.report.setDisclosure(expanded: true)
    }
    let host = NSHostingView(
        rootView: MenuBarView(model: model).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 700)
    host.layoutSubtreeIfNeeded()
    let text = try processDirectoryRenderText(
        host, output: ProcessInfo.processInfo.environment["MENUBAR_PROCESS_DIRECTORY_PREVIEW_PATH"])
    #expect(text.contains("work/api"), "\(text)")
    #expect(text.contains("tmp/web"), "\(text)")
    #expect(text.contains("java"), "\(text)")
    await model.stop()
}

@Test(arguments: [0, 1])
@MainActor func nativeLongProcessRowsKeepTheirOwnDirectoryAndValues(index: Int) throws {
    _ = NSApplication.shared
    let snapshot = try namedSessionSnapshot()
    let original = snapshot.findings[index]
    let process = HeavyProcess(
        process: ProcessIdentity(pid: Int32(42001 + index), startMicroseconds: 1),
        executable: "/bin/rust-analyzer-proc-macro-srv", name: "rust-analyzer-proc-macro-srv",
        cpuPercent: original.cpuPercent, footprintBytes: original.footprintBytes, cwd: original.cwd,
        command: nil, metadataStatus: original.metadataStatus, attribution: original.attribution)
    let host = NSHostingView(
        rootView: MenuBarProcessLabel(
            process: process, session: nil,
            directory: ProcessDirectoryLabels(snapshot.findings).label(for: process),
            cpuText: index == 0 ? "75%" : "25%", footprintText: index == 0 ? "20 MB" : "40 MB"
        ).frame(width: 280).padding(8).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    host.frame.size = host.fittingSize
    let output = ProcessInfo.processInfo.environment["MENUBAR_PROCESS_DIRECTORY_PREVIEW_PATH"]
        .map { URL(fileURLWithPath: $0).deletingPathExtension().path + "-row-\(index).png" }
    let text = try processDirectoryRenderText(host, output: output)
    #expect(text.contains("rust"), "\(text)")
    #expect(text.contains(index == 0 ? "work" : "tmp"), "\(text)")
    #expect(!text.contains(index == 0 ? "tmp" : "work"), "\(text)")
    #expect(text.contains(index == 0 ? "75%" : "25%"), "\(text)")
    #expect(text.replacingOccurrences(of: " ", with: "").contains(index == 0 ? "20mb" : "40mb"), "\(text)")
    #expect(host.fittingSize.height <= 36)
}

@MainActor private func processDirectoryRenderText(_ host: NSView, output: String?) throws -> String {
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2),
            pixelsHigh: Int(host.bounds.height * 2), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.size = host.bounds.size
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: #require(bitmap.cgImage)).perform([request])
    if let output {
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: output))
    }
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: " ").lowercased()
}

private func namedSessionOverview() throws -> ContributorOverview {
    var overview = ContributorOverview()
    overview.receive(try namedSessionSnapshot())
    return overview
}

private func namedSessionSnapshot(
    workersPerSession: Int = 1, directories: [String] = ["/work/alpha/project", "/tmp/alpha/project"],
    directoriesByWorker: Bool = false
) throws -> MonitoringSnapshot {
    let sessions = [
        "abcdabcd-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "12345678-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    ]
    func samples(_ time: Double) -> [ProcessSample] {
        sessions.indices.flatMap { index in
            (0..<workersPerSession).map { worker in
                ProcessSample(
                    identity: ProcessIdentity(
                        pid: Int32(index * workersPerSession + worker + 1), startMicroseconds: 1),
                    parentPID: 0, executable: "/bin/java", name: "java", sampledAt: time,
                    cpuSeconds: time * (index == 0 ? 0.9 : 0.8) / Double(workersPerSession),
                    footprintBytes: 320_000_000)
            }
        }
    }
    var ledger = CounterLedger()
    let baseline = ledger.ingest(samples(0), listedAt: 0)
    let values = samples(1)
    let rows = values.enumerated().map { index, value in
        let session = index / workersPerSession
        return HeavyProcess(
            process: value.identity, executable: value.executable, name: value.name,
            cpuPercent: (session == 0 ? 90 : 80) / Double(workersPerSession),
            footprintBytes: value.footprintBytes,
            cwd: directories[directoriesByWorker ? index % workersPerSession : session], command: nil,
            metadataStatus: .markerRead,
            attribution: Attribution(
                provider: .claude, evidence: .marker, context: .unverified,
                threadID: sessions[session], rootSessionID: nil, runtime: nil, terminal: nil,
                runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []),
            sessionName: "Build indexing and attribution for the shared application workspace")
    }
    var window = AccountingWindow(baseline: baseline)
    try window.append(ledger.ingest(values, listedAt: 1), rows: rows)
    let store = RecentActivityStore()
    store.append(window.seal(scope: .agentsOnly), current: window.current, present: window.present)
    return MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 170,
            unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
        timestamp: Date(), intervalSeconds: 0.1, cpuThresholdPercent: 0, memoryThresholdBytes: 0,
        sampledProcessCount: rows.count, unreadableProcessCount: 0, findings: rows,
        recentActivity: store.snapshot())
}

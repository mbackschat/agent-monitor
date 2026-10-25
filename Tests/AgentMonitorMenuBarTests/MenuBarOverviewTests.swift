import AgentMonitorPresentation
import AppKit
import Foundation
import SwiftUI
import Testing
import Vision

@testable import AgentMonitorCore
@testable import AgentMonitorMenuBar

@Test(
    .enabled(if: ProcessInfo.processInfo.environment["MENUBAR_OVERVIEW_PREVIEW_PATH"] != nil),
    arguments: [false, true])
@MainActor func nativeContributorOverviewRenders(dark: Bool) async throws {
    let output = try #require(ProcessInfo.processInfo.environment["MENUBAR_OVERVIEW_PREVIEW_PATH"])
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.report.overview = ContributorOverview(memoryCapacityBytes: 16_000_000_000)
    model.open()
    await model.waitForCollection()
    var terminal = LiveReportState()
    terminal.receive(snapshot)
    #expect(model.report.overview.totals == terminal.overview.totals)
    #expect(model.report.overview.main == terminal.overview.main)
    #expect(model.report.overview.nodes == terminal.overview.nodes)
    #expect(model.report.showsOverview)
    #expect(model.report.overview.main.count == 2)
    #expect(model.report.overview.nodes[.section(.recent)]?.stats.noLongerObserved.count == 1)
    _ = NSApplication.shared
    let host = NSHostingView(
        rootView: MenuBarView(model: model).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.frame = NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: 560)
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.size = host.bounds.size
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let path = dark ? URL(fileURLWithPath: output).deletingPathExtension().path + "-dark.png" : output
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    #expect(host.bounds.height == 560)
    await model.stop()
}

@Test @MainActor func contributorSummaryFitsOneCompactRow() throws {
    var overview = ContributorOverview()
    overview.receive(try nativeOverviewFixture())
    _ = NSApplication.shared
    for row in overview.visibleRows {
        let host = NSHostingView(
            rootView:
                MenuBarContributorSummary(node: row.node, overview: overview, expanded: false)
                .frame(width: 376))
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height <= 22)
        #expect(host.fittingSize.width == 376)
    }
}

@Test @MainActor func samplingExplanationUsesCompactProgressiveDisclosure() throws {
    _ = NSApplication.shared
    let host = NSHostingView(
        rootView: MenuBarSamplingCoverage(snapshot: try nativeOverviewFixture()).frame(width: 376))
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height <= 22)
}

func nativeOverviewFixture(unreadable: Int = 0) throws -> MonitoringSnapshot {
    var ledger = CounterLedger()
    func values(_ tick: Int) -> [ProcessSample] {
        var result: [ProcessSample] = []
        for index in 1...24 where tick < 2 || index != 3 {
            let bytes: UInt64 = index == 1 ? 320_000_000 : (index == 2 ? 2_100_000_000 : 1_000_000)
            let cpu: Double = index == 1 ? Double(tick) * 0.637 : (index == 3 ? 1.2 * Double(tick) : 0)
            result.append(
                ProcessSample(
                    identity: ProcessIdentity(pid: Int32(42000 + index), startMicroseconds: UInt64(index)),
                    parentPID: 0, executable: index == 3 ? "/usr/bin/java" : "/usr/local/bin/node",
                    name: index == 3 ? "java" : "node",
                    sampledAt: Double(tick), cpuSeconds: cpu, footprintBytes: bytes))
        }
        return result
    }
    func rows(_ values: [ProcessSample]) -> [HeavyProcess] {
        values.map { sample in
            let index = Int(sample.identity.pid) - 42000
            return HeavyProcess(
                process: sample.identity, executable: sample.executable, name: sample.name,
                cpuPercent: index == 1 ? 63.7 : 0, footprintBytes: sample.footprintBytes,
                cwd: index == 1
                    ? "/demo/sample-graph" : (index == 2 ? "/demo/agent-monitor" : "/demo/worker-burst"),
                command: nil, metadataStatus: .markerRead,
                attribution: Attribution(
                    provider: .codex,
                    evidence: index == 4 ? .runtimeOnly : .marker, context: .unverified,
                    threadID: index == 4 ? nil : "session-\(index)", rootSessionID: nil, runtime: nil,
                    terminal: nil, runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []))
        }
    }
    let store = RecentActivityStore()
    var baseline = ledger.ingest(values(0), listedAt: 0)
    var window = AccountingWindow(baseline: baseline)
    for tick in 1...2 {
        let samples = values(tick)
        let scan = ledger.ingest(samples, listedAt: Double(tick))
        let findings = rows(samples)
        var activity = AccountingWindow(baseline: baseline)
        try activity.append(scan, rows: findings)
        store.append(activity.seal(scope: .agentsOnly), current: activity.current, present: activity.present)
        window = AccountingWindow(baseline: baseline)
        try window.append(scan, rows: findings)
        baseline = scan
    }
    let projection = try window.projection(scope: .agentsOnly)
    return MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: 110, logicalCPUCount: 8,
            measuredUserPercent: 90, unmeasuredLifetimeCount: 0, previousScanSeconds: 0.01),
        timestamp: Date(timeIntervalSince1970: 52_496), intervalSeconds: 0.1,
        cpuThresholdPercent: 0, memoryThresholdBytes: 0, sampledProcessCount: 23,
        unreadableProcessCount: unreadable,
        findings: projection.rows, agentLoad: AgentLoadSummary(processes: projection.rows),
        window: projection.summary, recentActivity: store.snapshot())
}

@Test @MainActor func processReadGapsAreVisibleWithoutOpeningCoverage() async throws {
    let snapshot = try nativeOverviewFixture(unreadable: 3)
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    model.report.overview.enabled = false
    _ = NSApplication.shared
    let host = NSHostingView(
        rootView: MenuBarView(model: model).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 560)
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 840, pixelsHigh: 1120,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.size = host.bounds.size
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: #require(bitmap.cgImage)).perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: " ")
    #expect(text.contains("Read gaps:"))
    #expect(text.contains("3 same-user"))
    await model.stop()
}

@Test @MainActor func samplingCoverageRendersMetricsWithoutDiagnosticParagraphs() throws {
    _ = NSApplication.shared
    let snapshot = try nativeOverviewFixture(unreadable: 9)
    var reads = ReadCoverage()
    reads.append(
        ProcessSnapshot(
            samples: [], enumeratedCount: 28, unreadableCount: 28,
            listedAt: 1, scanSeconds: 0, hostCounters: nil, logicalCPUCount: 8,
            nativeOutcomes: (1...28).map { pid in
                NativeCounterOutcome(
                    pid: Int32(pid), identity: nil, operation: .bsdInfo,
                    status: pid <= 23 ? .lookupUnavailable : .otherFailure, failure: nil, observedAtTicks: 1)
            }))
    let summary = SamplingCoverageSummary(snapshot: snapshot, reads: reads, recentDuration: 47.5)
    let host = NSHostingView(
        rootView: MenuBarCoverageSummary(summary: summary)
            .padding(12).frame(width: 400).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height <= 200)
    host.frame.size = host.fittingSize
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2),
            pixelsHigh: Int(host.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.size = host.bounds.size
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: #require(bitmap.cgImage)).perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    #expect(text.contains("Observed"))
    // Vision reads this caption2 "il" as "ll" (2026-10-25 render), so accept either glyph pair.
    #expect(text.range(of: "Read fa(il|ll)ures", options: .regularExpression) != nil, "\(text)")
    #expect(text.contains("Sampled"))
    #expect(text.contains("Recent history"))
    #expect(text.contains("Exited before read"))
    #expect(text.contains("Other"))
    #expect(!text.contains("Totals are independent"))
    #expect(!text.contains("Session CPU is"))
    if let path = ProcessInfo.processInfo.environment["MENUBAR_COVERAGE_PREVIEW_PATH"] {
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: path))
    }
}

@Test @MainActor func commandInspectionRendersArgumentBoundariesInABoundedPane() async throws {
    _ = NSApplication.shared
    let process = try #require(try nativeOverviewFixture().findings.first)
    let controller = CommandInspectionController { _ in ["java", "-Xmx2g", "two words"] }
    #expect(controller.start(process))
    await controller.wait()
    let host = NSHostingView(
        rootView: MenuBarCommandInspection(process: process, controller: controller)
            .padding(12).frame(width: 400).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height <= 220)
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
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    #expect(text.contains("read on demand"), "\(text)")
    #expect(text.contains("java"), "\(text)")
    #expect(text.contains("two words"), "\(text)")
    #expect(text.contains("Hide"), "\(text)")
}

@Test @MainActor func contributorInfoIsSeparateFromFoldingAndGuardsHiddenArrowSelection() async throws {
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let id = try #require(model.report.overview.selection)
    model.report.overview.toggle(id)
    #expect(!model.report.overview.detailsVisible)
    #expect(model.handleShortcut("i", row: nil))
    #expect(model.report.overview.detailsVisible)
    #expect(!model.handleOverviewArrow(.downArrow, focus: .contributor(id)))
    #expect(model.report.overview.selection == id)
    #expect(model.handleShortcut("i", row: nil))
    #expect(!model.report.overview.detailsVisible)
    model.close()
    #expect(!model.handleShortcut("i", row: nil))
    await model.stop()
}

@Test @MainActor func contributorInspectionRendersLabelledValuesInsteadOfParagraphs() throws {
    _ = NSApplication.shared
    var overview = ContributorOverview()
    overview.receive(try nativeOverviewFixture())
    let node = try #require(overview.nodes.values.first { $0.process != nil })
    let host = NSHostingView(
        rootView:
            MenuBarContributorInspection(
                node: node, duration: overview.duration, canInspect: false, inspect: {}
            )
            .background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height <= 500)
    host.frame.size = host.fittingSize
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2),
            pixelsHigh: Int(host.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.size = host.bounds.size
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: #require(bitmap.cgImage)).perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    #expect(text.contains("Agent"), "\(text)")
    #expect(text.contains("Session"), "\(text)")
    #expect(text.contains("Directory"), "\(text)")
    #expect(text.contains("Counts and evidence"), "\(text)")
    #expect(!text.contains("Membership changes"), "\(text)")
    #expect(text.contains("Executable"), "\(text)")
    #expect(text.contains("Recent CPU"), "\(text)")
    #expect(!text.contains("Totals are independent"))
    if let path = ProcessInfo.processInfo.environment["MENUBAR_INSPECTION_PREVIEW_PATH"] {
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: path))
    }
}

@Test @MainActor func processLabelShowsEmbeddedInvocationInsteadOfVersionName() throws {
    _ = NSApplication.shared
    let original = try #require(try nativeOverviewFixture().findings.first)
    let process = HeavyProcess(
        process: original.process, executable: "/fixture/claude/versions/2.1.299",
        name: "2.1.299", cpuPercent: 75, footprintBytes: original.footprintBytes, cwd: original.cwd,
        command: nil, metadataStatus: original.metadataStatus, attribution: original.attribution,
        invocationName: "ugrep")
    let host = NSHostingView(
        rootView: MenuBarProcessLabel(
            process: process, session: nil,
            cpuText: "75%", footprintText: "20 MB"
        ).padding(8).frame(width: 400)
            .background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    host.frame.size = host.fittingSize
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: #require(bitmap.cgImage)).perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    #expect(text.contains("ugrep"), "\(text)")
    #expect(!text.contains("2.1.299"), "\(text)")
}

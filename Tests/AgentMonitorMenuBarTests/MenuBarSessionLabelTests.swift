import AgentMonitorPresentation
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import AgentMonitorCore
@testable import AgentMonitorMenuBar

@Test(arguments: [false, true])
@MainActor func compactNativeSessionLabelsKeepDistinctIdentitiesVisible(dark: Bool)
    async throws
{
    _ = NSApplication.shared
    let overview = try sessionLabelOverview()
    for (index, id) in overview.main.enumerated() {
        let node = try #require(overview.nodes[id])
        let host = NSHostingView(
            rootView: MenuBarContributorRow(node: node, overview: overview)
                .frame(width: 580)
                .background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.layoutSubtreeIfNeeded()
        host.frame.size = host.fittingSize
        let window = await mountOffscreenNativePreview(host)
        defer { window.close() }
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2),
                pixelsHigh: Int(host.bounds.height * 2), bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let recognized = try await nativeRecognizedText(in: #require(bitmap.cgImage))
        let text = recognized.map(\.text)
            .joined(separator: " ").lowercased()
        #expect(text.contains(index == 0 ? "abcdabcd" : "12345678"), "\(text)")
        #expect(text.contains("claude"), "\(text)")
        #expect(text.contains(index == 0 ? "work" : "tmp"), "\(text)")
        #expect(text.contains("alpha/project"), "\(text)")
        #expect(host.bounds.height <= 90)
        if let output = ProcessInfo.processInfo.environment["MENUBAR_SESSION_LABEL_PREVIEW_PATH"] {
            let base = URL(fileURLWithPath: output).deletingPathExtension().path
            let path = base + (dark ? "-dark" : "") + "-\(index + 1).png"
            try #require(bitmap.representation(using: .png, properties: [:])).write(
                to: URL(fileURLWithPath: path))
        }
    }
}

@Test(arguments: [false, true])
@MainActor func nativeProcessSessionHeadingsKeepDistinctIdentitiesVisible(dark: Bool) async throws {
    _ = NSApplication.shared
    let snapshot = try sessionLabelSnapshot(workersPerSession: 2, directories: ["/work/backend", "/tmp/web"])
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    model.report.overview.enabled = false
    #expect(model.report.groups.count == 2)
    let host = NSHostingView(
        rootView: MenuBarView(model: model).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.frame = NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: 560)
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 840, pixelsHigh: 1120, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.size = host.bounds.size
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let recognized = try await nativeRecognizedText(in: #require(bitmap.cgImage))
    let text = recognized.map(\.text)
        .joined(separator: " ").lowercased()
    #expect(text.contains("abcdabcd"), "\(text)")
    #expect(text.contains("12345678"), "\(text)")
    #expect(text.contains("backend"), "\(text)")
    #expect(text.contains("web"), "\(text)")
    if let output = ProcessInfo.processInfo.environment["MENUBAR_PROCESS_SESSION_LABEL_PREVIEW_PATH"] {
        let path = dark ? URL(fileURLWithPath: output).deletingPathExtension().path + "-dark.png" : output
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: path))
    }
    await model.stop()
}

@Test @MainActor func nativeGroupedProcessRowsKeepTheirOwnDirectoriesVisible() async throws {
    _ = NSApplication.shared
    let snapshot = try sessionLabelSnapshot(
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
    host.frame = NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: 700)
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    let text = try await processDirectoryRenderText(
        host, output: ProcessInfo.processInfo.environment["MENUBAR_PROCESS_DIRECTORY_PREVIEW_PATH"])
    #expect(text.contains("work/api"), "\(text)")
    #expect(text.contains("tmp/web"), "\(text)")
    #expect(text.contains("java"), "\(text)")
    await model.stop()
}

@Test(arguments: [0, 1])
@MainActor func nativeLongProcessRowsKeepTheirOwnDirectoryAndValues(index: Int) async throws {
    _ = NSApplication.shared
    let snapshot = try sessionLabelSnapshot()
    let original = snapshot.findings[index]
    let process = HeavyProcess(
        process: ProcessIdentity(pid: Int32(42001 + index), startMicroseconds: 1),
        executable: "/bin/rust-analyzer-proc-macro-srv", name: "rust-analyzer-proc-macro-srv",
        cpuPercent: original.cpuPercent, footprintBytes: original.footprintBytes, cwd: original.cwd,
        command: nil, metadataStatus: original.metadataStatus, attribution: original.attribution)
    let host = NSHostingView(
        rootView: MenuBarProcessLabel(
            process: process,
            placement: .sessionChild(.session(provider: "claude", id: process.attribution.threadID ?? "")),
            directory: ProcessDirectoryLabels(snapshot.findings).label(for: process),
            cpuText: index == 0 ? "75%" : "25%", footprintText: index == 0 ? "20 MB" : "40 MB"
        ).frame(width: 280).padding(8).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    host.frame.size = host.fittingSize
    let output = ProcessInfo.processInfo.environment["MENUBAR_PROCESS_DIRECTORY_PREVIEW_PATH"]
        .map { URL(fileURLWithPath: $0).deletingPathExtension().path + "-row-\(index).png" }
    let text = try await processDirectoryRenderText(host, output: output)
    #expect(text.contains("rust"), "\(text)")
    #expect(text.contains(index == 0 ? "work" : "tmp"), "\(text)")
    #expect(!text.contains(index == 0 ? "tmp" : "work"), "\(text)")
    #expect(text.contains(index == 0 ? "75%" : "25%"), "\(text)")
    #expect(text.replacingOccurrences(of: " ", with: "").contains(index == 0 ? "20mb" : "40mb"), "\(text)")
    #expect(host.fittingSize.height <= 36)
}

@Test(arguments: [ReportGrouping.none, .session], [false, true])
@MainActor func nativeStandaloneRowsExposeOwnersWithoutOpeningDetails(grouping: ReportGrouping, pinned: Bool)
    async throws
{
    _ = NSApplication.shared
    let snapshot = try sessionLabelSnapshot(directories: ["/work/api", "/tmp/web"])
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    model.report.overview.enabled = false
    if model.report.grouping != grouping { model.report.toggleGrouping() }
    if pinned { model.report.togglePin(.process(snapshot.findings[0].process)) }
    #expect(model.report.expanded == nil)
    #expect(model.visibleRowIDs.allSatisfy { if case .process = $0 { true } else { false } })
    let host = NSHostingView(
        rootView: MenuBarView(model: model).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.frame = NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: 560)
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    let output = ProcessInfo.processInfo.environment["MENUBAR_STANDALONE_PREVIEW_PATH"]
        .map { URL(fileURLWithPath: $0).deletingPathExtension().path + "-\(grouping.rawValue)-\(pinned).png" }
    let text = try await processDirectoryRenderText(host, output: output)
    for expected in ["claude", "abcdabcd", "12345678", "java", "work", "tmp/web"] {
        #expect(text.contains(expected), "\(text)")
    }
    await model.stop()
}

private enum StandaloneEvidenceFixture: CaseIterable {
    case unknown, runtime, ambiguous, shared

    var label: String {
        switch self {
        case .unknown, .runtime: "unresolved"
        case .ambiguous: "uncertain"
        case .shared: "shared runtime"
        }
    }
    var evidence: AttributionEvidence {
        switch self {
        case .unknown: .unknown
        case .runtime: .runtimeOnly
        case .ambiguous, .shared: .ambiguous
        }
    }
}

@Test(arguments: StandaloneEvidenceFixture.allCases)
@MainActor private func standaloneRowsPreserveUnknownAndSharedOwnership(kind: StandaloneEvidenceFixture)
    async throws
{
    _ = NSApplication.shared
    let identity = ProcessIdentity(pid: 42001, startMicroseconds: 1)
    let process = HeavyProcess(
        process: identity, executable: "/bin/node", name: "node", cpuPercent: 75,
        footprintBytes: 20_000_000, cwd: "/work/api", command: nil, metadataStatus: .notObserved,
        attribution: Attribution(
            provider: kind == .unknown ? nil : .codex, evidence: kind.evidence, context: .unverified,
            threadID: nil, rootSessionID: nil, runtime: kind == .shared ? identity : nil,
            terminal: nil, runtimeDirectory: nil, candidateThreadIDs: ["candidate-a", "candidate-b"],
            ancestry: []))
    let host = NSHostingView(
        rootView: MenuBarProcessLabel(
            process: process, placement: .standalone,
            directory: ProcessDirectoryLabels([process]).label(for: process),
            cpuText: "75%", footprintText: "20 MB"
        ).frame(width: 280).padding(8).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    host.frame.size = host.fittingSize
    let text = try await processDirectoryRenderText(host, output: nil)
    #expect(text.contains(kind.label), "\(text)")
    #expect(text.contains(kind == .unknown ? "unknown" : "codex"), "\(text)")
    #expect(!text.contains("candidate-a") && !text.contains("candidate-b"))
    #expect(text.contains("node") && text.contains("75%"), "\(text)")
}

@Test @MainActor func standaloneHistoricalLabelChangesStayVisibleBesideTheOwner() async throws {
    _ = NSApplication.shared
    let original = try #require(try sessionLabelSnapshot().findings.first)
    let process = HeavyProcess(
        process: original.process, executable: original.executable, name: original.name,
        cpuPercent: original.cpuPercent, footprintBytes: nil, cwd: original.cwd, command: nil,
        metadataStatus: original.metadataStatus, attribution: original.attribution,
        accounting: ProcessWindowAccounting(
            cpuSeconds: 1, recoveredCPUSeconds: 0, pointCandidateCPUSeconds: 0.7,
            uncertainCPUSeconds: 0.3, isHistorical: true, lastObservedAt: 1,
            lastObservedFootprintBytes: 320_000_000, labelChangedInWindow: true))
    let host = NSHostingView(
        rootView: MenuBarProcessLabel(
            process: process, placement: .standalone,
            directory: ProcessDirectoryLabels([process]).label(for: process),
            cpuText: "90%", footprintText: "—"
        ).frame(width: 280).padding(8).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    host.frame.size = host.fittingSize
    let text = try await processDirectoryRenderText(
        host, output: ProcessInfo.processInfo.environment["MENUBAR_HISTORICAL_LABEL_PREVIEW_PATH"])
    for expected in ["claude", "abcdabcd", "changed", "past", "90%"] {
        #expect(text.contains(expected), "\(text)")
    }
    #expect(!text.contains("0.32"))
}

@MainActor private func processDirectoryRenderText(_ host: NSView, output: String?) async throws -> String {
    let window = host.window == nil ? await mountOffscreenNativePreview(host) : nil
    defer { window?.close() }
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2),
            pixelsHigh: Int(host.bounds.height * 2), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.size = host.bounds.size
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let recognized = try await nativeRecognizedText(in: #require(bitmap.cgImage))
    if let output {
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: output))
    }
    return recognized.map(\.text)
        .joined(separator: " ").lowercased()
}

@Test @MainActor func nativeOverviewLongExecutablesKeepDistinctDirectoriesVisible() async throws {
    _ = NSApplication.shared
    var overview = ContributorOverview()
    overview.receive(
        try sessionLabelSnapshot(
            workersPerSession: 2, directories: ["/work/app", "/tmp/web"], directoriesByWorker: true,
            executableName: "rust-analyzer-proc-macro-srv"))
    let session = try #require(overview.main.first)
    overview.toggle(session)
    let families = overview.visibleRows.filter {
        if case .executable = $0.id { true } else { false }
    }
    #expect(families.count == 2)
    for (index, row) in families.enumerated() {
        let host = NSHostingView(
            rootView: MenuBarContributorRow(node: row.node, overview: overview)
                .frame(width: 580).padding(8).background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        host.frame.size = host.fittingSize
        let text = try await processDirectoryRenderText(
            host,
            output: ProcessInfo.processInfo.environment["MENUBAR_WORKLOAD_PREVIEW_PATH"].map {
                $0 + "-\(index).png"
            })
        let cwd = try #require(row.node.inspectionFields.first { $0.label == "Directory" }).value
        #expect(text.contains(cwd == "/work/app" ? "work/app" : "tmp/web"), "\(text)")
        #expect(text.contains("rust"), "\(text)")
        #expect(host.fittingSize.height <= 90)
    }
}

@Test @MainActor func nativeRootGroupKeepsChildThreadIdentitiesVisible() async throws {
    _ = NSApplication.shared
    let sessions = ["abcdabcd-root", "12345678-child", "fedcfedc-child"]
    let snapshot = try sessionLabelSnapshot(
        directories: ["/work/api", "/work/api", "/work/api"], sessionIDs: sessions,
        rootSessionID: sessions[0])
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    model.report.overview.enabled = false
    let group = try #require(model.report.groups.first)
    #expect(model.report.groups.count == 1)
    #expect(group.processes.count == 3)
    model.report.select(.group(group.id))
    model.report.setDisclosure(expanded: true)
    let host = NSHostingView(
        rootView: MenuBarView(model: model).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.frame = NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: 700)
    host.layoutSubtreeIfNeeded()
    let text = try await processDirectoryRenderText(
        host, output: ProcessInfo.processInfo.environment["MENUBAR_ROOT_PREVIEW_PATH"])
    for id in sessions { #expect(text.contains(id.prefix(8)), "\(text)") }
    await model.stop()
}

private func sessionLabelOverview() throws -> ContributorOverview {
    var overview = ContributorOverview()
    overview.receive(try sessionLabelSnapshot())
    return overview
}

private func sessionLabelSnapshot(
    workersPerSession: Int = 1, directories: [String] = ["/work/alpha/project", "/tmp/alpha/project"],
    directoriesByWorker: Bool = false, executableName: String = "java",
    sessionIDs: [String]? = nil, rootSessionID: String? = nil
) throws -> MonitoringSnapshot {
    let sessions =
        sessionIDs ?? [
            "abcdabcd-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "12345678-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        ]
    func samples(_ time: Double) -> [ProcessSample] {
        sessions.indices.flatMap { index in
            (0..<workersPerSession).map { worker in
                ProcessSample(
                    identity: ProcessIdentity(
                        pid: Int32(index * workersPerSession + worker + 1), startMicroseconds: 1),
                    parentPID: 0, executable: "/bin/" + executableName, name: executableName, sampledAt: time,
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
                provider: .claude, evidence: .marker, context: rootSessionID == nil ? .unverified : .terminal,
                threadID: sessions[session], rootSessionID: rootSessionID,
                runtime: rootSessionID == nil ? nil : values.first?.identity, terminal: nil,
                runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []))
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

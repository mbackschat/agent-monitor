import AgentMonitorPresentation
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import AgentMonitorCore
@testable import AgentMonitorMenuBar

@Test(
    .enabled(if: ProcessInfo.processInfo.environment["MENUBAR_OVERVIEW_PREVIEW_PATH"] != nil),
    arguments: [false, true])
@MainActor func nativeContributorOverviewRenders(dark: Bool) async throws {
    let output = try #require(ProcessInfo.processInfo.environment["MENUBAR_OVERVIEW_PREVIEW_PATH"])
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
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

private func nativeOverviewFixture() throws -> MonitoringSnapshot {
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
        var activity = RecentActivityAccumulator(baseline: baseline)
        activity.append(scan, rows: findings)
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
        cpuThresholdPercent: 0, memoryThresholdBytes: 0, sampledProcessCount: 23, unreadableProcessCount: 0,
        findings: projection.rows, agentLoad: AgentLoadSummary(processes: projection.rows),
        window: projection.summary, recentActivity: store.snapshot())
}

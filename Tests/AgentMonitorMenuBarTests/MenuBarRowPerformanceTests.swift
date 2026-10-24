import AgentMonitorCore
import AgentMonitorPresentation
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import AgentMonitorMenuBar

private struct RowCommandMeasurement: Codable {
    let processes: Int
    let grouping: String
    var observedProcesses: Int? = nil
    let milliseconds: [Double]
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MENUBAR_ROW_MEASUREMENT_PATH"] != nil))
@MainActor func measureNativeRowCommandProjection() async throws {
    let output = try #require(ProcessInfo.processInfo.environment["MENUBAR_ROW_MEASUREMENT_PATH"])
    var measurements: [RowCommandMeasurement] = []
    for (count, displayedCount) in [(50, 50), (150, 150), (150, 10)] {
        let observed = try (0..<count).flatMap { index in
            try menuBarFixture(
                pids: [Int32(42001 + index)],
                cpu: index < displayedCount ? 184.6 : 0,
                memoryBytes: index < displayedCount ? 1_400_000_000 : 1_000_000,
                sessionID: String(format: "11111111-1111-4111-8111-%012d", index % displayedCount)
            ).findings
        }
        let findings = Array(observed.prefix(displayedCount))
        let snapshot = MonitoringSnapshot(
            cpuAccounting: CPUAccounting(
                hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
                unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
            timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 0.1,
            cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
            sampledProcessCount: count, unreadableProcessCount: 0, findings: findings,
            observedFindings: observed)
        let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
        model.open()
        await model.waitForCollection()
        for grouping in [ReportGrouping.session, .none] {
            if model.report.grouping != grouping { model.report.toggleGrouping() }
            let rows = model.visibleRowIDs
            #expect(rows.count == displayedCount)
            #expect(model.rowIndex.projection.groups.flatMap(\.processes).count == count)
            var durations: [Double] = []
            for _ in 0..<3 {
                let start = ContinuousClock.now
                var enabled = 0
                for row in rows {
                    if model.canBegin(.terminate, row: row) { enabled += 1 }
                    _ = model.canBegin(.message, row: row)
                    _ = model.canBegin(.focus, row: row)
                    switch row {
                    case .process: #expect(model.pidToCopy(for: row) != nil)
                    case .group: #expect(model.pidToCopy(for: row) == nil)
                    }
                }
                let elapsed = start.duration(to: .now).components
                durations.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
                #expect(enabled == rows.filter { if case .process = $0 { true } else { false } }.count)
            }
            measurements.append(
                RowCommandMeasurement(
                    processes: displayedCount, grouping: grouping.rawValue,
                    observedProcesses: count, milliseconds: durations))
        }
        await model.stop()
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(measurements).write(to: URL(fileURLWithPath: output))
}

private struct RowRenderMeasurement: Codable {
    let processes: Int
    let displayedRows: Int
    let initialMilliseconds: Double
    let refreshMilliseconds: [Double]
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MENUBAR_ROW_RENDER_PATH"] != nil))
@MainActor func measureNativeRowRendering() async throws {
    let output = try #require(ProcessInfo.processInfo.environment["MENUBAR_ROW_RENDER_PATH"])
    _ = NSApplication.shared
    var measurements: [RowRenderMeasurement] = []
    for (count, displayedCount, expanded) in [
        (150, 150, false), (1000, 1000, false), (150, 10, false), (150, 150, true),
    ] {
        let findings = try (0..<count).flatMap { index in
            try menuBarFixture(
                pids: [Int32(42001 + index)],
                cpu: index < displayedCount ? 184.6 : 0,
                memoryBytes: index < displayedCount ? 1_400_000_000 : 1_000_000,
                sessionID: String(
                    format: "11111111-1111-4111-8111-%012d", index % (expanded ? 1 : displayedCount))
            ).findings
        }
        func snapshot(_ tick: Double) -> MonitoringSnapshot {
            MonitoringSnapshot(
                cpuAccounting: CPUAccounting(
                    hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: tick,
                    unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
                timestamp: Date(timeIntervalSince1970: tick), intervalSeconds: 0.1,
                cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
                sampledProcessCount: count, unreadableProcessCount: 0,
                findings: Array(findings.prefix(displayedCount)), observedFindings: findings)
        }
        let first = snapshot(0)
        let model = MenuBarModel { _, _, receive in try await receive(first) }
        model.open()
        await model.waitForCollection()
        if expanded { model.report.setSessionDisclosure(expanded: true, from: nil) }
        #expect(model.visibleRowIDs.count == displayedCount + (expanded ? 1 : 0))
        let start = ContinuousClock.now
        let host = NSHostingView(rootView: MenuBarView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 560)
        host.layoutSubtreeIfNeeded()
        let initial = elapsedMilliseconds(since: start)
        var refresh: [Double] = []
        for tick in 1...3 {
            let start = ContinuousClock.now
            model.report.receive(snapshot(Double(tick)))
            host.layoutSubtreeIfNeeded()
            refresh.append(elapsedMilliseconds(since: start))
            #expect(host.fittingSize == NSSize(width: 420, height: 560))
        }
        measurements.append(
            RowRenderMeasurement(
                processes: count, displayedRows: model.visibleRowIDs.count, initialMilliseconds: initial,
                refreshMilliseconds: refresh))
        await model.stop()
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(measurements).write(to: URL(fileURLWithPath: output))
}

private func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Double {
    let elapsed = start.duration(to: .now).components
    return Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
}

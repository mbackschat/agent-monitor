import AgentMonitorPresentation
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import AgentMonitorCore
@testable import AgentMonitorMenuBar

@Test @MainActor func adaptiveSamplingCoverageRendersCurrentPolicyAndRetainedOverrideRows() async throws {
    _ = NSApplication.shared
    var sampling = SamplingCoverage()
    sampling.append(
        SamplingDecision(
            mode: .adaptive, requestedSeconds: 0.1, baseSeconds: 0.3,
            minimumSeconds: 0.1, maximumSeconds: 0.5, rollingCPURate: 0.004,
            youngCPURate: 0.002, arrivalRate: 0.1, rollingSpanSeconds: 12.5,
            recentCPURate: 0.02, recentSpanSeconds: 1.25, overrides: [.recovery]),
        duration: 0.5, activations: [.recovery], policyChanges: 2)
    let timing = AcquisitionTiming(
        runID: UUID(), scanSequence: 1, qualityOfService: .userInitiated,
        requestedPeriodSeconds: 0.5, achievedPeriodSeconds: 0.6,
        scanWorkSeconds: 0, resolutionDelaySeconds: 0, sampling: sampling)
    let snapshot = MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
            unmeasuredLifetimeCount: 0, previousScanSeconds: nil, acquisition: timing),
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 0.1,
        cpuThresholdPercent: 0, memoryThresholdBytes: 0, sampledProcessCount: 0,
        unreadableProcessCount: 0, findings: [])
    let host = NSHostingView(
        rootView: MenuBarCoverageSummary(summary: SamplingCoverageSummary(snapshot: snapshot))
            .padding(12).frame(width: 400).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    host.frame.size = host.fittingSize
    #expect(host.bounds.width > 0 && host.bounds.height > 0)
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2),
            pixelsHigh: Int(host.bounds.height * 2), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.size = host.bounds.size
    host.cacheDisplay(in: host.bounds, to: bitmap)
    if let path = ProcessInfo.processInfo.environment["MENUBAR_SAMPLING_PREVIEW_PATH"] {
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: path))
    }
    let image = try #require(bitmap.cgImage)
    let recognized: [NativeRecognizedText]
    do {
        recognized = try await nativeRecognizedText(in: image)
    } catch {
        Issue.record(
            error, "Vision OCR failed for the \(image.width) × \(image.height) offscreen coverage bitmap")
        return
    }
    let text = recognized.map(\.text).joined(separator: " ")
    for label in ["Adaptive", "Requested / base", "Rolling support", "Recent support", "Recovery"] {
        #expect(text.contains(label))
    }
}

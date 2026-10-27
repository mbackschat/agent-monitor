import AgentMonitorCore
import AgentMonitorPresentation
import Foundation
import Testing

private let context = CPUAccounting(
    hostBusyPercent: 210.9, logicalCPUCount: 8, measuredUserPercent: 169.1,
    unmeasuredLifetimeCount: 3, previousScanSeconds: 0.041)

@Test func cpuContextUsesOneSharedLineWithRoundedPercentagesAndCoverage() {
    #expect(
        CPUContext.text(context) == "CPU: host 211% of 800% · your measured processes 169% (3 without data)")
    let unavailable = CPUAccounting(
        hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
        unmeasuredLifetimeCount: 2, previousScanSeconds: nil)
    #expect(
        CPUContext.text(unavailable)
            == "CPU: host No data of 800% · your measured processes 0% (2 without data)")
    let idle = CPUAccounting(
        hostBusyPercent: 0, logicalCPUCount: 8, measuredUserPercent: 0,
        unmeasuredLifetimeCount: 0, previousScanSeconds: 0.01)
    #expect(CPUContext.text(idle) == "CPU: host 0% of 800% · your measured processes 0% (0 without data)")
}

@Test func textAndPassiveDiagnosticsRetainFullCPUContext() {
    let snapshot = MonitoringSnapshot(
        cpuAccounting: context, timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1,
        cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
        sampledProcessCount: 10, unreadableProcessCount: 1, findings: [])
    #expect(TextReport.render(snapshot).contains(CPUContext.text(context)))
    var state = LiveReportState()
    state.receive(snapshot)
    state.showReference(.diagnostics)
    let content = ReportReferenceLayout.content(state: state, page: .diagnostics)
    #expect(content.contains { $0.text == CPUContext.text(context) })
}

@Test func cpuContextDistinguishesAchievedAcquisitionFromResolverDelay() {
    let timing = AcquisitionTiming(
        runID: UUID(), scanSequence: 1, qualityOfService: .userInitiated,
        requestedPeriodSeconds: 0.1, achievedPeriodSeconds: 0.125,
        scanWorkSeconds: 0.02, resolutionDelaySeconds: 0.4)
    let value = CPUAccounting(
        hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
        unmeasuredLifetimeCount: 0, previousScanSeconds: nil, acquisition: timing)
    #expect(CPUContext.text(value).contains("period 125 ms"))
    #expect(CPUContext.text(value).contains("resolution 0.4 s behind"))
}

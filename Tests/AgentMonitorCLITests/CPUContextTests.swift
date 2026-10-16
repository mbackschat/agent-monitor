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

@Test func textAndTUIHeadersUseTheSameCPUContext() {
    let snapshot = MonitoringSnapshot(
        cpuAccounting: context, timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1,
        cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
        sampledProcessCount: 10, unreadableProcessCount: 1, findings: [])
    #expect(TextReport.render(snapshot).contains(CPUContext.text(context)))
    var state = LiveReportState()
    state.receive(snapshot)
    let lines = LiveReportLayout.lines(state: state, width: 120, height: 20)
    #expect(lines.prefix(3).contains { $0.text == CPUContext.text(context) })
}

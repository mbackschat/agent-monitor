import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore

@Test func historyUsesAllAgentTotalsAndPreservesPeaksInTimeBuckets() {
    var history = ReportHistory()
    history.receive(historySnapshot(at: 1, cpu: 200))
    history.receive(historySnapshot(at: 1.5, cpu: 20))
    history.receive(historySnapshot(at: 600, cpu: 40))
    let bins = history.values(metric: .cpu, window: .tenMinutes, count: 10)
    #expect(bins[0] == 200)
    #expect(bins[9] == 40)
    #expect(bins[1..<9].allSatisfy { $0 == nil })
    #expect(history.currentValue(.cpu) == 40)
    #expect(history.currentValue(.memory) == 2)
    #expect(history.currentValue(.heavyCount) == 1)
}

@Test func historyBoundsRetentionAndKeepsTheLongerRangeWhenSwitching() {
    var history = ReportHistory()
    for second in 0...3700 { history.receive(historySnapshot(at: Double(second), cpu: Double(second))) }
    #expect(history.pointCount <= 3601)
    #expect(history.values(metric: .cpu, window: .oneHour, count: 60)[0] == 160)
    #expect(history.values(metric: .cpu, window: .tenMinutes, count: 10)[0] == 3160)
}

@Test func missingHistoryMeasurementsAreGapsAndMeasuredZeroIsNotAGap() {
    var history = ReportHistory()
    history.receive(historySnapshot(at: 1, cpu: 0))
    #expect(history.currentValue(.cpu) == 0)
    history.receive(historySnapshot(at: 100, cpu: nil))
    #expect(history.currentValue(.cpu) == nil)
    #expect(history.values(metric: .cpu, window: .tenMinutes, count: 10)[9] == nil)
    #expect(history.currentValue(.memory) == 2)
}

@Test func historyPauseHoldsTheStripButResumeIncludesInterveningSamples() {
    var state = LiveReportState()
    state.receive(historySnapshot(at: 1, cpu: 10))
    state.toggleFreeze()
    state.receive(historySnapshot(at: 2, cpu: 200))
    state.receive(historySnapshot(at: 3, cpu: 20))
    #expect(state.history.currentValue(.cpu) == 10)
    state.toggleFreeze()
    #expect(state.history.currentValue(.cpu) == 20)
    #expect(state.history.values(metric: .cpu, window: .tenMinutes, count: 10)[9] == 200)
    state.historyMetric = .memory
    state.historyWindow = .oneHour
    state.resetCollection()
    #expect(state.historyMetric == .memory)
    #expect(state.historyWindow == .oneHour)
    #expect(state.history.currentValue(.cpu) == 20)
}

@Test func historyClockRollbackStartsANewTimelineAndDuplicateSamplesDoNotGrowIt() {
    var history = ReportHistory()
    history.receive(historySnapshot(at: 100, cpu: 10))
    history.receive(historySnapshot(at: 100, cpu: 10))
    #expect(history.pointCount == 1)
    history.receive(historySnapshot(at: 10, cpu: 20))
    #expect(history.pointCount == 1)
    #expect(history.currentValue(.cpu) == 20)
}

private func historySnapshot(at time: Double, cpu: Double?) -> MonitoringSnapshot {
    let id = ProcessIdentity(pid: 42, startMicroseconds: 1)
    let process = HeavyProcess(
        process: id, executable: "/bin/worker", name: "worker", cpuPercent: cpu,
        footprintBytes: 2_000_000_000, cwd: nil, command: nil, metadataStatus: .notObserved,
        attribution: Attribution(
            provider: .codex, evidence: .unknown, context: .unverified, threadID: nil,
            rootSessionID: nil, runtime: nil, terminal: nil, runtimeDirectory: nil,
            candidateThreadIDs: [], ancestry: [id]))
    return MonitoringSnapshot(
        timestamp: Date(timeIntervalSince1970: time), intervalSeconds: 1,
        cpuThresholdPercent: 999, memoryThresholdBytes: 9_000_000_000,
        sampledProcessCount: 1, unreadableProcessCount: 0, findings: [],
        agentLoad: AgentLoadSummary(processes: [process]))
}

@Test(arguments: [40, 60, 120], HistoryMetric.allCases)
func historyUsesOneTerminalRowWithDiscoverableControls(width: Int, metric: HistoryMetric) {
    var state = LiveReportState()
    state.receive(historySnapshot(at: 1, cpu: 180))
    state.historyMetric = metric
    let line = state.history.line(metric: metric, window: .tenMinutes, width: width)
    #expect(line.count == width)
    #expect(line.contains("[h]"))
    #expect(line.contains("10m[t]"))
    #expect(line.contains(metric.formatted(state.history.currentValue(metric))))
}

@Test func tableSamplesWithoutASummaryPreserveHistoryUntilTheNextSummary() {
    var history = ReportHistory()
    history.receive(historySnapshot(at: 1, cpu: 180))
    let held = history
    history.receive(
        MonitoringSnapshot(
            timestamp: Date(timeIntervalSince1970: 2), intervalSeconds: 1,
            cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
            sampledProcessCount: 0, unreadableProcessCount: 0, findings: []))
    #expect(history == held)
    history.receive(historySnapshot(at: 16, cpu: 20))
    #expect(history.pointCount == 2)
    #expect(history.currentValue(.cpu) == 20)
}

@Test func fortyFifteenSecondSamplesFillFortyTenMinuteBinsWithoutMergingTheNewestPair() {
    var history = ReportHistory()
    for index in 1...40 { history.receive(historySnapshot(at: Double(index * 15), cpu: Double(index))) }
    #expect(history.values(metric: .cpu, window: .tenMinutes, count: 40) == (1...40).map { Double($0) })
}

import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct CarriedInspectionTests {
    @Test func carriedCPUIsHistoricalAtItsAdmissionCensusAndSurvivesHistory() throws {
        let held = inspectionReading()
        var ledger = CounterLedger()
        var window = AccountingWindow(baseline: ledger.ingest([], listedAt: 0))
        let counters = ledger.ingest([], listedAt: 0.1, carried: [held.sample])
        try window.append(counters, rows: [], carried: [held])
        let row = try #require(try window.findings(scope: .allProcesses).first)
        #expect(row.isHistorical)
        #expect(row.footprintBytes == nil)
        #expect(row.accounting?.cpuSeconds == 0.02)
        #expect(row.accounting?.lastObservedAt == 0.05)
        #expect(window.current.isEmpty)
        #expect(window.present.isEmpty)
        #expect(window.summary.endedAt == 0.1)
        let unit = window.seal(scope: .allProcesses)
        #expect(unit.records.first?.maximumFootprint?.bytes == 100)
        let history = RecentActivityStore()
        history.append(unit)
        #expect(history.snapshot()?.current.isEmpty == true)
        #expect(history.snapshot()?.present.isEmpty == true)
    }

    @Test func parentContextIsFrozenAndNeverChangesTheCensusGraph() throws {
        var monitor = Monitor()
        let parent = sample(1, start: 1, at: 0)
        monitor.ingest([parent], listedAt: 0)
        monitor.enrich(
            ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]),
            for: parent.identity, observedAt: 0)
        let before = monitor.findings()
        let held = monitor.inspectionObservation(
            inspectionReading().sample, parent: parent.identity, cwd: "/work")
        #expect(held.row.attribution.threadID == sessionA)
        #expect(held.row.attribution.evidence == .inheritedMarker)
        #expect(monitor.findings() == before)
        #expect(monitor.finding(for: held.sample.identity) == nil)
        monitor.enrich(
            ProcessMetadata(markers: [SessionMarker(threadID: sessionB, provider: .codex)]),
            for: parent.identity, observedAt: 0.1)
        #expect(held.row.attribution.threadID == sessionA)
        let reused = ProcessIdentity(pid: 1, startMicroseconds: 3)
        monitor.ingest([sample(1, start: 3)])
        monitor.enrich(
            ProcessMetadata(markers: [SessionMarker(threadID: sessionB, provider: .codex)]), for: reused)
        let rejected = monitor.inspectionObservation(inspectionReading().sample, parent: reused, cwd: nil)
        #expect(rejected.row.attribution.threadID == nil)
        let unknown = monitor.inspectionObservation(
            inspectionReading().sample, parent: parent.identity, cwd: nil)
        #expect(unknown.row.attribution.threadID == nil)
    }
}

extension CarriedInspectionTests {
    @Test func departureOfParentDoesNotEraseFrozenOwnershipAndExecIsCounted() throws {
        var monitor = Monitor()
        let parent = sample(1, start: 1, at: 0)
        monitor.ingest([parent])
        monitor.enrich(
            ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]),
            for: parent.identity)
        var worker = inspectionReading().sample
        worker.sampledAt = 0
        worker.cpuSeconds = 0
        var ledger = CounterLedger()
        var window = AccountingWindow(baseline: ledger.ingest([worker], listedAt: 0))
        worker.sampledAt = 0.05
        worker.cpuSeconds = 0.02
        worker.executable = "/fake/new-executable"
        let held = monitor.inspectionObservation(worker, parent: parent.identity, cwd: "/work")
        monitor.ingest([], listedAt: 0.1)
        let scan = ledger.ingest([], listedAt: 0.1, carried: [worker])
        try window.append(scan, rows: monitor.findings(), carried: [held])
        let contribution = try #require(window.summary.contributions.first)
        #expect(contribution.attribution.threadID == sessionA)
        #expect(contribution.cpuSeconds == 0.02)
        #expect(contribution.executableChangedIntervalCount == 1)
        #expect(window.seal(scope: .agentsOnly).records.first?.category.executable == worker.executable)
        #expect(window.present.isEmpty)
    }
}

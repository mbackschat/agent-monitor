import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct PublicationCoverageTests {
    @Test func backlogPreservesExtremaAndEvictsCoalescedUnitsWhole() throws {
        var ledger = CounterLedger()
        var baseline = ledger.ingest([sample(42, at: 0, cpu: 0)], listedAt: 0)
        var units: [AccountingWindow] = []
        for tick in 1...4 {
            let value = sample(42, at: Double(tick), cpu: Double(tick), memory: tick == 2 ? 1_000 : 100)
            let scan = ledger.ingest([value], listedAt: Double(tick))
            var window = AccountingWindow(baseline: baseline)
            let timing = AcquisitionTiming(
                runID: scan.id.runID, scanSequence: scan.id.sequence, qualityOfService: .userInitiated,
                requestedPeriodSeconds: 0.1, achievedPeriodSeconds: tick == 2 ? 1.2 : 0.1,
                scanWorkSeconds: 0, resolutionDelaySeconds: 0)
            try window.append(scan, rows: [recentRow(value, session: sessionA)], timing: timing)
            units.append(window)
            baseline = scan
        }
        var backlog = units[1]
        try backlog.merge(units[2])
        backlog.coalescePublication()
        let merged = backlog.seal(scope: .agentsOnly)
        #expect(merged.records.reduce(0) { $0 + $1.cpuSeconds } == 2)
        #expect(merged.records.first?.maximumFootprint?.bytes == 1_000)
        #expect(merged.acquisitionCoverage.maximumGapSeconds == 1.2)
        #expect(merged.acquisitionCoverage.overrunCount == 1)
        #expect(merged.publicationCoverage.sourceUnitCount == 2)
        #expect(merged.publicationCoverage.publishedUnitCount == 1)
        #expect(merged.publicationCoverage.coalescedUnitCount == 2)
        #expect(merged.publicationCoverage.maximumUnitSpanSeconds == 2)
        #expect(merged.publicationCoverage.coalescedStartedAt == 1)
        #expect(merged.publicationCoverage.coalescedEndedAt == 3)
        let store = RecentActivityStore(limits: RecentActivityLimits(seconds: 2.5))
        store.append(units[0].seal(scope: .agentsOnly))
        store.append(merged)
        #expect(store.snapshot()?.cpuSeconds == 2)
        #expect(store.snapshot()?.startedAt == 1)
        store.append(units[3].seal(scope: .agentsOnly))
        #expect(store.snapshot()?.cpuSeconds == 1)
        #expect(store.snapshot()?.startedAt == 3)
        #expect(store.snapshot()?.units.first?.publicationCoverage.coalescedUnitCount == 0)
        var display = units[0]
        try display.merge(units[1])
        #expect(display.summary.publicationCoverage.sourceUnitCount == 2)
        #expect(display.summary.publicationCoverage.publishedUnitCount == 2)
        #expect(display.summary.publicationCoverage.coalescedUnitCount == 0)
    }
}

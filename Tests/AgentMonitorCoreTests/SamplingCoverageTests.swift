import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct SamplingCoverageTests {
    @Test func overrideActivationsAndDurationRemainSeparateAcrossMerges() throws {
        let held = SamplingDecision(
            mode: .adaptive, requestedSeconds: 0.1, baseSeconds: 0.3,
            minimumSeconds: 0.1, maximumSeconds: 0.5, overrides: [.uncertainty, .lifecycle])
        var first = SamplingCoverage()
        first.append(held, duration: 0.1, activations: [.uncertainty, .lifecycle], policyChanges: 1)
        first.append(held, duration: 0.25, activations: [], policyChanges: 0)
        let fixed = SamplingDecision(
            requestedSeconds: 0.5, baseSeconds: 0.5, minimumSeconds: 0.1,
            maximumSeconds: 0.5, overrides: [.inspection])
        var second = SamplingCoverage()
        second.append(fixed, duration: 0.5, activations: [.inspection], policyChanges: 2)
        first.merge(second)
        #expect(first.modes == [.fixed, .adaptive])
        #expect(first.latest == fixed)
        #expect(first.overrideActivations == ["uncertainty": 1, "lifecycle": 1, "inspection": 1])
        #expect(abs((first.overrideSeconds["uncertainty"] ?? 0) - 0.35) < 1e-9)
        #expect(abs((first.overrideSeconds["lifecycle"] ?? 0) - 0.35) < 1e-9)
        #expect(first.overrideSeconds["inspection"] == 0.5)
        #expect(first.policyChangeCount == 3)
        #expect(first.minimumRequestedSeconds == 0.1)
        #expect(first.maximumRequestedSeconds == 0.5)
        #expect(try JSONDecoder().decode(SamplingCoverage.self, from: JSONEncoder().encode(first)) == first)
    }

    @Test func latestDecisionDoesNotInventAnotherPeriodOrActivation() {
        var coverage = SamplingCoverage()
        let active = SamplingDecision(mode: .adaptive, overrides: [.recovery])
        coverage.append(active, duration: 0.4, activations: [.recovery], policyChanges: 1)
        let current = SamplingDecision(
            mode: .adaptive, requestedSeconds: 0.3, baseSeconds: 0.3, maximumSeconds: 0.5)
        coverage.setLatest(current)
        coverage.merge(SamplingCoverage())
        #expect(coverage.latest == current)
        #expect(coverage.overrideActivations == ["recovery": 1])
        #expect(coverage.overrideSeconds == ["recovery": 0.4])
        #expect(coverage.policyChangeCount == 1)
        #expect(coverage.minimumRequestedSeconds == 0.1)
        #expect(coverage.maximumRequestedSeconds == 0.1)
    }

    @Test func acquisitionIncludesUntimedRequestsAndCoalescesTheirExtrema() throws {
        var ledger = CounterLedger()
        let baseline = ledger.ingest([], listedAt: 0)
        let middle = ledger.ingest([], listedAt: 0.5)
        let final = ledger.ingest([], listedAt: 1)
        var window = AccountingWindow(baseline: baseline)
        var active = SamplingCoverage()
        active.append(
            SamplingDecision(mode: .adaptive, overrides: [.sustained]), duration: 0.5,
            activations: [.sustained], policyChanges: 1)
        try window.append(
            middle, rows: [],
            timing: samplingTiming(middle, requested: 0.1, achieved: nil, sampling: active))
        var next = AccountingWindow(baseline: middle)
        var continued = SamplingCoverage()
        continued.append(
            SamplingDecision(
                mode: .adaptive, requestedSeconds: 0.5, baseSeconds: 0.5,
                maximumSeconds: 0.5, overrides: [.sustained]), duration: 0.5,
            activations: [], policyChanges: 0)
        try next.append(
            final, rows: [],
            timing: samplingTiming(final, requested: 0.5, achieved: 0.6, sampling: continued))
        try window.merge(next)
        window.coalescePublication()
        let coverage = window.seal(scope: .allProcesses).acquisitionCoverage
        #expect(coverage.scanCount == 2)
        #expect(coverage.timedPeriodCount == 1)
        #expect(coverage.minimumRequestedPeriodSeconds == 0.1)
        #expect(coverage.maximumRequestedPeriodSeconds == 0.5)
        #expect(coverage.maximumGapSeconds == 0.6)
        #expect(coverage.overrunCount == 0)
        #expect(coverage.sampling.overrideActivations == ["sustained": 1])
        #expect(coverage.sampling.overrideSeconds == ["sustained": 1])
        #expect(coverage.sampling.policyChangeCount == 1)
        #expect(
            try JSONDecoder().decode(AcquisitionCoverage.self, from: JSONEncoder().encode(coverage))
                == coverage)
    }

    @Test func fixedRequestsHaveNoAdaptiveOverrides() {
        var coverage = AcquisitionCoverage()
        let timing = AcquisitionTiming(
            runID: UUID(), scanSequence: 1, qualityOfService: .userInitiated,
            requestedPeriodSeconds: 2, achievedPeriodSeconds: 2,
            scanWorkSeconds: 0, resolutionDelaySeconds: 0)
        coverage.append(timing)
        #expect(coverage.minimumRequestedPeriodSeconds == 2)
        #expect(coverage.maximumRequestedPeriodSeconds == 2)
        #expect(coverage.sampling.overrideActivations.isEmpty)
        #expect(coverage.sampling.overrideSeconds.isEmpty)
    }

    @Test func midPeriodShorteningKeepsActualRequestsSeparateFromTheEffectiveDeadline() {
        var sampling = SamplingCoverage()
        sampling.append(
            SamplingDecision(requestedSeconds: 1, baseSeconds: 1, maximumSeconds: 1),
            duration: 0.5, activations: [], policyChanges: 0)
        sampling.append(
            SamplingDecision(requestedSeconds: 0.1, baseSeconds: 0.1, maximumSeconds: 1),
            duration: 0, activations: [], policyChanges: 1)
        var coverage = AcquisitionCoverage()
        coverage.append(
            AcquisitionTiming(
                runID: UUID(), scanSequence: 1, qualityOfService: .userInitiated,
                requestedPeriodSeconds: 0.1, achievedPeriodSeconds: 0.5,
                scanWorkSeconds: 0, resolutionDelaySeconds: 0, sampling: sampling,
                effectivePeriodSeconds: 0.5))
        #expect(coverage.minimumRequestedPeriodSeconds == 0.1)
        #expect(coverage.maximumRequestedPeriodSeconds == 1)
        #expect(coverage.overrunCount == 0)
    }

    @Test func recentRangeCompactionAndEvictionConserveOnlyRetainedSamplingPeriods() throws {
        let runID = UUID()
        let store = RecentActivityStore(limits: RecentActivityLimits(seconds: 2.5))
        for index in 0..<2 {
            var sampling = SamplingCoverage()
            sampling.append(
                SamplingDecision(
                    mode: .adaptive, requestedSeconds: index == 0 ? 0.1 : 0.25,
                    baseSeconds: index == 0 ? 0.1 : 0.25, maximumSeconds: 0.25,
                    overrides: [.lifecycle]),
                duration: index == 0 ? 0.4 : 0.6,
                activations: index == 0 ? [.lifecycle] : [], policyChanges: index == 0 ? 1 : 0)
            var coverage = AcquisitionCoverage()
            coverage.append(
                AcquisitionTiming(
                    runID: runID, scanSequence: UInt64(index + 1), qualityOfService: .userInitiated,
                    requestedPeriodSeconds: index == 0 ? 0.1 : 0.25,
                    achievedPeriodSeconds: index == 0 ? 0.2 : 0.3,
                    scanWorkSeconds: 0, resolutionDelaySeconds: 0, sampling: sampling))
            store.append(
                RecentActivityUnit(
                    runID: runID, baseline: UInt64(index), final: UInt64(index + 1),
                    start: Double(index), end: Double(index + 1), scope: .allProcesses,
                    records: [], crossings: [], excluded: 0, acquisition: coverage))
        }
        let before = try #require(store.snapshot())
        #expect(before.units.count == 2)
        #expect(before.acquisitionCoverage.scanCount == 2)
        #expect(before.acquisitionCoverage.sampling.overrideActivations == ["lifecycle": 1])
        #expect(before.acquisitionCoverage.sampling.overrideSeconds == ["lifecycle": 1])
        #expect(before.acquisitionCoverage.minimumRequestedPeriodSeconds == 0.1)
        #expect(before.acquisitionCoverage.maximumRequestedPeriodSeconds == 0.25)

        var fixed = SamplingCoverage()
        fixed.append(
            SamplingDecision(requestedSeconds: 0.5, baseSeconds: 0.5, maximumSeconds: 0.5),
            duration: 1, activations: [], policyChanges: 1)
        var coverage = AcquisitionCoverage()
        coverage.append(
            AcquisitionTiming(
                runID: runID, scanSequence: 3, qualityOfService: .userInitiated,
                requestedPeriodSeconds: 0.5, achievedPeriodSeconds: 0.5,
                scanWorkSeconds: 0, resolutionDelaySeconds: 0, sampling: fixed))
        store.append(
            RecentActivityUnit(
                runID: runID, baseline: 2, final: 3, start: 2, end: 3, scope: .allProcesses,
                records: [], crossings: [], excluded: 0, acquisition: coverage))
        let after = try #require(store.snapshot()).acquisitionCoverage
        #expect(after.scanCount == 2)
        #expect(after.overrunCount == 0)
        #expect(after.minimumRequestedPeriodSeconds == 0.25)
        #expect(after.maximumRequestedPeriodSeconds == 0.5)
        #expect(after.sampling.modes == [.adaptive, .fixed])
        #expect(after.sampling.overrideActivations.isEmpty)
        #expect(after.sampling.overrideSeconds == ["lifecycle": 0.6])
        #expect(after.sampling.policyChangeCount == 1)
        #expect(after.sampling.latest?.mode == .fixed)
        #expect(before.acquisitionCoverage.sampling.overrideSeconds == ["lifecycle": 1])
    }
}

private func samplingTiming(
    _ scan: CounterScan, requested: Double, achieved: Double?, sampling: SamplingCoverage
) -> AcquisitionTiming {
    AcquisitionTiming(
        runID: scan.id.runID, scanSequence: scan.id.sequence, qualityOfService: .userInitiated,
        requestedPeriodSeconds: requested, achievedPeriodSeconds: achieved,
        scanWorkSeconds: 0, resolutionDelaySeconds: 0, sampling: sampling)
}

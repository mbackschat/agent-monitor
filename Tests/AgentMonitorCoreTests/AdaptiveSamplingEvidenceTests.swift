import Testing

@testable import AgentMonitorCore

@Suite struct AdaptiveSamplingEvidenceTests {
    private func observation(_ pid: Int32 = 1) -> AdaptiveSamplingEvidence.Observation {
        .init(pid: pid, identity: ProcessIdentity(pid: pid, startMicroseconds: 1), birth: -100)
    }

    @Test func queuedRefreshPreservesNegativeUntilActualInvalidation() {
        var evidence = AdaptiveSamplingEvidence()
        var value = observation()
        value.resolution = .negative
        _ = evidence.ingest([value], listedAt: 0, closedAt: 0)
        value.resolution = nil
        value.read = .failure(code: 1, verified: true)
        #expect(!evidence.ingest([value], listedAt: 1, closedAt: 1).uncertain)
        value.invalidated = true
        #expect(evidence.ingest([value], listedAt: 2, closedAt: 2).uncertain)
    }

    @Test func unknownChildCountsButOwnNegativeAndVerifiedHelpersDoNot() {
        var evidence = AdaptiveSamplingEvidence()
        var parent = observation(1)
        parent.resolution = .negative
        _ = evidence.ingest([parent], listedAt: 0, closedAt: 0)
        var child = observation(2)
        child.resolution = .pending
        var negative = observation(3)
        negative.resolution = .negative
        var helper = observation(4)
        helper.provenHelper = true
        var otherUser = observation(5)
        otherUser.inScope = false
        let arrival = evidence.ingest([parent, child, negative, helper, otherUser], listedAt: 1, closedAt: 1)
        #expect(arrival.aggregate.arrivals == 1)
        #expect(arrival.aggregate.event)
        let departure = evidence.ingest([parent], listedAt: 2, closedAt: 2)
        #expect(departure.aggregate.event)
        #expect(!evidence.ingest([parent], listedAt: 3, closedAt: 3).aggregate.event)
    }

    @Test func unverifiedArrivalIsCountedOnceThenAbsenceRetiresHold() {
        var evidence = AdaptiveSamplingEvidence()
        _ = evidence.ingest([], listedAt: 0, closedAt: 0)
        var value = observation()
        value.identity = nil
        value.read = .failure(code: 3, verified: false)
        let failed = evidence.ingest([value], listedAt: 1, closedAt: 1)
        #expect(failed.aggregate.arrivals == 1)
        #expect(failed.uncertain)
        value = observation()
        let verified = evidence.ingest([value], listedAt: 2, closedAt: 2)
        #expect(verified.aggregate.arrivals == 0)
        #expect(verified.aggregate.recovery)
        #expect(!verified.uncertain)
        #expect(!evidence.ingest([], listedAt: 3, closedAt: 3).uncertain)
    }

    @Test(arguments: [false, true])
    func persistentRelaxationRequiresExactIdentityAndFiveSeconds(relax: Bool) {
        var evidence = AdaptiveSamplingEvidence(relaxPersistentFailures: relax)
        var value = observation()
        value.read = .failure(code: 1, verified: true)
        #expect(evidence.ingest([value], listedAt: 0, closedAt: 0).uncertain)
        #expect(evidence.ingest([value], listedAt: 4, closedAt: 4).uncertain)
        let third = evidence.ingest([value], listedAt: 5, closedAt: 5)
        #expect(third.uncertain == !relax)
        #expect(third.persistentlyUnreadable == (relax ? 1 : 0))
        value.identity = ProcessIdentity(pid: 1, startMicroseconds: 2)
        #expect(evidence.ingest([value], listedAt: 6, closedAt: 6).uncertain)
        #expect(evidence.ingest([], listedAt: 7, closedAt: 7, listingSucceeded: false).uncertain)
    }

    @Test func verifiedReplacementAfterUnreadableScanIsStillAnArrival() {
        var evidence = AdaptiveSamplingEvidence()
        var value = observation()
        _ = evidence.ingest([value], listedAt: 0, closedAt: 0)
        value.identity = nil
        value.read = .failure(code: 3, verified: false)
        _ = evidence.ingest([value], listedAt: 1, closedAt: 1)
        value.identity = ProcessIdentity(pid: 1, startMicroseconds: 2)
        value.read = .available
        let replacement = evidence.ingest([value], listedAt: 2, closedAt: 2)
        #expect(replacement.aggregate.arrivals == 1)
        #expect(!replacement.aggregate.recovery)
    }

    @Test func youngClassificationUsesCounterObservationRatherThanScanCompletion() {
        var ledger = CounterLedger()
        var value = sample(1, at: 0, cpu: 0)
        value.startedAt = 0
        _ = ledger.ingest([value], listedAt: 0)
        value.sampledAt = 60
        value.cpuSeconds = 1
        let scan = ledger.ingest([value], listedAt: 59, scanSeconds: 2)
        var evidence = AdaptiveSamplingEvidence()
        let observed = AdaptiveSamplingEvidence.Observation(pid: 1, identity: value.identity, birth: 0)
        let result = evidence.ingest(
            [observed], contributions: scan.contributions, listedAt: 59, closedAt: 61)
        #expect(result.aggregate.youngCPU == 1)
    }

    @Test func unverifiedFailuresNeverQualifyAndChangedFailuresRestartTheStreak() {
        var evidence = AdaptiveSamplingEvidence(relaxPersistentFailures: true)
        var value = observation()
        value.read = .failure(code: 1, verified: false)
        for time in [0.0, 5, 10] {
            #expect(evidence.ingest([value], listedAt: time, closedAt: time).uncertain)
        }
        value.read = .failure(code: 1, verified: true)
        #expect(evidence.ingest([value], listedAt: 11, closedAt: 11).uncertain)
        _ = evidence.ingest([value], listedAt: 15, closedAt: 15)
        #expect(!evidence.ingest([value], listedAt: 16, closedAt: 16).uncertain)
        value.read = .failure(code: 2, verified: true)
        #expect(evidence.ingest([value], listedAt: 17, closedAt: 17).uncertain)
        _ = evidence.ingest([value], listedAt: 22, closedAt: 22)
        #expect(!evidence.ingest([value], listedAt: 23, closedAt: 23).uncertain)
        value.invalidated = true
        #expect(evidence.ingest([value], listedAt: 24, closedAt: 24).uncertain)
    }

    @Test func listingRecoverySuppliesBriefOverride() {
        var evidence = AdaptiveSamplingEvidence()
        let value = observation()
        _ = evidence.ingest([value], listedAt: 0, closedAt: 0)
        #expect(evidence.ingest([], listedAt: 1, closedAt: 1, listingSucceeded: false).uncertain)
        let recovered = evidence.ingest([value], listedAt: 2, closedAt: 2)
        #expect(!recovered.uncertain)
        #expect(recovered.aggregate.recovery)
    }

    @Test(arguments: [AdaptiveSamplingEvidence.Resolution.pending, .point, .uncertain, .supported])
    func allNonNegativeEvidenceLevelsQualify(resolution: AdaptiveSamplingEvidence.Resolution) {
        var evidence = AdaptiveSamplingEvidence()
        var ledger = CounterLedger()
        _ = evidence.ingest([], listedAt: 0, closedAt: 0)
        _ = ledger.ingest([], listedAt: 0)
        var value = sample(1, at: 1, cpu: 0.25)
        value.startedAt = 0.5
        let counters = ledger.ingest([value], listedAt: 1)
        let observation = AdaptiveSamplingEvidence.Observation(
            pid: 1, identity: value.identity, birth: 0.5,
            resolution: resolution)
        let result = evidence.ingest(
            [observation], contributions: counters.contributions, listedAt: 1, closedAt: 1)
        #expect(result.aggregate.arrivals == 1)
        #expect(result.aggregate.cpu == 0.25)
        #expect(result.aggregate.youngCPU == 0.25)
    }

    @Test func retainedHelperProofSurvivesParentDepartureButNotPIDReuse() {
        var evidence = AdaptiveSamplingEvidence()
        var parent = observation(1)
        parent.provenHelper = true
        var child = observation(2)
        child.provenHelper = true
        _ = evidence.ingest([parent, child], listedAt: 0, closedAt: 0)
        let retained = evidence.ingest([child], listedAt: 1, closedAt: 1)
        #expect(!retained.aggregate.event)
        child.identity = ProcessIdentity(pid: 2, startMicroseconds: 2)
        child.provenHelper = false
        child.resolution = .supported
        #expect(evidence.ingest([child], listedAt: 2, closedAt: 2).aggregate.arrivals == 1)
    }
}

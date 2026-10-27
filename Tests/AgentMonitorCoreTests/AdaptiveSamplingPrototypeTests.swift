import Testing

@Suite struct AdaptiveSamplingPrototypeTests {
    @Test(arguments: [0.625, 12.5, 37.5, 60.0])
    func ratesUseWholeSupportEvenWhenLongerThanLookback(period: Double) {
        var policy = AdaptiveSamplingPrototype(maximum: period)
        let result = policy.observe(.init(opening: 0, closing: period, cpu: 0.002 * period))
        #expect(abs(result.recent.cpu - 0.002) < 1e-12)
        #expect(abs(result.recent.span - period) < 1e-12)
        #expect(!result.reasons.contains(.excess))
    }

    @Test func twoIntervalsUseOneAndAQuarterSeconds() {
        var policy = AdaptiveSamplingPrototype(maximum: 0.625)
        _ = policy.observe(.init(opening: 0, closing: 0.625, cpu: 0.00125))
        let result = policy.observe(.init(opening: 0.625, closing: 1.25, cpu: 0.00125))
        #expect(result.recent.span == 1.25)
        #expect(abs(result.recent.cpu - 0.002) < 1e-12)
    }

    @Test func uncertaintyFreezesAndReleaseDoesNotSpendHeldTime() {
        var policy = AdaptiveSamplingPrototype(maximum: 0.625)
        _ = policy.observe(.init(opening: 0, closing: 30))
        let before = policy.base
        #expect(before > 0.1)
        let held = policy.observe(.init(opening: 30, closing: 60), uncertain: true)
        #expect(held.requested == 0.1)
        #expect(held.base == before)
        let released = policy.observe(.init(opening: 60, closing: 90))
        #expect(released.base == before)
        let next = policy.observe(.init(opening: 90, closing: 91))
        #expect(abs(next.base - before - 0.525 / 60) < 1e-12)
    }

    @Test func oldSteadyBusyWorkerStaysFastAfterMeanCatchesUp() {
        var policy = AdaptiveSamplingPrototype(maximum: 0.625)
        var decision = policy.observe(.init(opening: 0, closing: 1, cpu: 4))
        for second in 2...180 {
            decision = policy.observe(.init(opening: Double(second - 1), closing: Double(second), cpu: 4))
        }
        #expect(decision.requested == 0.1)
        #expect(decision.reasons == [.sustained])
        #expect(decision.base == 0.625)
    }

    @Test func maxChangesPreserveBaseAndHistoryButRestartClearsControlHistory() {
        var policy = AdaptiveSamplingPrototype(maximum: 0.25)
        _ = policy.observe(.init(opening: 0, closing: 60))
        #expect(policy.base == 0.25)
        policy.changeMaximum(1)
        #expect(policy.base == 0.25)
        #expect(policy.history.count == 1)
        policy.changeMaximum(0.2)
        #expect(policy.base == 0.2)
        policy.restart(minimum: 0.15, window: 10, enabled: true, at: 60)
        #expect(policy.base == 0.15)
        #expect(policy.history.isEmpty)
    }

    @Test func offUsesMaximumExceptDuringInspection() {
        var policy = AdaptiveSamplingPrototype(maximum: 0.625)
        policy.enabled = false
        let off = policy.observe(.init(opening: 0, closing: 1, cpu: 4, event: true), uncertain: true)
        #expect(off.requested == 0.625)
        #expect(off.reasons.isEmpty)
        let inspected = policy.observe(.init(opening: 1, closing: 2), inspection: true)
        #expect(inspected.requested == 0.1)
        #expect(inspected.reasons == [.inspection])
    }

    @Test func lifecycleAndRecoveryOverridesExpireWithoutRestartingBase() {
        var policy = AdaptiveSamplingPrototype(maximum: 0.625)
        _ = policy.observe(.init(opening: 0, closing: 60))
        let event = policy.observe(.init(opening: 60, closing: 60.1, event: true))
        #expect(event.requested == 0.1)
        #expect(event.base == 0.625)
        let released = policy.observe(.init(opening: 60.1, closing: 61.2))
        #expect(released.requested == 0.625)
        let recovered = policy.observe(.init(opening: 31.2, closing: 61.3, cpu: 0.0602, recovery: true))
        #expect(recovered.reasons.contains(.recovery))
        #expect(abs(recovered.recent.cpu - 0.002) < 1e-12)
    }

    @Test func historyRemainsBoundedAndLatestAggregateSurvivesLongGap() {
        var policy = AdaptiveSamplingPrototype(maximum: 60, window: 300)
        for tick in 1...3_100 {
            _ = policy.observe(.init(opening: Double(tick - 1) / 10, closing: Double(tick) / 10))
        }
        #expect(policy.history.count <= 3_002)
        policy.restart(minimum: 0.1, window: 1, enabled: true, at: 310)
        let latest = policy.observe(.init(opening: 310, closing: 370, cpu: 0.12))
        #expect(latest.recent.span == 60)
        #expect(abs(latest.recent.cpu - 0.002) < 1e-12)
    }

    @Test func restartingUsesSettingBoundaryForRampButFullCounterSupportForRates() {
        var policy = AdaptiveSamplingPrototype(maximum: 0.625)
        policy.restart(minimum: 0.1, window: 60, enabled: true, at: 100)
        let value = policy.observe(.init(opening: 0, closing: 100.1, cpu: 0.2))
        #expect(abs(value.base - (0.1 + 0.525 * 0.1 / 60)) < 1e-9)
        #expect(value.recent.span == 100.1)
    }

    @Test func openingAcceleratesWithoutErasingHistoryAndClosingOnlyChangesBounds() {
        var policy = AdaptiveSamplingPrototype(maximum: 0.625)
        _ = policy.observe(.init(opening: 0, closing: 60))
        policy.openPanel(maximum: 0.25)
        #expect(policy.base == 0.1)
        #expect(policy.history.count == 1)
        policy.changeMaximum(0.625)
        #expect(policy.base == 0.1)
        #expect(policy.history.count == 1)
    }

    @Test func thresholdsAndEventExpiryHaveExplicitBoundaries() {
        for (cpu, expected) in [(0.1.nextDown, false), (0.1, true)] {
            var policy = AdaptiveSamplingPrototype(maximum: 0.625)
            #expect(
                policy.observe(.init(opening: 0, closing: 1, cpu: cpu)).reasons.contains(.sustained)
                    == expected)
        }
        var policy = AdaptiveSamplingPrototype(maximum: 0.625)
        #expect(policy.observe(.init(opening: 0, closing: 1, event: true)).reasons.contains(.lifecycle))
        #expect(!policy.observe(.init(opening: 1, closing: 2)).reasons.contains(.lifecycle))
    }

    @Test func youngEvidenceExpiresOnlyAfterItsOwnRollingWindow() {
        var policy = AdaptiveSamplingPrototype(maximum: 0.625)
        var result = policy.observe(.init(opening: 0, closing: 1, cpu: 0.024, youngCPU: 0.024))
        for second in 2...180 {
            result = policy.observe(
                .init(
                    opening: Double(second - 1), closing: Double(second),
                    cpu: 0.024, youngCPU: second <= 60 ? 0.024 : 0))
            if second == 61 { #expect(result.rolling.youngCPU > 0.020) }
            if second == 120 { #expect(result.rolling.youngCPU == 0) }
        }
        #expect(result.requested == 0.625)
    }
}

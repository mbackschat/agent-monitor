import Testing

private func establishedIdleLives(until end: Double) -> [AdaptiveWorkloadLife] {
    let sessions = [
        sessionA, sessionB, "33333333-3333-4333-8333-333333333333", "44444444-4444-4444-8444-444444444444",
    ]
    return (0..<16).map {
        AdaptiveWorkloadLife(
            pid: Int32(100 + $0), birth: -120, end: end, cpu: .steady(0.0015),
            parentPID: $0.isMultiple(of: 4) ? 1 : Int32(100 + ($0 / 4) * 4), sessionID: sessions[$0 / 4])
    }
}

@Suite struct AdaptiveSamplingWorkloadTests {
    @Test(arguments: [0.25, 0.625])
    func establishedSessionsReachMaximumAndSaveAtLeastHalfTheScans(maximum: Double) async throws {
        var lives = establishedIdleLives(until: 240)
        lives += (0..<79).map { index in
            AdaptiveWorkloadLife(
                pid: Int32(200 + index), birth: 1 + Double(index) * 3, end: 1.2 + Double(index) * 3,
                resolution: .negative, readOffset: 0)
        }
        lives += [AdaptiveWorkloadLife(pid: 500, birth: 0, end: 240, cpu: .steady(0.01), helper: true)]
        let scenario = AdaptiveWorkloadScenario(name: "established-idle", lives: lives, maximum: maximum)
        let adaptive = try await runAdaptiveWorkload(scenario, arm: .adaptive)
        let baseline = try await runAdaptiveWorkload(scenario, arm: .fixedMinimum)
        let range = 90.0..<210.0
        #expect(adaptive.scans(in: range) <= baseline.scans(in: range) / 2)
        #expect(adaptive.fraction(in: range) { abs($0.decision.requested - maximum) < 1e-9 } >= 0.95)
        for life in lives.prefix(16) {
            let contributions = adaptive.contributions.filter { $0.process == life.identity }
            #expect(!contributions.isEmpty)
            #expect(contributions.allSatisfy { $0.attribution.threadID == life.sessionID })
        }
        #expect(abs(adaptive.partition(scenario).initial - 0.034 * scenario.scanSeconds) < 1e-7)
    }

    @Test func firstScanBirthAndDelayedFirstReadHaveIndependentInitialLoss() async throws {
        let lives = [
            AdaptiveWorkloadLife(pid: 1, birth: 0.001, end: 1, cpu: .steady(1)),
            AdaptiveWorkloadLife(pid: 2, birth: -10, end: 1, cpu: .steady(1), failures: 0..<0.5),
        ]
        let scenario = AdaptiveWorkloadScenario(name: "baseline-edges", lives: lives, horizon: 2)
        let result = try await runAdaptiveWorkload(scenario, arm: .adaptive)
        let first = try #require(result.firstReads[lives[1].identity])
        #expect(abs(result.partition(scenario).initial - first) < 1e-7)
        #expect((result.accepted[lives[0].identity] ?? 0) > 0.8)
    }

    @Test func oldBusyWorkerStaysFastAndFailedListingDrainsThenTerminates() async throws {
        let life = AdaptiveWorkloadLife(
            pid: 1, birth: -120, end: 240, cpu: .burst(from: 80, until: 220, rate: 4))
        var scenario = AdaptiveWorkloadScenario(name: "old-busy", lives: [life])
        let result = try await runAdaptiveWorkload(scenario, arm: .adaptive)
        let busy = result.ticks.filter { (85..<215).contains($0.start) }
        #expect(!busy.isEmpty)
        #expect(busy.allSatisfy { $0.requested == 0.1 && $0.decision.reasons.contains(.sustained) })
        scenario.failedListingAt = 90
        let failed = try await runAdaptiveWorkload(scenario, arm: .adaptive)
        #expect(try #require(failed.ticks.last).start < 90)
        #expect(failed.contributions.reduce(0) { $0 + $1.cpuSeconds } > 30)
    }

    @Test func scanOverrunDoesNotCatchUpOrPretendRequestedEqualsAchieved() async throws {
        let scenario = AdaptiveWorkloadScenario(name: "overrun", lives: [], horizon: 4, scanSeconds: 0.15)
        let result = try await runAdaptiveWorkload(scenario, arm: .fixedMinimum)
        for pair in zip(result.ticks, result.ticks.dropFirst()) {
            #expect(abs(pair.1.start - pair.0.start - 0.15) < 1e-9)
            #expect(pair.0.requested == 0.1)
        }
    }

    @Test func identityDiscoveryDoesNotRequireReadableCPU() async throws {
        let life = AdaptiveWorkloadLife(pid: 1, birth: 0.01, end: 1, failures: 0..<2)
        let scenario = AdaptiveWorkloadScenario(name: "identity-without-counters", lives: [life], horizon: 2)
        let result = try await runAdaptiveWorkload(scenario, arm: .adaptive)
        #expect(result.identities == [life.identity])
        #expect(result.lastReads.isEmpty)
        #expect(result.partition(scenario).unseen == 0)
        #expect(abs(result.partition(scenario).unreadable - 0.99) < 1e-9)
    }
}

import Testing

@testable import AgentMonitorCore

@Suite struct ProductionAdaptiveWorkloadTests {
    @Test func establishedIdleAgentsRelaxThenResumedCPUUsesTheMinimumWithoutLosingContributions() async throws
    {
        var lives = productionIdleAgents()
        lives[1].cpu = .burst(from: 10, until: 18, rate: 2)
        let scenario = productionScenario("production-resumed-agent", lives: lives)
        let result = try await runAdaptiveWorkload(scenario, arm: .adaptive, productionController: true)
        expectIdleMaximum(result, maximum: scenario.maximum)
        expectMinimumPeriods(result, in: 11..<17)
        #expect(result.sampling.overrideActivations["sustained", default: 0] > 0)
        #expect(result.sampling.overrideSeconds["sustained", default: 0] > 5)
        #expect(result.accepted[lives[1].identity, default: 0] > 15)
        expectExactSessions(result, lives: lives)
    }

    @Test func birthBurstAcceleratesAndKeepsTheChildsOwnSessionAndNewbornCPU() async throws {
        let worker = AdaptiveWorkloadLife(
            pid: 500, birth: 10.017, end: 14.017, cpu: .steady(2), parentPID: 100,
            sessionID: sessionB)
        let lives = productionIdleAgents() + [worker]
        let scenario = productionScenario("production-birth-burst", lives: lives)
        let result = try await runAdaptiveWorkload(scenario, arm: .adaptive, productionController: true)
        expectIdleMaximum(result, maximum: scenario.maximum)
        expectMinimumPeriods(result, in: 11..<13)
        #expect(result.sampling.overrideActivations["lifecycle", default: 0] > 0)
        let contributions = result.contributions.filter { $0.process == worker.identity }
        #expect(contributions.contains { $0.newbornOpening && $0.verifiedBirth == worker.birth })
        #expect(result.accepted[worker.identity, default: 0] > 0)
        expectExactSessions(result, lives: lives)
    }

    @Test func readGapHoldsTheMinimumAndRecoversOriginalCPUIntervalsOnce() async throws {
        var lives = productionIdleAgents()
        lives[1].failures = 10..<12
        let scenario = productionScenario("production-counter-recovery", lives: lives)
        let result = try await runAdaptiveWorkload(scenario, arm: .adaptive, productionController: true)
        expectIdleMaximum(result, maximum: scenario.maximum)
        expectMinimumPeriods(result, in: 10.75..<12.75)
        #expect(result.sampling.overrideActivations["uncertainty"] == 1)
        #expect(result.sampling.overrideActivations["recovery"] == 1)
        #expect(result.sampling.overrideSeconds["uncertainty", default: 0] > 1)
        #expect(result.sampling.overrideSeconds["recovery", default: 0] >= 0.9)
        let recovered = result.contributions.filter {
            $0.process == lives[1].identity && $0.startedAt < 10 && $0.endedAt >= 12
        }
        #expect(recovered.count == 1)
        #expect((recovered.first?.missingReadIntervalCount ?? 0) > 0)
        #expect((recovered.first?.cpuSeconds ?? 0) > 0)
        expectExactSessions(result, lives: lives)
    }
}

private func productionIdleAgents() -> [AdaptiveWorkloadLife] {
    (0..<4).map { (index: Int) -> AdaptiveWorkloadLife in
        let parent: Int32 = index.isMultiple(of: 2) ? 1 : Int32(99 + index)
        let session = index < 2 ? sessionA : sessionB
        return AdaptiveWorkloadLife(
            pid: Int32(100 + index), birth: -120, end: 24, cpu: .steady(0.0015),
            parentPID: parent, sessionID: session)
    }
}

private func productionScenario(_ name: String, lives: [AdaptiveWorkloadLife]) -> AdaptiveWorkloadScenario {
    AdaptiveWorkloadScenario(name: name, lives: lives, horizon: 24, maximum: 0.5, window: 2)
}

private func expectIdleMaximum(_ result: AdaptiveWorkloadResult, maximum: Double) {
    let periods = acquisitionPeriods(result, in: 4..<8)
    #expect(!periods.isEmpty)
    #expect(periods.allSatisfy { abs($0 - maximum) < 1e-8 })
}

private func expectMinimumPeriods(_ result: AdaptiveWorkloadResult, in range: Range<Double>) {
    let periods = acquisitionPeriods(result, in: range)
    #expect(!periods.isEmpty)
    #expect(periods.allSatisfy { abs($0 - 0.1) < 1e-8 })
}

private func acquisitionPeriods(_ result: AdaptiveWorkloadResult, in range: Range<Double>) -> [Double] {
    zip(result.ticks, result.ticks.dropFirst()).compactMap { first, next in
        guard range.contains(first.start), range.contains(next.start) else { return nil }
        return next.start - first.start
    }
}

private func expectExactSessions(_ result: AdaptiveWorkloadResult, lives: [AdaptiveWorkloadLife]) {
    for life in lives {
        let contributions = result.contributions.filter { $0.process == life.identity }
        #expect(!contributions.isEmpty)
        #expect(
            contributions.allSatisfy {
                $0.attribution.provider == .codex && $0.attribution.threadID == life.sessionID
            })
    }
}

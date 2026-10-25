import Testing

@testable import AgentMonitorCore

@Test func profileAggregatesExactTotalsAndNearestRankPercentiles() throws {
    let profile = PipelineProfile(sampleLimit: 3)
    for value in [3.0, 1, 2] {
        profile.record(.nativeSampling, cpu: value / 10, wall: value)
    }
    let stats = try #require(profile.snapshot().stages["nativeSampling"])
    #expect(stats.count == 3)
    #expect(abs(stats.cpu.totalSeconds - 0.6) < 1e-9)
    #expect(stats.wall.totalSeconds == 6)
    #expect(stats.wall.p50Seconds == 2)
    #expect(stats.wall.p99Seconds == 3)
    #expect(stats.wall.maximumSeconds == 3)
    #expect(stats.percentilesComplete)
    profile.record(.nativeSampling, cpu: 1, wall: 10)
    let capped = try #require(profile.snapshot().stages["nativeSampling"])
    #expect(capped.count == 4)
    #expect(capped.wall.totalSeconds == 16)
    #expect(capped.wall.maximumSeconds == 10)
    #expect(!capped.percentilesComplete)
    #expect(capped.wall.p50Seconds == nil)
}

@Test func profileRecordsThrowingStagesAndFinalizesWorkerBeforeCloseReturns() async throws {
    struct Expected: Error {}
    let profile = PipelineProfile()
    #expect(throws: Expected.self) {
        try Optional(profile).measure(.counterAccounting) { throw Expected() }
    }
    let worker = SerialBlockingWorker(
        name: "profile fixture", initial: 0, profile: profile, role: .acquisition)
    _ = try await worker.perform { value in value += 1 }
    await worker.close()
    let result = profile.snapshot()
    #expect(result.stages["counterAccounting"]?.count == 1)
    #expect(result.workers["acquisition"]?.jobs.count == 1)
    #expect(result.workers["acquisition"]?.threadCPUSeconds != nil)
}

@Test func profileRetainsWorkerCPUWithoutJobs() async throws {
    let profile = PipelineProfile()
    let worker = SerialBlockingWorker(
        name: "idle profile fixture", initial: 0, profile: profile, role: .providers)
    await worker.close()
    let statistics = try #require(profile.snapshot().workers["providers"])
    #expect(statistics.threadCPUSeconds != nil)
    #expect(statistics.jobs.count == 0)
    #expect(statistics.jobs.wall.p50Seconds == nil)
}

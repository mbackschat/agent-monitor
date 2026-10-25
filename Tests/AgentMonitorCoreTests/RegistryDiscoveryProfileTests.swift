import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

@Test func registryAdmissionReasonsPreserveCadenceAndCountOnlyAdmissions() {
    let profile = PipelineProfile()
    var instrumented = SessionRegistryCadence()
    var uninstrumented = SessionRegistryCadence()
    let first = sample(42).identity
    let second = sample(43).identity
    let third = sample(44).identity
    let fourth = sample(45).identity
    let attempts: [(AgentProvider, Double, Set<ProcessIdentity>, Bool)] = [
        (.claude, 100, [first], true),
        (.claude, 100, [first], false),
        (.claude, 101, [], false),
        (.claude, 110, [first, second], true),
        (.claude, 111, [first], false),
        (.claude, 170, [first, second, third], true),
        (.claude, 169, [first, second, third, fourth], true),
        (.claude, 170, [first, second, third, fourth], false),
        (.codex, 170, [first], true),
    ]
    for (provider, seconds, runtimes, expected) in attempts {
        let at = Date(timeIntervalSince1970: seconds)
        let counted = instrumented.due(provider, runtimes: runtimes, at: at, profile: profile)
        let unchanged = uninstrumented.due(provider, runtimes: runtimes, at: at)
        #expect(counted == expected)
        #expect(unchanged == expected)
    }
    var expected = Dictionary(
        uniqueKeysWithValues: PipelineProfile.Counter.allCases.map { ($0.rawValue, UInt64(0)) })
    expected["registryInitialAdmissions"] = 2
    expected["registryNewRuntimeAdmissions"] = 1
    expected["registryPeriodicAdmissions"] = 1
    expected["registryClockResetAdmissions"] = 1
    #expect(profile.snapshot().counters == expected)
}

private final class RegistryProfileFixture: ProcessReading, SessionRegistryReading, SamplingClock, Sendable {
    struct ListingFailure: Error {}
    let fail: Bool
    let listings = Mutex(0)
    let identityChecks = Mutex(0)

    init(fail: Bool = false) { self.fail = fail }
    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot { diagnosisScan([], at: 0) }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata { ProcessMetadata() }
    func isCurrent(_ sample: ProcessSample) -> Bool {
        identityChecks.withLock { $0 += 1 }
        return sample.identity.pid != 43
    }
    func output(of query: SessionRegistryQuery) throws -> Data {
        listings.withLock { $0 += 1 }
        if fail { throw ListingFailure() }
        return Data("[]".utf8)
    }
    func monotonicNow() -> Double { 0 }
    func now() -> Date { Date(timeIntervalSince1970: 0) }
}

@Test(.timeLimit(.minutes(1)), arguments: [false, true])
func registryProfileCountsExecutedCandidatesAndCompletedResults(fail: Bool) async throws {
    let profile = PipelineProfile()
    let enrichment = PipelineEnrichment(profile: profile)
    let fixture = RegistryProfileFixture(fail: fail)
    let query = try #require(AttributionAdapters.builtIn.sessionRegistry(for: .claude))
    defer { enrichment.finish() }
    enrichment.requestRegistries([
        RegistryRefreshRequest(provider: .claude, query: query, samples: [sample(99)])
    ])
    enrichment.requestRegistries([
        RegistryRefreshRequest(
            provider: .claude, query: query, samples: [sample(42), sample(43), sample(44)])
    ])
    #expect(profile.snapshot().counters["registryRequestedCandidates"] == 0)
    let worker = Task {
        try await enrichment.refreshRegistries(
            reader: fixture, registry: fixture, clock: fixture, checking: {})
    }
    var results = enrichment.takeResults().1
    while results.isEmpty {
        await Task.yield()
        results = enrichment.takeResults().1
    }
    enrichment.finish()
    try await worker.value
    let result = try #require(results.first)
    #expect(results.count == 1)
    #expect(result.verified == [sample(42).identity, sample(44).identity])
    #expect((result.output == nil) == fail)
    #expect(fixture.listings.withLock { $0 } == 1)
    #expect(fixture.identityChecks.withLock { $0 } == 3)
    let counters = profile.snapshot().counters
    #expect(counters["registryRequestedCandidates"] == 3)
    #expect(counters["registryVerifiedCandidates"] == 2)
    #expect(counters["registryCompletedListings"] == 1)
}

@Test func stoppedRegistryDiscoveryDoesNotCountRequestsThatNeverStart() async throws {
    let profile = PipelineProfile()
    let enrichment = PipelineEnrichment(profile: profile)
    let fixture = RegistryProfileFixture()
    let query = try #require(AttributionAdapters.builtIn.sessionRegistry(for: .claude))
    enrichment.finish()
    enrichment.requestRegistries([
        RegistryRefreshRequest(provider: .claude, query: query, samples: [sample(42)])
    ])
    try await enrichment.refreshRegistries(reader: fixture, registry: fixture, clock: fixture, checking: {})
    #expect(fixture.listings.withLock { $0 } == 0)
    #expect(fixture.identityChecks.withLock { $0 } == 0)
    #expect(profile.snapshot().counters.values.allSatisfy { $0 == 0 })
}

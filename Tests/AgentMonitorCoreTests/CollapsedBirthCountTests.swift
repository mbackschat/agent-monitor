import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct CollapsedBirthCountTests {
    @Test func laterBirthsTightenCountsWithoutTreatingAbsenceAsExit() throws {
        var fixture = Fixture()
        try fixture.batch([(1, 10), (2, 20)], at: 100)
        try fixture.batch([(1, 10), (3, 150)], at: 200)
        let mixed = try #require(fixture.window.summary.collapsedContributions.first)
        #expect(mixed.processCount == LifetimeCountRange(minimum: 3, maximum: 4))
        #expect(mixed.workerCount == mixed.processCount)
        try fixture.batch([(4, 250)], at: 300)
        let final = try #require(fixture.window.summary.collapsedContributions.first)
        #expect(final.processCount == LifetimeCountRange(minimum: 4, maximum: 5))
        #expect(final.category.categoryDetailsRetained)
        #expect(fixture.window.payloadSize == fixture.window.recountedPayloadSize)
    }

    @Test(arguments: [UInt64?.none, 0, 100, 101, 201])
    func onlyStrictlyLaterVerifiedBirthsProveDisjointness(birth: UInt64?) throws {
        var fixture = Fixture()
        try fixture.batch([(1, 10)], at: 100)
        try fixture.batch([(2, birth)], at: 200)
        let result = try #require(fixture.window.summary.collapsedContributions.first)
        #expect(result.processCount.minimum == (birth == 101 ? 2 : 1))
        #expect(result.processCount.maximum == 2)
    }

    @Test func missingObservationTicksPreventBirthProof() throws {
        var fixture = Fixture()
        try fixture.batch([(1, 10)], at: 100, includeObservationTicks: false)
        try fixture.batch([(2, 150)], at: 200)
        let result = try #require(fixture.window.summary.collapsedContributions.first)
        #expect(result.processCount == LifetimeCountRange(minimum: 1, maximum: 2))
    }

    @Test(arguments: [true, false])
    func mergedWindowsPreserveBoundaryAndIndependentValueCopies(knownBoundary: Bool) throws {
        var fixture = Fixture()
        try fixture.batch([(1, 10)], at: 100, includeObservationTicks: knownBoundary)
        var first = fixture.window
        fixture.window = AccountingWindow(baseline: fixture.lastScan)
        try fixture.batch([(2, 150)], at: 200)
        try first.merge(fixture.window)
        // Independently collapsed populations still use max/sum; later admission can prove new births.
        #expect(first.summary.collapsedContributions.first?.processCount.minimum == 1)
        fixture.window = first
        try fixture.batch([(3, 250)], at: 300)
        #expect(
            fixture.window.summary.collapsedContributions.first?.processCount.minimum
                == (knownBoundary ? 2 : 1))
        #expect(first.summary.collapsedContributions.first?.processCount.minimum == 1)
    }

    @Test func newbornChurnRetainsExactCountsWithConstantCollapsedStorage() throws {
        var fixture = Fixture()
        var initialSize: MonitoringPayloadSize?
        for batch in 0..<100 {
            let births = (0..<5).map { (Int32(batch * 5 + $0 + 1), UInt64?(UInt64(batch * 100 + 1))) }
            try fixture.observe(births, at: UInt64(batch * 100 + 50))
            try fixture.observe(births, at: UInt64(batch * 100 + 51))
            try fixture.collapse()
            let summary = fixture.window.summary
            let value = try #require(summary.collapsedContributions.first)
            #expect(
                value.processCount == LifetimeCountRange(minimum: (batch + 1) * 5, maximum: (batch + 1) * 5))
            #expect(value.workerCount == value.processCount)
            #expect(value.cpuSeconds == Double((batch + 1) * 5))
            #expect(value.intervalCount == (batch + 1) * 5)
            #expect(value.maximumFootprint?.bytes == UInt64((batch + 1) * 5))
            #expect(summary.collapsedContributions.count == 1)
            if let initialSize { #expect(fixture.window.payloadSize == initialSize) }
            initialSize = fixture.window.payloadSize
        }
    }

    @Test func multipleDirectoryRunsDoNotMultiplyNewbornCounts() throws {
        var fixture = Fixture()
        try fixture.batch([(1, 10)], at: 100)
        try fixture.observe([(2, 150)], at: 200, cwd: "/one")
        try fixture.observe([(2, 150)], at: 201, cwd: "/two")
        try fixture.collapse()
        let value = try #require(fixture.window.summary.collapsedContributions.first)
        #expect(value.processCount == LifetimeCountRange(minimum: 2, maximum: 2))
        #expect(value.workerCount == value.processCount)
    }

    @Test func unknownTicksStayUnknownAfterReuseAndWindowMerge() throws {
        var fixture = Fixture()
        try fixture.observe([(1, 10)], at: 100, includeObservationTicks: false)
        var earlier = fixture.window
        fixture.window = AccountingWindow(baseline: fixture.lastScan)
        try fixture.observe([(1, 10)], at: 200)
        try earlier.merge(fixture.window)
        fixture.window = earlier
        try fixture.observe([(1, 10)], at: 201, cwd: "/other")
        try fixture.collapse()
        try fixture.batch([(2, 250)], at: 300)
        #expect(fixture.window.summary.collapsedContributions.first?.processCount.minimum == 1)
    }

    @Test func runtimesAndWorkersUseSeparateDisjointCounts() throws {
        var fixture = Fixture()
        try fixture.observe([(1, 10), (2, 20)], at: 100, runtimes: [1])
        try fixture.collapse()
        try fixture.observe([(3, 150), (4, 160)], at: 200, runtimes: [3])
        try fixture.collapse()
        let values = fixture.window.summary.collapsedContributions
        #expect(values.count == 2)
        for value in values {
            #expect(value.processCount == LifetimeCountRange(minimum: 2, maximum: 2))
            let count = value.category.isAgentRuntime == true ? 0 : 2
            #expect(value.workerCount == LifetimeCountRange(minimum: count, maximum: count))
        }
    }

    @Test func categoryReleasePreservesImprovedCountsAndExactResources() throws {
        var fixture = Fixture()
        try fixture.observe([(1, 10)], at: 100)
        try fixture.observe([(1, 10)], at: 101)
        try fixture.collapse()
        try fixture.observe([(2, 150)], at: 200)
        try fixture.observe([(2, 150)], at: 201)
        try fixture.collapse()
        let before = try #require(fixture.window.summary.collapsedContributions.first)
        fixture.window.compact(to: MonitoringPipelineLimits(pendingTextBytes: 1))
        let released = try #require(fixture.window.summary.collapsedContributions.first)
        #expect(!released.category.categoryDetailsRetained)
        #expect(released.processCount == before.processCount)
        #expect(released.workerCount == before.workerCount)
        #expect(released.cpuSeconds == before.cpuSeconds)
        #expect(released.intervalCount == before.intervalCount)
        #expect(released.maximumFootprint == before.maximumFootprint)
        try fixture.batch([(3, 250)], at: 300)
        fixture.window.compact(to: MonitoringPipelineLimits(pendingTextBytes: 1))
        let merged = try #require(fixture.window.summary.collapsedContributions.first)
        #expect(!merged.category.categoryDetailsRetained)
        #expect(merged.processCount == LifetimeCountRange(minimum: 2, maximum: 3))
        #expect(merged.cpuSeconds == before.cpuSeconds)
        #expect(merged.maximumFootprint?.bytes == 3)
    }

    private struct Fixture {
        var ledger = CounterLedger()
        var window: AccountingWindow
        var lastScan: CounterScan
        var tick = 0.0

        init() {
            lastScan = ledger.ingest([], listedAt: 0)
            window = AccountingWindow(baseline: lastScan)
        }

        mutating func batch(
            _ births: [(Int32, UInt64?)], at ticks: UInt64, includeObservationTicks: Bool = true
        ) throws {
            try observe(births, at: ticks, includeObservationTicks: includeObservationTicks)
            try collapse()
        }

        mutating func observe(
            _ births: [(Int32, UInt64?)], at ticks: UInt64, includeObservationTicks: Bool = true,
            cwd: String? = nil, runtimes: Set<Int32> = []
        ) throws {
            tick += 1
            let samples = births.map { pid, birth in
                var value = sample(pid, at: tick, cpu: tick, memory: UInt64(pid))
                value.startedAtTicks = birth
                value.sampledAtTicks = includeObservationTicks ? ticks : nil
                return value
            }
            let rows = samples.map {
                HeavyProcess(
                    process: $0.identity, executable: $0.executable, name: $0.name,
                    cpuPercent: nil, footprintBytes: $0.footprintBytes, cwd: cwd,
                    command: [String(repeating: "x", count: 2_000)], metadataStatus: .markerRead,
                    attribution: Attribution(
                        provider: .codex, evidence: .marker, context: .unverified,
                        threadID: sessionA, rootSessionID: nil, runtime: nil, terminal: nil,
                        runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []))
            }
            lastScan = ledger.ingest(samples, listedAt: tick)
            try window.append(
                lastScan, rows: rows,
                runtimes: Set(samples.filter { runtimes.contains($0.identity.pid) }.map(\.identity)))
        }

        mutating func collapse() throws {
            tick += 1
            lastScan = ledger.ingest([], listedAt: tick)
            try window.append(lastScan, rows: [])
            window.compact(to: MonitoringPipelineLimits(pendingTextBytes: 1_000))
        }
    }
}

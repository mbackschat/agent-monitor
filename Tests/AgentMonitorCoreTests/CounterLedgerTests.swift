import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct CounterLedgerTests {
    private func process(_ pid: Int32 = 10, at: Double, cpu: Double?, birth: Double = 10.5, start: UInt64 = 1)
        -> ProcessSample
    {
        var value = sample(pid, start: start, at: at, cpu: cpu)
        value.startedAt = birth
        return value
    }

    @Test(arguments: [1, 3]) func delayedFirstCounterKeepsOriginalPrebirthListing(failures: Int) throws {
        var ledger = CounterLedger()
        let initial = ledger.ingest([], listedAt: 10)
        for offset in 1...failures {
            _ = ledger.ingest([process(at: 10.0 + Double(offset), cpu: nil)], listedAt: 10.0 + Double(offset))
        }
        let final = ledger.ingest([process(at: 20, cpu: 2)], listedAt: 19)
        let delta = try #require(final.contributions.first)
        #expect(delta.id.opening == .newbornZero(listing: initial.id, verifiedBirth: 10.5))
        #expect(delta.cpuSeconds == 2)
        #expect(delta.observedSeconds == 10)
        #expect(delta.spansMissingScans)
    }

    @Test func latestPrebirthListingIsUsedRatherThanRunStart() throws {
        var ledger = CounterLedger()
        _ = ledger.ingest([], listedAt: 10)
        let preceding = ledger.ingest([], listedAt: 11)
        _ = ledger.ingest([], listedAt: 12)
        let result = ledger.ingest([process(at: 13, cpu: 1, birth: 11.5)], listedAt: 13)
        #expect(
            try #require(result.contributions.first).id.opening
                == .newbornZero(
                    listing: preceding.id, verifiedBirth: 11.5))
    }

    @Test func birthDuringTheCurrentScanUsesThatScansListing() throws {
        var ledger = CounterLedger()
        _ = ledger.ingest([], listedAt: 10)
        let result = ledger.ingest([process(at: 12, cpu: 0.25, birth: 11.5)], listedAt: 11, scanSeconds: 1)
        let delta = try #require(result.contributions.first)
        #expect(delta.id.opening == .newbornZero(listing: result.id, verifiedBirth: 11.5))
        #expect(delta.observedSeconds == 1)
    }

    @Test func preexistingFirstGoodCounterOnlyEstablishesBaseline() {
        var ledger = CounterLedger()
        _ = ledger.ingest([], listedAt: 10)
        _ = ledger.ingest([process(at: 11, cpu: nil, birth: 9)], listedAt: 11)
        let result = ledger.ingest([process(at: 12, cpu: 100, birth: 9)], listedAt: 12)
        #expect(result.contributions.isEmpty)
        #expect(result.exclusions.map(\.reason) == [.preexistingLifetime])
        #expect(
            ledger.ingest([process(at: 13, cpu: 101, birth: 9)], listedAt: 13).contributions.first?.cpuSeconds
                == 1)
    }

    @Test func evictionCannotReintroducePreviouslyAcceptedCumulativeCPU() {
        var ledger = CounterLedger(maximumBaselines: 1)
        _ = ledger.ingest([], listedAt: 10)
        #expect(ledger.ingest([process(at: 11, cpu: 1)], listedAt: 11).contributions.count == 1)
        let evicted = ledger.ingest([process(20, at: 12, cpu: 1, birth: 11.5)], listedAt: 12)
        #expect(evicted.evictedBaselines == [ProcessIdentity(pid: 10, startMicroseconds: 1)])
        let returned = ledger.ingest([process(at: 13, cpu: 3)], listedAt: 13)
        #expect(returned.contributions.isEmpty)
        #expect(returned.exclusions.map(\.reason) == [.historyEvicted])
        #expect(ledger.retainedBaselineCount == 1)
        #expect(ledger.ingest([process(at: 14, cpu: 4)], listedAt: 14).contributions.first?.cpuSeconds == 1)
    }

    @Test func listingEvictionMakesFirstCumulativeCPUUnavailable() {
        var ledger = CounterLedger(maximumListings: 1)
        _ = ledger.ingest([], listedAt: 10)
        _ = ledger.ingest([], listedAt: 11)
        let result = ledger.ingest([process(at: 12, cpu: 2)], listedAt: 12)
        #expect(result.contributions.isEmpty)
        #expect(result.exclusions.map(\.reason) == [.historyEvicted])
        #expect(ledger.retainedListingCount == 1)
    }

    @Test func pidReuseNeverSubtractsTheOldLifetimesCounter() throws {
        var ledger = CounterLedger()
        _ = ledger.ingest([process(at: 10, cpu: 100, birth: 1)], listedAt: 10)
        let result = ledger.ingest([process(at: 12, cpu: 1, birth: 11, start: 2)], listedAt: 12)
        let delta = try #require(result.contributions.first)
        #expect(delta.cpuSeconds == 1)
        #expect(delta.id.closing.process.startMicroseconds == 2)
    }

    @Test func decreasingCounterStartsANewBaselineWithoutNewbornRecovery() {
        var ledger = CounterLedger()
        _ = ledger.ingest([], listedAt: 10)
        _ = ledger.ingest([process(at: 11, cpu: 20)], listedAt: 11)
        let reset = ledger.ingest([process(at: 12, cpu: 2)], listedAt: 12)
        #expect(reset.contributions.isEmpty)
        #expect(reset.exclusions.map(\.reason) == [.counterReset])
        #expect(ledger.ingest([process(at: 13, cpu: 3)], listedAt: 13).contributions.first?.cpuSeconds == 1)
    }

    @Test func missingReadsRetainCounterEndpointsAndZeroIsMeasured() throws {
        var ledger = CounterLedger()
        let initial = ledger.ingest([process(at: 10, cpu: 3, birth: 1)], listedAt: 10)
        _ = ledger.ingest([process(at: 11, cpu: nil, birth: 1)], listedAt: 11)
        _ = ledger.ingest([], listedAt: 12)
        let final = ledger.ingest([process(at: 13, cpu: 3, birth: 1)], listedAt: 13)
        let delta = try #require(final.contributions.first)
        #expect(delta.cpuSeconds == 0)
        #expect(delta.id.opening == .observation(.init(scan: initial.id, process: delta.id.closing.process)))
        #expect(delta.observedSeconds == 3)
    }

    @Test func reportAndResumeBoundariesExcludeRecoveredCPUUntilWidened() throws {
        var ledger = CounterLedger()
        let initial = ledger.ingest([], listedAt: 10)
        let resume = ledger.ingest([], listedAt: 11)
        let final = ledger.ingest([process(at: 12, cpu: 1)], listedAt: 11.5, scanSeconds: 0.5)
        let narrow = try CounterWindow(baseline: resume, final: final, contributions: final.contributions)
        #expect(narrow.cpuSeconds == nil)
        #expect(narrow.recovered.map(\.cpuSeconds) == [1])
        let wide = try CounterWindow(baseline: initial, final: final, contributions: final.contributions)
        #expect(wide.cpuSeconds == 1)
        #expect(wide.cpuPercent == 50)
        #expect(wide.recovered.isEmpty)
    }

    @Test func coalescingDeduplicatesAndRecomputesTheEnclosingWindow() throws {
        var ledger = CounterLedger()
        let a = ledger.ingest([process(at: 10.2, cpu: 1, birth: 1)], listedAt: 10, scanSeconds: 0.2)
        let b = ledger.ingest([process(at: 11.4, cpu: 2, birth: 1)], listedAt: 11, scanSeconds: 0.4)
        let c = ledger.ingest([process(at: 12.5, cpu: 4, birth: 1)], listedAt: 12, scanSeconds: 0.5)
        let all = b.contributions + c.contributions + b.contributions
        let merged = try CounterWindow(baseline: a, final: c, contributions: all)
        #expect(merged.contributions.count == 2)
        #expect(merged.cpuSeconds == 3)
        #expect(merged.observedSeconds == 2.5)
        #expect(merged.cpuPercent == 120)
        let last = try CounterWindow(baseline: b, final: c, contributions: all)
        #expect(last.contributions == c.contributions)
        #expect(last.cpuSeconds == 2)
    }

    @Test func differentRunsCannotShareABaseline() {
        var a = CounterLedger()
        var b = CounterLedger()
        let start = a.ingest([], listedAt: 10)
        _ = b.ingest([], listedAt: 10)
        let end = b.ingest([], listedAt: 11)
        #expect(throws: CounterWindowError.self) {
            try CounterWindow(baseline: start, final: end, contributions: [])
        }
    }

    @Test func rawTicksSubtractBeforeFloatingPointConversion() throws {
        var ledger = CounterLedger()
        var first = process(at: 10, cpu: 1, birth: 1)
        first.rawCPU = NativeCPUCounters(user: 1 << 54, system: 0, numerator: 1, denominator: 1)
        first.cpuSeconds = first.rawCPU?.seconds
        _ = ledger.ingest([first], listedAt: 10)
        var next = process(at: 11, cpu: first.cpuSeconds, birth: 1)
        next.rawCPU = NativeCPUCounters(user: (1 << 54) + 1, system: 0, numerator: 1, denominator: 1)
        let delta = try #require(ledger.ingest([next], listedAt: 11).contributions.first)
        #expect(delta.cpuSeconds == 1e-9)
    }

    @Test func oneRawCounterDecreaseCannotHideBehindAnotherIncrease() {
        var ledger = CounterLedger()
        var first = process(at: 10, cpu: 100, birth: 1)
        first.rawCPU = NativeCPUCounters(user: 100, system: 100, numerator: 1, denominator: 1)
        _ = ledger.ingest([first], listedAt: 10)
        var next = process(at: 11, cpu: 200, birth: 1)
        next.rawCPU = NativeCPUCounters(user: 50, system: 200, numerator: 1, denominator: 1)
        let result = ledger.ingest([next], listedAt: 11)
        #expect(result.contributions.isEmpty)
        #expect(result.exclusions.map(\.reason) == [.counterReset])
    }

    @Test(arguments: [Double.nan, .infinity, -1]) func malformedCounterBreaksContinuity(cpu: Double) {
        var ledger = CounterLedger()
        _ = ledger.ingest([process(at: 10, cpu: 1, birth: 1)], listedAt: 10)
        let invalid = ledger.ingest([process(at: 11, cpu: cpu, birth: 1)], listedAt: 11)
        #expect(invalid.contributions.isEmpty)
        #expect(invalid.exclusions.map(\.reason) == [.invalidCounter])
        let next = ledger.ingest([process(at: 12, cpu: 3, birth: 1)], listedAt: 12)
        #expect(next.contributions.isEmpty)
        #expect(next.exclusions.map(\.reason) == [.initialBaseline])
    }

    @Test func invalidReadTimeCannotMoveBaselineBackwards() {
        var ledger = CounterLedger()
        _ = ledger.ingest([process(at: 10, cpu: 1, birth: 1)], listedAt: 10)
        let invalid = ledger.ingest([process(at: 9, cpu: 2, birth: 1)], listedAt: 11)
        #expect(invalid.exclusions.map(\.reason) == [.invalidTime])
        let next = ledger.ingest([process(at: 12, cpu: 3, birth: 1)], listedAt: 12)
        #expect(next.contributions.first?.cpuSeconds == 2)
        #expect(next.contributions.first?.startedAt == 10)
    }

    @Test func incompatibleRawCounterTimebasesCannotBridge() {
        var ledger = CounterLedger()
        var first = process(at: 10, cpu: 1, birth: 1)
        first.rawCPU = NativeCPUCounters(user: 100, system: 0, numerator: 1, denominator: 1)
        _ = ledger.ingest([first], listedAt: 10)
        var next = process(at: 11, cpu: 2, birth: 1)
        next.rawCPU = NativeCPUCounters(user: 200, system: 0, numerator: 2, denominator: 1)
        let result = ledger.ingest([next], listedAt: 11)
        #expect(result.contributions.isEmpty)
        #expect(result.exclusions.map(\.reason) == [.incompatibleCounters])
    }

    @Test func conflictingCopiesOfAContributionAreRejected() throws {
        var ledger = CounterLedger()
        let a = ledger.ingest([process(at: 10, cpu: 1, birth: 1)], listedAt: 10)
        let b = ledger.ingest([process(at: 11, cpu: 2, birth: 1)], listedAt: 11)
        let original = try #require(b.contributions.first)
        let changed = CPUContribution(id: original.id, cpuSeconds: 2, startedAt: 10, endedAt: 11)
        #expect(throws: CounterWindowError.self) {
            try CounterWindow(baseline: a, final: b, contributions: [original, changed])
        }
    }
}

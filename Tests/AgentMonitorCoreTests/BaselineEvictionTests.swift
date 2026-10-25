import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct BaselineEvictionTests {
    @Test func steadyChurnDoesNotRepeatedlySortTheRetainedPopulation() {
        var ledger = CounterLedger(maximumBaselines: 128)
        for scan in 0..<1_000 {
            let stable = (1...40).map { sample(Int32($0), at: Double(scan), cpu: Double(scan)) }
            let births = (0..<2).map {
                sample(Int32(100 + scan * 2 + $0), at: Double(scan), cpu: 0)
            }
            _ = ledger.ingest(stable + births, listedAt: Double(scan))
            #expect(ledger.retainedBaselineCount <= 128)
            #expect(ledger.retainedEvictionReferenceCount <= 256)
        }
        #expect(ledger.evictionSortInputCount < 5_000)
    }

    @Test func anOldMissingLifetimeCannotPinUnboundedLazyReferences() {
        var ledger = CounterLedger(maximumBaselines: 8)
        _ = ledger.ingest([sample(1), sample(2)], listedAt: 1)
        for scan in 2...1_000 {
            _ = ledger.ingest([sample(2, at: Double(scan), cpu: Double(scan))], listedAt: Double(scan))
            #expect(ledger.retainedEvictionReferenceCount <= 16)
        }
        let returned = ledger.ingest([sample(1, at: 1_001, cpu: 10)], listedAt: 1_001)
        #expect(returned.contributions.first?.cpuSeconds == 10)
        #expect(returned.contributions.first?.id.opening.scan.sequence == 0)
        #expect(ledger.evictionSortInputCount == 0)
    }

    @Test(arguments: 0..<100) func evictionAndBirthFloorMatchSortOracle(seed: Int) {
        struct Seen {
            var sequence: Int
            var read: Double
        }
        var random = UInt64(seed + 1)
        func next() -> UInt64 {
            random = random &* 6_364_136_223_846_793_005 &+ 1
            return random >> 32
        }
        let capacity = 8
        var ledger = CounterLedger(maximumBaselines: capacity)
        var seen: [ProcessIdentity: Seen] = [:]
        var floor = -Double.infinity
        for scan in 0..<100 {
            var population: [ProcessIdentity: ProcessSample] = [:]
            for _ in 0..<Int(next() % 16) {
                let pid = Int32(next() % 16 + 1)
                let start = next() % 3
                var value = sample(pid, start: start, at: Double(scan + 10), cpu: Double(scan + 1))
                value.startedAt = Double(start) + 10.5
                if next() % 7 == 0 { value.cpuSeconds = nil }
                population[value.identity] = value
            }
            let previouslyRetained = Set(seen.keys)
            for value in population.values {
                seen[value.identity] = Seen(sequence: scan, read: value.sampledAt)
            }
            let expected = seen.sorted {
                if $0.value.sequence != $1.value.sequence { return $0.value.sequence < $1.value.sequence }
                if $0.key.pid != $1.key.pid { return $0.key.pid < $1.key.pid }
                return $0.key.startMicroseconds < $1.key.startMicroseconds
            }.prefix(max(0, seen.count - capacity)).map(\.key)
            let result = ledger.ingest(Array(population.values), listedAt: Double(scan + 10))
            #expect(result.evictedBaselines == expected)
            for exclusion in result.exclusions where exclusion.reason == .historyEvicted {
                #expect(population[exclusion.observation.process]!.startedAt! <= floor)
            }
            for value in population.values
            where scan > 0 && !previouslyRetained.contains(value.identity)
                && value.cpuSeconds != nil && value.startedAt! <= floor
            {
                #expect(
                    result.exclusions.contains {
                        $0.observation.process == value.identity && $0.reason == .historyEvicted
                    })
            }
            for identity in expected {
                floor = max(floor, seen.removeValue(forKey: identity)!.read)
            }
            #expect(ledger.retainedBaselineCount == seen.count)
        }
    }
}

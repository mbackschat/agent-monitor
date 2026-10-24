import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct RecentActivityTests {
    @Test func compactionRetainsSpikesAndImmutableOwnersWithoutRawScanGrowth() throws {
        var ledger = CounterLedger()
        let initial = ledger.ingest([sample(42, at: 0, cpu: 0)], listedAt: 0)
        var activity = RecentActivityAccumulator(baseline: initial)
        for tick in 1...10 {
            var value = sample(42, at: Double(tick) / 10, cpu: Double(tick) / 100)
            value.footprintBytes = tick == 3 ? 100_000_000 : 10_000_000
            value.kernelPeakFootprintBytes = 150_000_000
            let scan = ledger.ingest([value], listedAt: value.sampledAt)
            activity.append(scan, rows: [recentRow(value, session: tick <= 5 ? nil : sessionA)])
        }
        let unit = activity.seal(scope: .agentsOnly)
        #expect(unit.records.count == 2)
        #expect(abs(unit.records.reduce(0) { $0 + $1.cpuSeconds } - 0.1) < 1e-9)
        #expect(
            unit.records.first { $0.category.owner.sessionID == nil }?.maximumFootprint?.bytes == 100_000_000)
        #expect(
            unit.records.first { $0.category.owner.sessionID == sessionA }?.maximumFootprint?.bytes
                == 10_000_000)
        #expect(unit.crossings.isEmpty)
    }

    @Test func crossingCPUBecomesRecoveredAfterWholeUnitEviction() throws {
        var ledger = CounterLedger()
        let first = ledger.ingest([sample(42, at: 0, cpu: 0)], listedAt: 0)
        let middle = ledger.ingest([], listedAt: 1)
        var a = RecentActivityAccumulator(baseline: first)
        a.append(middle, rows: [])
        let value = sample(42, at: 2, cpu: 0.4)
        let last = ledger.ingest([value], listedAt: 2)
        var b = RecentActivityAccumulator(baseline: middle)
        b.append(last, rows: [recentRow(value, session: sessionA)])
        let unit = b.seal(scope: .agentsOnly)
        #expect(unit.records.first?.cpuSeconds == 0)
        #expect(unit.crossings.count == 1)
        let store = RecentActivityStore()
        store.append(a.seal(scope: .agentsOnly))
        store.append(unit)
        let wide = store.snapshot()
        #expect(wide?.cpuSeconds == 0.4)
        #expect(wide?.recoveredCPUSeconds == 0)
        let narrow = RecentActivityStore(limits: RecentActivityLimits(seconds: 1))
        narrow.append(unit)
        #expect(narrow.snapshot()?.cpuSeconds == 0)
        #expect(narrow.snapshot()?.recoveredCPUSeconds == 0.4)
    }

    @Test func scopeAndRunChangesCannotCarryOldHistoryOrMemory() throws {
        let store = RecentActivityStore()
        for index in 0..<2 {
            var ledger = CounterLedger()
            let start = ledger.ingest([sample(42, at: 0, cpu: 0)], listedAt: 0)
            var activity = RecentActivityAccumulator(baseline: start)
            let value = sample(42, at: 1, cpu: Double(index + 1))
            activity.append(ledger.ingest([value], listedAt: 1), rows: [recentRow(value, session: sessionA)])
            store.append(activity.seal(scope: .agentsOnly))
            #expect(store.snapshot()?.units.count == 1)
            #expect(store.snapshot()?.cpuSeconds == Double(index + 1))
        }
    }
}

func recentRow(_ sample: ProcessSample, session: String?) -> HeavyProcess {
    HeavyProcess(
        process: sample.identity, executable: sample.executable, name: sample.name, cpuPercent: nil,
        footprintBytes: sample.footprintBytes, kernelPeakFootprintBytes: sample.kernelPeakFootprintBytes,
        cwd: "/fixture", command: nil, metadataStatus: .markerRead,
        attribution: Attribution(
            provider: session == nil ? nil : .codex, evidence: session == nil ? .unknown : .marker,
            context: .unverified, threadID: session, rootSessionID: nil, runtime: nil, terminal: nil,
            runtimeDirectory: nil, candidateThreadIDs: [], ancestry: [sample.identity]))
}

extension RecentActivityTests {
    @Test func everyWholeUnitSuffixMatchesIndependentRawCPUAndMemoryOracle() throws {
        var ledger = CounterLedger()
        var baseline = ledger.ingest([sample(1, at: 0, cpu: 0), sample(2, at: 0, cpu: 0)], listedAt: 0)
        var units: [RecentActivityUnit] = []
        var rawCPU: [(opening: UInt64, closing: UInt64, seconds: Double)] = []
        var rawMemory: [(scan: UInt64, key: String, bytes: UInt64)] = []
        for unitIndex in 0..<8 {
            var accumulator = RecentActivityAccumulator(baseline: baseline)
            for offset in 1...3 {
                let tick = unitIndex * 3 + offset
                var values: [ProcessSample] = []
                for pid: Int32 in [1, 2] where pid == 1 || tick >= 8 {
                    var value = sample(
                        pid, executable: tick < 10 ? "/one/node" : "/two/java",
                        at: Double(tick) / 3, cpu: Double(tick) / 10)
                    value.footprintBytes = tick % 5 == 0 ? nil : UInt64((tick * 17) % 101)
                    value.kernelPeakFootprintBytes = tick % 4 == 0 ? nil : UInt64(100 - tick)
                    values.append(value)
                }
                let scan = ledger.ingest(values, listedAt: Double(tick) / 3)
                let rows = values.map {
                    recentRow($0, session: tick % 4 == 0 ? nil : (tick < 12 ? sessionA : sessionB))
                }
                let runtime: Set<ProcessIdentity> = unitIndex % 2 == 0 ? [values[0].identity] : []
                accumulator.append(scan, rows: rows, runtimes: runtime)
                for contribution in scan.contributions {
                    rawCPU.append(
                        (
                            contribution.id.opening.scan.sequence, contribution.id.closing.scan.sequence,
                            contribution.cpuSeconds
                        ))
                }
                for row in rows {
                    let key =
                        "\(row.process.pid)/\(row.attribution.threadID ?? "?")/\(row.executable)/\(runtime.contains(row.process))"
                    if let bytes = row.footprintBytes { rawMemory.append((scan.id.sequence, key, bytes)) }
                }
                baseline = scan
            }
            units.append(accumulator.seal(scope: .allProcesses))
        }
        for suffix in 0..<units.count {
            let store = RecentActivityStore()
            for unit in units.dropFirst(suffix) { store.append(unit) }
            let snapshot = try #require(store.snapshot())
            let opening = units[suffix].baselineScan
            let expected = rawCPU.filter { $0.closing > opening && $0.opening >= opening }.reduce(0) {
                $0 + $1.seconds
            }
            let recovered = rawCPU.filter { $0.closing > opening && $0.opening < opening }.reduce(0) {
                $0 + $1.seconds
            }
            #expect(abs(snapshot.cpuSeconds - expected) < 1e-9)
            #expect(abs(snapshot.recoveredCPUSeconds - recovered) < 1e-9)
            var expectedMemory: [String: UInt64] = [:]
            for reading in rawMemory where reading.scan > opening {
                expectedMemory[reading.key] = max(expectedMemory[reading.key] ?? 0, reading.bytes)
            }
            var actual: [String: UInt64] = [:]
            for record in snapshot.units.flatMap(\.records) {
                let category = record.category
                let key =
                    "\(category.process.pid)/\(category.owner.sessionID ?? "?")/\(category.executable)/\(category.isAgentRuntime)"
                if let bytes = record.maximumFootprint?.bytes { actual[key] = max(actual[key] ?? 0, bytes) }
            }
            #expect(actual == expectedMemory)
        }
    }

    @Test func oversizedContextIsDiscardedRatherThanRetainedBeyondTheCap() throws {
        var ledger = CounterLedger()
        let baseline = ledger.ingest([], listedAt: 0)
        var activity = RecentActivityAccumulator(baseline: baseline)
        let values = (1...30).map { sample(Int32($0), at: 1, cpu: 1) }
        activity.append(
            ledger.ingest(values, listedAt: 1), rows: values.map { recentRow($0, session: sessionA) })
        let store = RecentActivityStore(limits: RecentActivityLimits(records: 10, textBytes: 100))
        store.append(activity.seal(scope: .agentsOnly), current: activity.current, present: activity.present)
        let snapshot = try #require(store.snapshot())
        #expect(snapshot.retentionLimited)
        #expect(!snapshot.currentContextAvailable)
        #expect(store.retainedPayloadSize.observations <= 10)
        #expect(store.retainedPayloadSize.textBytes <= 100)
    }

    @Test func pausedBackingStaysSelfContainedUnderRetentionPressure() throws {
        var ledger = CounterLedger()
        var baseline = ledger.ingest([sample(42, at: 0, cpu: 0)], listedAt: 0)
        let store = RecentActivityStore(limits: RecentActivityLimits(records: 18, textBytes: 3000))
        var paused: RecentActivitySnapshot?
        for tick in 1...20 {
            var activity = RecentActivityAccumulator(baseline: baseline)
            let value = sample(42, at: Double(tick), cpu: Double(tick))
            let scan = ledger.ingest([value], listedAt: Double(tick))
            activity.append(scan, rows: [recentRow(value, session: sessionA)])
            store.append(
                activity.seal(scope: .agentsOnly), current: activity.current, present: activity.present)
            if tick == 2 { paused = store.snapshot() }
            #expect(store.retainedPayloadSize.observations <= 18)
            #expect(store.retainedPayloadSize.textBytes <= 3000)
            baseline = scan
        }
        #expect(paused?.cpuSeconds == 2)
        #expect(paused?.units.flatMap(\.records).count == 2)
        #expect(store.snapshot()?.retentionLimited == true)
    }
}

extension RecentActivityTests {
    @Test(arguments: [true, false])
    func executableChangeUsesAcceptedCounterEndpointsAcrossMissingReads(crossesUnit: Bool) throws {
        var ledger = CounterLedger()
        let initial = ledger.ingest([sample(42, executable: "/bin/a", at: 0, cpu: 0)], listedAt: 0)
        let missing = ledger.ingest(
            crossesUnit ? [] : [sample(42, executable: "/bin/b", at: 1, cpu: nil)], listedAt: 1)
        var activity = RecentActivityAccumulator(baseline: crossesUnit ? missing : initial)
        if !crossesUnit {
            activity.append(missing, rows: [recentRow(missing.observations[0].sample, session: sessionA)])
        }
        let value = sample(42, executable: "/bin/b", at: 2, cpu: 1)
        activity.append(ledger.ingest([value], listedAt: 2), rows: [recentRow(value, session: sessionA)])
        #expect(activity.seal(scope: .agentsOnly).records.first?.executableChangedIntervals == 1)
    }
}

extension RecentActivityTests {
    @Test func emptyBoundedHistoryStillDeclaresItsAllProcessScope() throws {
        var ledger = CounterLedger()
        let baseline = ledger.ingest([], listedAt: 0)
        var activity = RecentActivityAccumulator(baseline: baseline)
        let value = sample(42, at: 1, cpu: 1)
        activity.append(ledger.ingest([value], listedAt: 1), rows: [recentRow(value, session: nil)])
        let store = RecentActivityStore(limits: RecentActivityLimits(records: 1, textBytes: 1))
        store.append(activity.seal(scope: .allProcesses))
        let snapshot = try #require(store.snapshot())
        #expect(snapshot.units.isEmpty)
        #expect(snapshot.scope == .allProcesses)
    }
}

extension RecentActivityTests {
    @Test func openUnitBudgetIncludesSeparateFinalScanContext() {
        var ledger = CounterLedger()
        let baseline = ledger.ingest([], listedAt: 0)
        var activity = RecentActivityAccumulator(baseline: baseline)
        let value = sample(42, at: 1, cpu: 1)
        activity.append(ledger.ingest([value], listedAt: 1), rows: [recentRow(value, session: sessionA)])
        let unit = activity.seal(scope: .allProcesses)
        let current = activity.current.reduce(0) { $0 + $1.payloadSize.observations }
        #expect(
            activity.payloadSize.observations == unit.size.observations + current + activity.present.count)
    }
}

extension RecentActivityTests {
    @Test(arguments: [false, true])
    func lossQualifierExpiresAfterTheAffectedRange(gap: Bool) throws {
        let store = RecentActivityStore(limits: RecentActivityLimits(records: 160, textBytes: 100_000))
        var ledger = CounterLedger()
        var baseline = ledger.ingest([], listedAt: 0)
        for tick in 1...125 {
            let count = !gap && tick == 2 ? 200 : 1
            let values = (1...count).map { sample(Int32($0), at: Double(tick), cpu: Double(tick)) }
            let scan = ledger.ingest(values, listedAt: Double(tick))
            var activity = RecentActivityAccumulator(baseline: baseline)
            activity.append(scan, rows: values.map { recentRow($0, session: sessionA) })
            if !gap || tick != 2 { store.append(activity.seal(scope: .agentsOnly)) }
            if tick == 3 { #expect(store.snapshot()?.retentionLimited == true) }
            baseline = scan
        }
        let result = try #require(store.snapshot())
        #expect(result.duration == 60)
        #expect(!result.retentionLimited)
        #expect(store.retainedPayloadSize.observations <= 160)
    }
}

extension RecentActivityTests {
    @Test(arguments: [50, 613])
    func historyRemainsBoundedWithChurnOrALongAllProcessPause(population: Int) throws {
        let churn = population == 50
        var ledger = CounterLedger()
        var baseline = ledger.ingest([], listedAt: 0)
        let store = RecentActivityStore()
        var paused: RecentActivitySnapshot?
        var heldCPU: Double?
        for tick in 1...185 {
            let values = (1...population).map { index in
                sample(
                    Int32(churn ? tick * population + index : index), at: Double(tick), cpu: Double(tick) / 10
                )
            }
            let scan = ledger.ingest(values, listedAt: Double(tick))
            var activity = RecentActivityAccumulator(baseline: baseline)
            activity.append(scan, rows: values.map { recentRow($0, session: sessionA) })
            store.append(
                activity.seal(scope: .allProcesses), current: activity.current, present: activity.present)
            if !churn && tick == 60 {
                paused = store.snapshot()
                heldCPU = paused?.cpuSeconds
            }
            if !churn && tick == 120 {
                #expect(paused?.cpuSeconds == heldCPU)
                #expect(store.snapshot()?.retentionLimited == true)
                paused = nil
            }
            #expect(store.retainedPayloadSize.observations <= 65_536)
            #expect(store.retainedPayloadSize.textBytes <= 16_777_216)
            baseline = scan
        }
        let latest = try #require(store.snapshot())
        #expect(latest.duration == 60)
        #expect(!latest.retentionLimited)
        if churn { #expect(Set(latest.units.flatMap(\.records).map(\.category.process)).count == 3000) }
    }
}

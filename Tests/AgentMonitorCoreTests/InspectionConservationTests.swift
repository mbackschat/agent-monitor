import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct InspectionConservationTests {
    @Test func randomMissingReadsReuseAndDeparturesConserveTheLastAcceptedCounter() throws {
        for seed in 1...60 {
            var random = UInt64(seed)
            func draw(_ limit: Int) -> Int {
                random = random &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Int((random >> 32) % UInt64(limit))
            }
            var ledger = CounterLedger()
            var baselineLedger = CounterLedger()
            let zero = ledger.ingest([], listedAt: 0)
            _ = baselineLedger.ingest([], listedAt: 0)
            var window = AccountingWindow(baseline: zero)
            var oracle: [ProcessIdentity: Double] = [:]
            var accepted = 0.0
            var baselineCPU = 0.0
            var ids: Set<CPUContribution.ID> = []
            for tick in 1...40 {
                let end = Double(tick) / 10
                var buffer = InspectionBuffer()
                var census: [ProcessSample] = []
                var rows: [HeavyProcess] = []
                var listed: [Int32] = []
                var outcomes: [NativeCounterOutcome] = []
                for pid in 42..<50 {
                    let disposition = draw(4)
                    var held = inspectionReading(pid: Int32(pid))
                    var sample = ProcessSample(
                        identity: ProcessIdentity(pid: Int32(pid), startMicroseconds: UInt64(tick)),
                        parentPID: 1, executable: held.sample.executable, name: held.sample.name,
                        sampledAt: end - 0.05, cpuSeconds: nil, footprintBytes: 100)
                    sample.startedAt = end - 0.08
                    sample.sampledAt = end - 0.05
                    sample.cpuSeconds = Double(draw(20) + 1) / 1000
                    let owner = held.row.attribution
                    let row = HeavyProcess(
                        process: sample.identity, executable: sample.executable,
                        name: sample.name, cpuPercent: nil, footprintBytes: sample.footprintBytes,
                        cwd: nil, command: nil, metadataStatus: .unavailable, attribution: owner)
                    held = HeldInspectionObservation(
                        sample: sample, row: row, evidenceAt: nil,
                        isAgentRuntime: false, corroboratedRoot: nil)
                    _ = buffer.retain(held)
                    switch disposition {
                    case 0:
                        sample.sampledAt = end
                        sample.cpuSeconds = held.sample.cpuSeconds! * 2
                        census.append(sample)
                        rows.append(row)
                        listed.append(Int32(pid))
                        oracle[sample.identity] = sample.cpuSeconds
                    case 1:
                        oracle[sample.identity] = sample.cpuSeconds
                    default:
                        listed.append(Int32(pid))
                        outcomes.append(
                            NativeCounterOutcome(
                                pid: Int32(pid), identity: nil,
                                operation: .bsdInfo, status: .permissionDenied, failure: nil,
                                observedAtTicks: 0))
                    }
                }
                let source = ProcessSnapshot(
                    samples: census, enumeratedCount: listed.count,
                    unreadableCount: outcomes.count, listedAt: end, scanSeconds: 0,
                    hostCounters: nil, logicalCPUCount: 8, nativeOutcomes: outcomes, listedPIDs: listed)
                let carried = buffer.admit(at: source)
                let scan = ledger.ingest(
                    census, listedAt: end, source: source, carried: carried.map(\.sample))
                let control = baselineLedger.ingest(census, listedAt: end, source: source)
                for contribution in scan.contributions {
                    let unique = ids.insert(contribution.id).inserted
                    #expect(unique)
                    accepted += contribution.cpuSeconds
                }
                baselineCPU += control.contributions.reduce(0) { $0 + $1.cpuSeconds }
                try window.append(scan, rows: rows, carried: carried)
                #expect(window.present == Set(census.map(\.identity)))
                #expect(abs(accepted - oracle.values.reduce(0, +)) < 1e-8)
                #expect(accepted + 1e-8 >= baselineCPU)
            }
            #expect(abs(window.summary.contributions.reduce(0) { $0 + $1.cpuSeconds } - accepted) < 1e-8)
        }
    }

    @Test func pressureMayCollapseCarriedRowsWithoutLosingResources() throws {
        let held = inspectionReading()
        var ledger = CounterLedger()
        var window = AccountingWindow(baseline: ledger.ingest([], listedAt: 0))
        try window.append(ledger.ingest([], listedAt: 0.1, carried: [held.sample]), rows: [], carried: [held])
        window.compact(to: MonitoringPipelineLimits(pendingObservations: 1, pendingTextBytes: 1024))
        #expect(window.summary.contributions.isEmpty)
        #expect(window.collapsedCPUSeconds == 0.02)
        #expect(window.present.isEmpty)
        #expect(window.current.isEmpty)
    }
}

extension InspectionConservationTests {
    @Test func returnedLifetimeTelescopesFromCarriedEndpointAcrossOneMissingCensus() throws {
        let held = inspectionReading()
        var ledger = CounterLedger()
        var window = AccountingWindow(baseline: ledger.ingest([], listedAt: 0))
        try window.append(ledger.ingest([], listedAt: 0.1, carried: [held.sample]), rows: [], carried: [held])
        try window.append(ledger.ingest([], listedAt: 0.2), rows: [])
        var returned = held.sample
        returned.sampledAt = 0.3
        returned.cpuSeconds = 0.1
        let scan = ledger.ingest([returned], listedAt: 0.3)
        try window.append(scan, rows: [held.row])
        #expect(scan.contributions.first?.missingReadIntervalCount == 1)
        #expect(abs(window.summary.contributions.reduce(0) { $0 + $1.cpuSeconds } - 0.1) < 1e-9)
        #expect(window.present == [held.sample.identity])
    }

    @Test func carriedCounterResetRemainsExcludedAndCannotInventCPU() {
        var ledger = CounterLedger()
        var reading = inspectionReading().sample
        reading.startedAt = nil
        reading.sampledAt = 0
        reading.cpuSeconds = 2
        _ = ledger.ingest([reading], listedAt: 0)
        reading.sampledAt = 0.05
        reading.cpuSeconds = 1
        let scan = ledger.ingest([], listedAt: 0.1, carried: [reading])
        #expect(scan.contributions.isEmpty)
        #expect(scan.exclusions.first?.reason == .counterReset)
    }
}

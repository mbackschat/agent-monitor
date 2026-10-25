import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

@Suite struct AccountingWindowCapacityTests {
    @Test func retainedSizeDoesNotGrowWithScansOrEvidenceRefreshes() throws {
        let fixture = CapacityPopulation(count: 4)
        var ledger = CounterLedger()
        var window = AccountingWindow(baseline: fixture.scan(0, ledger: &ledger))
        var firstSize = 0
        for tick in 1...150 {
            try window.append(
                fixture.scan(tick, ledger: &ledger), rows: fixture.rows,
                attributionTimes: Dictionary(
                    uniqueKeysWithValues: fixture.rows.map {
                        ($0.process, Double(tick) / 10)
                    }))
            if tick == 10 { firstSize = window.payloadSize.observations }
        }
        #expect(window.summary.contributions.count == 4)
        #expect(window.payloadSize.observations <= firstSize)
        #expect(abs(try #require(window.counters().cpuSeconds) - 0.6) < 1e-9)
    }

    @Test(arguments: [613, 1_000], [2, 5])
    func sustainedWindowsFitWithAncestryAndRecentHistory(population: Int, displaySeconds: Int) throws {
        let ticksPerWindow = displaySeconds * 10
        let fixture = CapacityPopulation(count: population)
        var ledger = CounterLedger()
        var baseline = fixture.scan(0, ledger: &ledger)
        let limits = MonitoringPipelineLimits()
        var total = 0.0
        for unit in 0..<4 {
            var window = AccountingWindow(baseline: baseline)
            for tick in (unit * ticksPerWindow + 1)...((unit + 1) * ticksPerWindow) {
                let scan = fixture.scan(tick, ledger: &ledger)
                try window.append(scan, rows: fixture.rows)
                let records = window.payloadSize.observations
                try #require(
                    records <= limits.pendingObservations,
                    "population \(population), scan \(tick), records \(records)")
                #expect(
                    window.payloadSize.textBytes <= limits.pendingTextBytes)
                baseline = scan
            }
            let projection = try window.projection(scope: .agentsOnly)
            #expect(projection.rows.count == population)
            #expect(projection.summary.contributions.count == population)
            #expect(projection.summary.contributions.allSatisfy { $0.attribution.threadID == sessionA })
            total += try #require(projection.counters.cpuSeconds)
        }
        #expect(abs(total - Double(population * ticksPerWindow * 4) / 1_000) < 1e-8)
    }

    @Test func compactRecordsPreserveEvidenceRangesAndIntervalCountsAcrossMerge() throws {
        let fixture = CapacityPopulation(count: 2)
        var ledger = CounterLedger()
        var baseline = fixture.scan(0, ledger: &ledger)
        var combined = AccountingWindow(baseline: baseline)
        for tick in 1...4 {
            let scan = fixture.scan(tick, ledger: &ledger)
            var unit = AccountingWindow(baseline: baseline)
            let times = Dictionary(
                uniqueKeysWithValues: fixture.rows.map { ($0.process, Double(tick) + 0.01) })
            try unit.append(scan, rows: fixture.rows, attributionTimes: times)
            try combined.merge(unit)
            baseline = scan
        }
        let values = combined.summary.contributions
        #expect(values.count == 2)
        #expect(values.allSatisfy { $0.intervalCount == 4 && $0.missingReadIntervalCount == 0 })
        #expect(
            values.allSatisfy { $0.earliestEvidenceObservedAt == 1.01 && $0.latestEvidenceObservedAt == 4.01 }
        )
        #expect(values.allSatisfy { abs($0.cpuSeconds - 0.004) < 1e-9 })
        #expect(
            try JSONDecoder().decode([FrozenCPUContribution].self, from: JSONEncoder().encode(values))
                == values)
    }

    @Test(.timeLimit(.minutes(3)))
    func productionPipelineDeliversFiveSecondWindowsForOneThousandProcesses() async throws {
        let fixture = PipelinePopulation()
        let reports = Mutex<[MonitoringSnapshot]>([])
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                intervalSeconds: 0.1, samples: 2, collectAgentLoad: true, reportIntervalSeconds: 5),
            reader: fixture, clock: fixture, registry: fixture, recentActivity: RecentActivityStore())
        try await session.run { snapshot in reports.withLock { $0.append(snapshot) } }
        let delivered = reports.withLock { $0 }
        #expect(!delivered.isEmpty)
        #expect(delivered.last?.window?.finalScan == 60)
        let seconds = delivered.compactMap(\.window).flatMap(\.contributions).reduce(0) { $0 + $1.cpuSeconds }
        #expect(abs(seconds - 60) < 1e-8)
        #expect(delivered.allSatisfy { $0.findings.count == 1_000 })
        #expect(delivered.allSatisfy { $0.findings.allSatisfy { $0.attribution.threadID == sessionA } })
        let history = try #require(delivered.last?.recentActivity)
        #expect(history.baselineScan == delivered.first?.window?.baselineScan)
        #expect(history.startedAt == delivered.first?.window?.startedAt)
        #expect(history.endedAt == delivered.last?.window?.endedAt)
        #expect(!history.retentionLimited)
    }

    @Test func delayedPresentationCoalescesTwoFullWindowsWithinTheDefaultBudget() async throws {
        let fixture = CapacityPopulation(count: 1_000)
        let ticksPerWindow = 50
        var ledger = CounterLedger()
        var baseline = fixture.scan(0, ledger: &ledger)
        let channel = MonitoringChannel<AccountingWindow>(
            stage: .presentation, limits: MonitoringPipelineLimits(),
            coalesce: { old, new in
                try old.merge(new)
                old.compact(to: MonitoringPipelineLimits())
                return old.payloadSize
            })
        for unit in 0..<2 {
            var window = AccountingWindow(baseline: baseline)
            for tick in (unit * ticksPerWindow + 1)...((unit + 1) * ticksPerWindow) {
                let scan = fixture.scan(tick, ledger: &ledger)
                try window.append(scan, rows: fixture.rows)
                baseline = scan
            }
            try await channel.send(
                window, size: window.payloadSize, sequence: UInt64(unit * ticksPerWindow + 1))
        }
        await channel.finish()
        let merged = try #require(await channel.next())
        #expect(merged.summary.contributions.count == 1_000)
        #expect(abs(try #require(merged.counters().cpuSeconds) - 100) < 1e-8)
        #expect(try await channel.next() == nil)
    }
}

private struct CapacityPopulation {
    let rows: [HeavyProcess]

    init(count: Int) {
        rows = (1...count).map { index in
            let identity = ProcessIdentity(pid: Int32(42_000 + index), startMicroseconds: UInt64(index))
            return HeavyProcess(
                process: identity, executable: "/fake/worker", name: "worker", cpuPercent: nil,
                footprintBytes: 1_000_000, cwd: "/fake/project", command: nil, metadataStatus: .markerRead,
                attribution: Attribution(
                    provider: .codex, evidence: .marker, context: .unverified,
                    threadID: sessionA, rootSessionID: nil, runtime: nil, terminal: nil,
                    runtimeDirectory: nil, candidateThreadIDs: [],
                    ancestry: [identity]
                        + (1...3).map { ProcessIdentity(pid: Int32($0), startMicroseconds: 1) }))
        }
    }

    func scan(_ tick: Int, ledger: inout CounterLedger) -> CounterScan {
        let time = Double(tick) / 10
        let samples = rows.map { row in
            ProcessSample(
                identity: row.process, parentPID: 1, executable: row.executable, name: row.name,
                sampledAt: time, cpuSeconds: Double(tick) / 1_000, footprintBytes: row.footprintBytes)
        }
        let source = diagnosisScan(samples, at: time)
        return ledger.ingest(samples, listedAt: time, source: source)
    }
}

private final class PipelinePopulation: ProcessReading, SamplingClock, SessionRegistryReading, Sendable {
    private let time = Mutex(0.0)
    let count: Int
    let sharedDepth: Int?
    init(count: Int = 1_000, sharedDepth: Int? = nil) {
        self.count = count
        self.sharedDepth = sharedDepth
    }

    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let at = time.withLock { $0 }
        let samples: [ProcessSample] = (1...count).map { (index: Int) in
            let pid = Int32(42_000 + index)
            let parent: Int32
            if let sharedDepth {
                parent = index == 1 ? 0 : index <= sharedDepth ? pid - 1 : Int32(42_000 + sharedDepth)
            } else {
                parent = index % 5 == 1 ? 0 : pid - 1
            }
            return ProcessSample(
                identity: ProcessIdentity(pid: pid, startMicroseconds: 1), parentPID: parent,
                executable: "/fake/worker", name: "worker", sampledAt: at,
                cpuSeconds: at / 100, footprintBytes: 1_000_000)
        }
        return diagnosisScan(samples, at: at)
    }

    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        metadata(for: sample, includeCommand: false)
    }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)], status: .markerRead)
    }
    func output(of query: SessionRegistryQuery) throws -> Data { Data("[]".utf8) }
    func wait(seconds: Double) async throws {
        try Task.checkCancellation()
        time.withLock { $0 += seconds }
    }
    func monotonicNow() -> Double { time.withLock { $0 } }
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }
}

@Test(.timeLimit(.minutes(5)))
func productionPipelineSupportsThreeThousandLifetimesWithTenAncestors() async throws {
    let fixture = PipelinePopulation(count: 3_000, sharedDepth: 10)
    let store = RecentActivityStore()
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(
            intervalSeconds: 0.1, samples: 2, scope: .allProcesses,
            collectAgentLoad: true, reportIntervalSeconds: 5),
        reader: fixture, clock: fixture, registry: fixture, recentActivity: store)
    let reports = Mutex<[MonitoringSnapshot]>([])
    try await session.run { value in reports.withLock { $0.append(value) } }
    let values = reports.withLock { $0 }
    #expect(values.last?.window?.finalScan == 60)
    #expect(values.allSatisfy { $0.observedFindings.count == 3_000 })
    let cpu = values.compactMap(\.window).flatMap(\.contributions).reduce(0) { $0 + $1.cpuSeconds }
    #expect(abs(cpu - 180) < 1e-7)
    #expect(store.diagnostics.chargedRecords <= 65_536)
}

@Test func retainedObservationUsesItsCanonicalRunAttributionStorage() throws {
    var ledger = CounterLedger()
    var window = AccountingWindow(baseline: CapacityPopulation(count: 1).scan(0, ledger: &ledger))
    for tick in 1...3 {
        let fixture = CapacityPopulation(count: 1)
        let scan = fixture.scan(tick, ledger: &ledger)
        try window.append(scan, rows: fixture.rows)
    }
    let row = try #require(try window.findings(scope: .allProcesses).first)
    let contribution = try #require(window.summary.contributions.first)
    let shared = row.attribution.ancestry.withUnsafeBufferPointer { left in
        contribution.attribution.ancestry.withUnsafeBufferPointer { right in
            left.baseAddress == right.baseAddress
        }
    }
    #expect(shared)
}

@Test func mergedRecoveredContributionSharesCanonicalAttributionStorage() throws {
    var ledger = CounterLedger()
    func scan(_ tick: Int, cpu: Double?) -> CounterScan {
        let row = CapacityPopulation(count: 1).rows[0]
        let observation = ProcessSample(
            identity: row.process, parentPID: 1,
            executable: row.executable, name: row.name, sampledAt: Double(tick), cpuSeconds: cpu,
            footprintBytes: row.footprintBytes)
        return ledger.ingest([observation], listedAt: Double(tick))
    }
    _ = scan(0, cpu: 0)
    var window = AccountingWindow(baseline: scan(1, cpu: nil))
    let middle = scan(2, cpu: nil)
    try window.append(middle, rows: CapacityPopulation(count: 1).rows)
    var later = AccountingWindow(baseline: middle)
    try later.append(scan(3, cpu: 0.3), rows: CapacityPopulation(count: 1).rows)
    try window.merge(later)
    let row = try #require(try window.findings(scope: .allProcesses).first)
    let recovered = try #require(window.summary.contributions.first)
    #expect(recovered.openingScan < window.baseline.id.sequence)
    let shared = row.attribution.ancestry.withUnsafeBufferPointer { left in
        recovered.attribution.ancestry.withUnsafeBufferPointer { right in
            left.baseAddress == right.baseAddress
        }
    }
    #expect(shared)
}

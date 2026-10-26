import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private enum CompletedStall: Error { case finished }

private final class ChurningPipeline: ProcessReading, AcquisitionClock, SessionRegistryReading, Sendable {
    struct State {
        var time = 0.0
        var tick = 0
        var oracle = CounterLedger()
        var cpu = 0.0
        var intervals = 0
        var sessionCPU: [String: Double] = [:]
        var sessionMemory: [String: UInt64] = [:]
    }
    let state = Mutex(State())
    let consumerEntered = ClockGate()
    let unitPublished = ClockGate()
    let collectionFinished = AsyncStream<Void>.makeStream()
    let finalTick: Int
    init(stallSeconds: Int) { finalTick = stallSeconds * 10 + 11 }

    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        try state.withLock { state in
            if state.tick > finalTick {
                collectionFinished.continuation.yield(())
                throw CompletedStall.finished
            }
            let tick = state.tick
            let generation = tick / 10
            let pids = Array(1...8) + (0..<5).map { 10_000 + generation * 5 + $0 }
            let samples = pids.map { pid in
                var value = sample(
                    Int32(pid), at: state.time,
                    cpu: Double(pid < 10_000 ? tick : tick % 10 + 1) / 1_000
                        * (pid.isMultiple(of: 2) ? 2 : 1), memory: UInt64(pid) * 1_000)
                value.executable = pid < 10_000 ? "/bin/worker" : "/bin/worker-\(pid)"
                if pid >= 10_000 { value.startedAt = Double(generation) - 0.05 }
                return value
            }
            let counters = state.oracle.ingest(samples, listedAt: state.time)
            state.cpu += counters.contributions.reduce(0) { $0 + $1.cpuSeconds }
            state.intervals += counters.contributions.reduce(0) { $0 + $1.intervalCount }
            for contribution in counters.contributions {
                let owner = contribution.id.closing.process.pid.isMultiple(of: 2) ? sessionA : sessionB
                state.sessionCPU[owner, default: 0] += contribution.cpuSeconds
            }
            if tick > 0 {
                for sample in samples {
                    let owner = sample.identity.pid.isMultiple(of: 2) ? sessionA : sessionB
                    state.sessionMemory[owner] = max(
                        state.sessionMemory[owner] ?? 0, sample.footprintBytes ?? 0)
                }
            }
            state.tick += 1
            return diagnosisScan(samples, at: state.time, scan: 0)
        }
    }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        ProcessMetadata(
            markers: [
                SessionMarker(
                    threadID: sample.identity.pid.isMultiple(of: 2) ? sessionA : sessionB, provider: .codex)
            ], status: .markerRead)
    }
    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        metadata(for: sample, includeCommand: false)
    }
    func output(of query: SessionRegistryQuery) throws -> Data { Data("[]".utf8) }
    func wait(until deadline: Double, wake: AcquisitionWake) throws {
        let seconds = max(0, deadline - monotonicNow())
        if state.withLock({ $0.tick == 11 }) {
            guard consumerEntered.wait(wake: wake) else { return }
        }
        let tick = state.withLock { $0.tick }
        if tick > 1, (tick - 1).isMultiple(of: 10) {
            guard unitPublished.wait(wake: wake) else { return }
        }
        state.withLock { $0.time += seconds }
    }
    func monotonicNow() -> Double { state.withLock { $0.time } }
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }
}

private final class AcknowledgedHistory: RecentActivityCollecting, Sendable {
    let store = RecentActivityStore()
    let published: ClockGate

    init(published: ClockGate) { self.published = published }

    func append(_ unit: RecentActivityUnit, current: [RecentWorkerRecord]?, present: Set<ProcessIdentity>?) {
        store.append(unit, current: current, present: present)
        published.signal()
    }

    func snapshot() -> RecentActivitySnapshot? { store.snapshot() }
}

@Test(.timeLimit(.minutes(2)))
func productionConsumerStallPreservesChurningAccountingAndHistory() async throws {
    // Thirteen workers fit prompt capture; every interval has known ownership without enrichment races.
    // Eighty seconds crosses history eviction; the smaller budget forces delivery compaction.
    let fixture = ChurningPipeline(stallSeconds: 80)
    // Only delivery is stalled here; DisplayCadenceTests separately blocks publication.
    // Acknowledgements keep instantaneous virtual scans from exhausting the unrelated ingress ring.
    let history = AcknowledgedHistory(published: fixture.unitPublished)
    let profile = PipelineProfile()
    let limits = MonitoringPipelineLimits(pendingObservations: 1_000)
    let pipeline = IndependentMonitoringPipeline(
        configuration: try MonitoringConfiguration(
            intervalSeconds: 0.1, samples: 0,
            scope: .allProcesses, collectAgentLoad: true, pipelineLimits: limits, reportIntervalSeconds: 5),
        reader: fixture, clock: fixture, registry: fixture, excluded: [], recentActivity: history,
        profile: profile)
    let reports = Mutex<[MonitoringSnapshot]>([])
    try await #require(throws: CompletedStall.self) {
        try await pipeline.run(thresholds: nil, interval: nil) { snapshot in
            let first = reports.withLock { values in
                values.append(snapshot)
                return values.count == 1
            }
            if first {
                fixture.consumerEntered.signal()
                for await _ in fixture.collectionFinished.stream { break }
            }
        }
    }
    #expect(fixture.state.withLock { $0.tick } == fixture.finalTick + 1)
    #expect(try #require(profile.snapshot().handoff).maximumQueuedUnits <= 1)
    let windows = reports.withLock { $0.compactMap(\.window) }
    #expect(windows.last?.finalScan == UInt64(fixture.finalTick))
    let cpu = windows.reduce(0) { sum, window in
        sum + window.contributions.reduce(0) { $0 + $1.cpuSeconds }
            + window.collapsedContributions.reduce(0) { $0 + $1.cpuSeconds }
    }
    let intervals = windows.reduce(0) { sum, window in
        sum + window.contributions.reduce(0) { $0 + $1.intervalCount }
            + window.collapsedContributions.reduce(0) { $0 + $1.intervalCount }
    }
    #expect(abs(cpu - fixture.state.withLock { $0.cpu }) < 1e-7)
    #expect(intervals == fixture.state.withLock { $0.intervals })
    #expect(windows.contains { !$0.collapsedContributions.isEmpty })
    var sessionCPU: [String: Double] = [:]
    for window in windows {
        for contribution in window.contributions {
            let owner = try #require(contribution.attribution.threadID)
            sessionCPU[owner, default: 0] += contribution.cpuSeconds
        }
        for contribution in window.collapsedContributions {
            #expect(contribution.category.categoryDetailsRetained)
            let owner = try #require(contribution.category.sessionID)
            sessionCPU[owner, default: 0] += contribution.cpuSeconds
        }
    }
    let expectedCPU = fixture.state.withLock { $0.sessionCPU }
    #expect(Set(sessionCPU.keys) == Set(expectedCPU.keys))
    for (owner, expected) in expectedCPU { #expect(abs((sessionCPU[owner] ?? 0) - expected) < 1e-7) }
    var sessionMemory: [String: UInt64] = [:]
    for report in reports.withLock({ $0 }) {
        let recent = try #require(report.recentActivity)
        for unit in recent.displayUnits {
            for record in unit.records {
                let owner = try #require(record.category.owner.sessionID)
                sessionMemory[owner] = max(sessionMemory[owner] ?? 0, record.maximumFootprint?.bytes ?? 0)
            }
            for record in unit.collapsedContributions {
                let owner = try #require(record.category.sessionID)
                sessionMemory[owner] = max(sessionMemory[owner] ?? 0, record.maximumFootprint?.bytes ?? 0)
            }
        }
    }
    #expect(sessionMemory == fixture.state.withLock { $0.sessionMemory })
    #expect(history.store.diagnostics.chargedRecords <= 65_536)
    let last = try #require(reports.withLock { $0.last })
    #expect(last.recentActivity?.currentContextAvailable == true)
    #expect(try #require(last.recentActivity).baselineScan > 0)
    #expect(last.observedFindings.filter { !$0.isHistorical }.count == 13)
}

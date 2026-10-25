import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private enum CompletedStall: Error { case finished }

private final class ChurningPipeline: ProcessReading, SamplingClock, SessionRegistryReading, Sendable {
    struct State {
        var time = 0.0
        var tick = 0
        var oracle = CounterLedger()
        var cpu = 0.0
        var intervals = 0
    }
    let state = Mutex(State())
    let consumerEntered = AsyncStream<Void>.makeStream()
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
            let pids = Array(1...200) + (0..<5).map { 10_000 + generation * 5 + $0 }
            let samples = pids.map { pid in
                var value = sample(
                    Int32(pid), at: state.time,
                    cpu: Double(pid < 10_000 ? tick : tick % 10 + 1) / 1_000)
                value.executable = pid < 10_000 ? "/bin/worker" : "/bin/worker-\(pid)"
                if pid >= 10_000 { value.startedAt = Double(generation) - 0.05 }
                return value
            }
            let counters = state.oracle.ingest(samples, listedAt: state.time)
            state.cpu += counters.contributions.reduce(0) { $0 + $1.cpuSeconds }
            state.intervals += counters.contributions.reduce(0) { $0 + $1.intervalCount }
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
    func wait(seconds: Double) async throws {
        try Task.checkCancellation()
        if state.withLock({ $0.tick == 11 }) {
            for await _ in consumerEntered.stream { break }
        }
        state.withLock { $0.time += seconds }
    }
    func monotonicNow() -> Double { state.withLock { $0.time } }
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }
}

@Test(.timeLimit(.minutes(5)), arguments: [60, 600])
func productionConsumerStallPreservesChurningAccountingAndHistory(seconds: Int) async throws {
    let fixture = ChurningPipeline(stallSeconds: seconds)
    let history = RecentActivityStore()
    let limits = MonitoringPipelineLimits(pendingObservations: 4_000)
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(
            intervalSeconds: 0.1, samples: 0,
            scope: .allProcesses, collectAgentLoad: true, pipelineLimits: limits, reportIntervalSeconds: 5),
        reader: fixture, clock: fixture, registry: fixture, recentActivity: history)
    let reports = Mutex<[MonitoringSnapshot]>([])
    await #expect(throws: CompletedStall.self) {
        try await session.run { snapshot in
            let first = reports.withLock { values in
                values.append(snapshot)
                return values.count == 1
            }
            if first {
                fixture.consumerEntered.continuation.yield(())
                for await _ in fixture.collectionFinished.stream { break }
            }
        }
    }
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
    if seconds == 600 { #expect(windows.contains { !$0.collapsedContributions.isEmpty }) }
    #expect(history.diagnostics.chargedRecords <= 65_536)
    let last = try #require(reports.withLock { $0.last })
    #expect(last.recentActivity?.currentContextAvailable == true)
    #expect(last.observedFindings.filter { !$0.isHistorical }.count == 205)
}

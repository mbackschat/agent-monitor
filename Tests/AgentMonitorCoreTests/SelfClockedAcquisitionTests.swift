import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private final class SelfClockFixture: ProcessReading, AcquisitionClock, Sendable {
    struct State {
        var time = 0.0
        var starts: [Double] = []
        var deadlines: [Double] = []
        var threads: Set<String> = []
    }
    let state = Mutex(State())
    let interval: LiveInterval?
    let waitEntered = AsyncStream<Void>.makeStream()
    let blockWait: Bool

    init(interval: LiveInterval? = nil, blockWait: Bool = false) {
        self.interval = interval
        self.blockWait = blockWait
    }
    func snapshot(excluding: Set<Int32>) -> ProcessSnapshot {
        state.withLock { state in
            let index = state.starts.count
            state.starts.append(state.time)
            state.threads.insert(Thread.current.name ?? "unnamed")
            if index == 2 { state.time += 0.35 }
            return diagnosisScan(
                [sample(42, at: state.time, cpu: Double(index) * 0.01)], at: state.time, scan: 0)
        }
    }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)], status: .markerRead)
    }
    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        metadata(for: sample, includeCommand: false)
    }
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }
    func monotonicNow() -> Double { state.withLock { $0.time } }
    func wait(until deadline: Double, wake: AcquisitionWake) {
        let first = state.withLock { state in
            state.threads.insert(Thread.current.name ?? "unnamed")
            state.deadlines.append(deadline)
            return state.deadlines.count == 1
        }
        waitEntered.continuation.yield(())
        if blockWait {
            wake.wait(seconds: 30)
        } else if first, let interval {
            interval.set(0.1)
        } else {
            state.withLock { $0.time = deadline }
        }
    }
}

@Suite struct SelfClockedAcquisitionTests {
    @Test func deadlinesAndReadsStayOnAcquisitionWithoutCatchUpScans() async throws {
        let reader = SelfClockFixture()
        let results = Mutex<[MonitoringSnapshot]>([])
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(intervalSeconds: 0.1, samples: 5),
            reader: reader, clock: reader)
        try await session.run { report in results.withLock { $0.append(report) } }
        let state = reader.state.withLock { $0 }
        #expect(state.threads == ["AgentMonitor acquisition"])
        #expect(state.starts.count == 6)
        #expect(zip(state.starts, [0.0, 0.1, 0.2, 0.55, 0.65, 0.75]).allSatisfy { abs($0 - $1) < 1e-9 })
        #expect(state.deadlines.count == 4)
        #expect(results.withLock { $0.count } == 5)
    }

    @Test func changedIntervalRecomputesDeadlineOnTheAcquisitionThread() async throws {
        let interval = LiveInterval(30)
        let reader = SelfClockFixture(interval: interval)
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(intervalSeconds: 30, samples: 1),
            reader: reader, clock: reader)
        let results = Mutex<[Double]>([])
        try await session.run(interval: interval) { report in
            results.withLock { $0.append(report.intervalSeconds) }
        }
        #expect(reader.state.withLock { $0.deadlines } == [30, 0.1])
        #expect(results.withLock { $0 } == [0.1])
    }

    @Test(.timeLimit(.minutes(1))) func cancellationWakesTheBlockingDeadline() async throws {
        let reader = SelfClockFixture(blockWait: true)
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(intervalSeconds: 30, samples: 0),
            reader: reader, clock: reader)
        let run = Task { try await session.run { _ in } }
        for await _ in reader.waitEntered.stream { break }
        let start = ContinuousClock.now
        run.cancel()
        await #expect(throws: CancellationError.self) { try await run.value }
        #expect(ContinuousClock.now - start < .seconds(2))
        #expect(reader.state.withLock { $0.starts.count } == 1)
    }
}

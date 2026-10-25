import Darwin
import Foundation
import Synchronization

/// Opt-in acceptance instrumentation accepts only fixed stage names and numeric durations.
/// CPU stamps must bracket synchronous work on one thread; worker and stage totals overlap.
package final class PipelineProfile: Sendable {
    enum Stage: String, CaseIterable, Sendable {
        case nativeSampling, promptCapture, counterAccounting, attribution
        case windowAccounting, historyClosure, historyProjection, pendingMerge, reportProjection
        case metadataBatch, providerRequest
    }
    enum Worker: String, CaseIterable, Sendable { case acquisition, metadata, providers }
    struct Stamp {
        let cpu = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        let wall = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
    }
    package struct Distribution: Encodable, Sendable {
        package let totalSeconds: Double
        package let maximumSeconds: Double
        package let p50Seconds: Double?
        package let p99Seconds: Double?
    }
    package struct Statistics: Encodable, Sendable {
        package let count: Int
        package let percentilesComplete: Bool
        package let cpu: Distribution
        package let wall: Distribution
    }
    package struct WorkerStatistics: Encodable, Sendable {
        package let threadCPUSeconds: Double?
        package let jobs: Statistics
    }
    package struct Snapshot: Encodable, Sendable {
        package let stages: [String: Statistics]
        package let workers: [String: WorkerStatistics]
    }
    private struct Samples {
        var count = 0
        var cpuTotal = 0.0
        var wallTotal = 0.0
        var cpuMax = 0.0
        var wallMax = 0.0
        var cpu: [Double] = []
        var wall: [Double] = []
        mutating func append(cpu: Double, wall: Double, limit: Int) {
            count += 1
            cpuTotal += cpu
            wallTotal += wall
            cpuMax = max(cpuMax, cpu)
            wallMax = max(wallMax, wall)
            if self.cpu.count < limit {
                self.cpu.append(cpu)
                self.wall.append(wall)
            }
        }
        var statistics: Statistics {
            let complete = count == cpu.count
            func distribution(_ values: [Double], total: Double, maximum: Double) -> Distribution {
                let sorted = complete ? values.sorted() : []
                func percentile(_ p: Double) -> Double? {
                    sorted.isEmpty ? nil : sorted[max(0, Int(ceil(Double(sorted.count) * p)) - 1)]
                }
                return Distribution(
                    totalSeconds: total, maximumSeconds: maximum,
                    p50Seconds: percentile(0.5), p99Seconds: percentile(0.99))
            }
            return Statistics(
                count: count, percentilesComplete: complete,
                cpu: distribution(cpu, total: cpuTotal, maximum: cpuMax),
                wall: distribution(wall, total: wallTotal, maximum: wallMax))
        }
    }
    private struct State {
        var stages: [Stage: Samples] = [:]
        var workers: [Worker: Samples] = [:]
        var threadCPU: [Worker: Double] = [:]
    }
    private let state = Mutex(State())
    private let sampleLimit: Int
    package init(sampleLimit: Int = 100_000) {
        precondition(sampleLimit > 0)
        self.sampleLimit = sampleLimit
    }
    func record(_ stage: Stage, cpu: Double, wall: Double) {
        state.withLock {
            $0.stages[stage, default: Samples()].append(cpu: cpu, wall: wall, limit: sampleLimit)
        }
    }
    func end(_ stage: Stage, since start: Stamp) {
        let end = Stamp()
        record(stage, cpu: Double(end.cpu - start.cpu) / 1e9, wall: Double(end.wall - start.wall) / 1e9)
    }
    func endJob(_ worker: Worker, since start: Stamp) {
        let end = Stamp()
        state.withLock {
            $0.workers[worker, default: Samples()].append(
                cpu: Double(end.cpu - start.cpu) / 1e9, wall: Double(end.wall - start.wall) / 1e9,
                limit: sampleLimit)
        }
    }
    func endThread(_ worker: Worker, since start: Stamp) {
        let cpu = Double(Stamp().cpu - start.cpu) / 1e9
        state.withLock { $0.threadCPU[worker, default: 0] += cpu }
    }
    package func snapshot() -> Snapshot {
        state.withLock { state in
            Snapshot(
                stages: Dictionary(
                    uniqueKeysWithValues: state.stages.map { ($0.key.rawValue, $0.value.statistics) }),
                workers: Dictionary(
                    uniqueKeysWithValues: Set(state.workers.keys).union(state.threadCPU.keys).map {
                        (
                            $0.rawValue,
                            WorkerStatistics(
                                threadCPUSeconds: state.threadCPU[$0],
                                jobs: state.workers[$0, default: Samples()].statistics)
                        )
                    }))
        }
    }
}

extension Optional where Wrapped == PipelineProfile {
    func measure<Value>(_ stage: PipelineProfile.Stage, _ body: () throws -> Value) rethrows -> Value {
        guard let profile = self else { return try body() }
        let stamp = PipelineProfile.Stamp()
        defer { profile.end(stage, since: stamp) }
        return try body()
    }
}

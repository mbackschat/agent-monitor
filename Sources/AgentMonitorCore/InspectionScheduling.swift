import Foundation
import Synchronization

/// Inspection is a run-local permission to attempt reads, not a sampling cadence.
/// Its generation catches pause/resume even when both happen between complete scans.
public final class LiveInspection: Sendable {
    struct State {
        var active: Bool
        var generation: UInt64 = 0
        var activations: UInt64
    }
    private struct Storage {
        var value: State
        var wake: AcquisitionWake?
        var terminal = InspectionCoverage()
    }
    private let state: Mutex<Storage>
    public init(active: Bool = false) {
        state = Mutex(Storage(value: State(active: active, activations: active ? 1 : 0)))
    }
    var value: State { state.withLock { $0.value } }
    /// Final unadmitted evidence, without a synthetic CPU window or cumulative history.
    public var terminalCoverage: InspectionCoverage { state.withLock { $0.terminal } }
    func finish(_ coverage: InspectionCoverage) { state.withLock { $0.terminal = coverage } }
    func setWake(_ wake: AcquisitionWake?) { state.withLock { $0.wake = wake } }
    public func set(_ active: Bool) {
        let wake = state.withLock { storage -> AcquisitionWake? in
            guard storage.value.active != active else { return nil }
            storage.value.generation += 1
            if active { storage.value.activations += 1 }
            storage.value.active = active
            return storage.wake
        }
        wake?.signal()
    }
}

struct InspectionRead: Sendable {
    let sample: ProcessSample
    let parent: ProcessIdentity?
    let cwd: String?
}

protocol InspectionReading: Sendable {
    func inspectionPIDs(allowance: InspectionAllowance) throws -> [Int32]
    func inspectionRead(_ pid: Int32, allowance: InspectionAllowance) -> InspectionRead?
}

/// Each native operation spends the same allowance, including context and verification reads.
/// A syscall already in flight cannot be preempted; lateness is recorded at its return.
final class InspectionAllowance: Sendable {
    private let remaining = Mutex(InspectionLimits.maximumNativeOperations)
    private let deadline: Double
    private let now: @Sendable () -> Double
    private let cancelled: @Sendable () -> Bool
    init(deadline: Double, now: @escaping @Sendable () -> Double, cancelled: @escaping @Sendable () -> Bool) {
        self.deadline = deadline
        self.now = now
        self.cancelled = cancelled
    }
    var available: Bool { !cancelled() && now() < deadline && remaining.withLock { $0 > 0 } }
    func permitsOperation() -> Bool {
        guard available else { return false }
        return remaining.withLock { count in
            guard count > 0 else { return false }
            count -= 1
            return true
        }
    }
}

struct InspectionScheduler: Sendable {
    var buffer = InspectionBuffer()
    private var listed: Set<Int32> = []
    private var generation: UInt64 = 0
    private var activations: UInt64 = 0
    private var startedActive = false
    private var rotation = 0
    private var prepared = false
    private var attempted = false

    mutating func prepare(census: ProcessSnapshot, inspection: LiveInspection) {
        buffer.discard()
        listed = Set(
            census.listedPIDs ?? census.samples.map(\.identity.pid) + census.nativeOutcomes.map(\.pid))
        let state = inspection.value
        generation = state.generation
        activations = state.activations
        startedActive = state.active
        prepared = census.listedPIDs != nil
        attempted = false
    }

    mutating func synchronize(_ inspection: LiveInspection) {
        if inspection.value.generation != generation {
            buffer.discard()
            listed.removeAll()
            prepared = false
            rotation = 0
        }
    }

    mutating func finish(_ inspection: LiveInspection) -> InspectionCoverage {
        buffer.discard()
        let coverage = takeCoverage(inspection: inspection)
        inspection.finish(coverage)
        return coverage
    }

    mutating func admit(at census: ProcessSnapshot, inspection: LiveInspection) -> [HeldInspectionObservation]
    {
        let state = inspection.value
        guard state.active, state.generation == generation else {
            buffer.discard()
            return []
        }
        return buffer.admit(at: census)
    }

    mutating func observe(
        reader: any InspectionReading, monitor: Monitor, since start: Double, nextDeadline: Double,
        now: @escaping @Sendable () -> Double, cancelled: @escaping @Sendable () -> Bool,
        inspection: LiveInspection, excluding: Set<Int32>
    ) throws {
        guard !attempted else { return }
        attempted = true
        let state = inspection.value
        guard state.active, state.generation == generation else {
            buffer.discard()
            return
        }
        buffer.coverage.mode = .enabled
        let deadline = min(
            start + InspectionLimits.offset + InspectionLimits.maximumSeconds,
            nextDeadline - InspectionLimits.deadlineReserve)
        guard prepared, now() < deadline else {
            buffer.coverage.opportunitiesSkipped += 1
            return
        }
        let allowance = InspectionAllowance(
            deadline: deadline, now: now,
            cancelled: {
                cancelled() || inspection.value.generation != state.generation
            })
        guard allowance.available else {
            buffer.coverage.opportunitiesSkipped += 1
            return
        }
        buffer.coverage.opportunitiesTaken += 1
        defer {
            buffer.coverage.maximumCompleteScanLateness = max(
                buffer.coverage.maximumCompleteScanLateness, max(0, now() - nextDeadline))
            synchronize(inspection)
        }
        let pids: [Int32]
        do { pids = try reader.inspectionPIDs(allowance: allowance) } catch {
            buffer.coverage.enumerationFailures += 1
            return
        }
        let candidates = pids.filter { !listed.contains($0) && !excluding.contains($0) }
        guard !candidates.isEmpty else { return }
        let first = rotation % candidates.count
        var attemptedReads = 0
        let roots = SessionCorroboration(monitor.findings())
        for offset in 0..<min(InspectionLimits.maximumReads, candidates.count) {
            guard allowance.available else { break }
            let pid = candidates[(first + offset) % candidates.count]
            attemptedReads += 1
            if let read = reader.inspectionRead(pid, allowance: allowance) {
                buffer.coverage.candidatesRead += 1
                _ = buffer.retain(
                    monitor.inspectionObservation(
                        read.sample, parent: read.parent, cwd: read.cwd, roots: roots))
            } else {
                buffer.coverage.candidatesFailed += 1
            }
        }
        rotation = (first + max(1, attemptedReads)) % candidates.count
        buffer.coverage.candidatesLeftUnread += candidates.count - attemptedReads
    }

    mutating func takeCoverage(inspection: LiveInspection) -> InspectionCoverage {
        var result = buffer.coverage
        let state = inspection.value
        if startedActive || state.activations != activations || result.mode != .disabled {
            result.mode = startedActive && state.active && state.generation == generation ? .enabled : .mixed
        }
        buffer.coverage = InspectionCoverage()
        return result
    }
}

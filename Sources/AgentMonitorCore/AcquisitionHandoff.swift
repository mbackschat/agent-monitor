import Synchronization

/// Only closed, attributed units cross this ring. Admission never merges, seals history or waits
/// for a consumer; the publication bridge owns that work (CPU-01 cadence boundary).
final class AcquisitionHandoff<Element: Sendable>: Sendable {
    private struct Entry: Sendable {
        let value: Element
        let size: MonitoringPayloadSize
    }
    private struct State {
        var ring: [Entry?]
        var head = 0
        var count = 0
        var size = MonitoringPayloadSize(observations: 0, textBytes: 0)
        var ended = false
        var error: (any Error)?
        var waiter: CheckedContinuation<Element?, any Error>?
    }
    private let state: Mutex<State>
    private let limits: MonitoringPipelineLimits

    private let profile: PipelineProfile?

    init(limits: MonitoringPipelineLimits, profile: PipelineProfile? = nil) {
        self.profile = profile
        self.limits = limits
        state = Mutex(State(ring: Array(repeating: nil, count: limits.pendingScans)))
        profile?.observeHandoff(units: 0, size: .init(observations: 0, textBytes: 0), limits: limits)
    }

    func send(_ value: Element, size: MonitoringPayloadSize, sequence: UInt64) throws {
        let waiter: CheckedContinuation<Element?, any Error>? = try state.withLock { state in
            guard !state.ended else { throw state.error ?? CancellationError() }
            guard state.count < limits.pendingScans,
                size.observations <= limits.pendingObservations - state.size.observations,
                size.textBytes <= limits.pendingTextBytes - state.size.textBytes
            else { throw MonitoringError.overloaded(stage: .publication, rejectedScan: sequence) }
            if let waiter = state.waiter {
                state.waiter = nil
                return waiter
            }
            state.ring[(state.head + state.count) % state.ring.count] = Entry(value: value, size: size)
            state.count += 1
            state.size.add(size)
            profile?.observeHandoff(units: state.count, size: state.size, limits: limits)
            return nil
        }
        waiter?.resume(returning: value)
    }

    func finish(throwing error: (any Error)? = nil) {
        let waiter = state.withLock { state in
            guard !state.ended else { return nil as CheckedContinuation<Element?, any Error>? }
            state.ended = true
            state.error = error
            defer { state.waiter = nil }
            return state.waiter
        }
        if let error { waiter?.resume(throwing: error) } else { waiter?.resume(returning: nil) }
    }

    /// Ends the stream with the failure that stopped acquisition after offering its drained
    /// partial unit. The offer is best effort: a full or closed ring must not replace that failure
    /// with a publication overload, which would misreport why collection stopped.
    func finish(
        throwing error: any Error,
        offering final: (value: Element, size: MonitoringPayloadSize, sequence: UInt64)?
    ) {
        if let final { try? send(final.value, size: final.size, sequence: final.sequence) }
        finish(throwing: error)
    }

    func cancel() { finish(throwing: CancellationError()) }

    var hasWaitingConsumer: Bool { state.withLock { $0.waiter != nil } }

    func next() async throws -> Element? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let result: Result<Element?, any Error>? = state.withLock { state in
                    if Task.isCancelled { return .failure(CancellationError()) }
                    if state.count > 0 {
                        let entry = state.ring[state.head]!
                        state.ring[state.head] = nil
                        state.head = (state.head + 1) % state.ring.count
                        state.count -= 1
                        state.size.subtract(entry.size)
                        return .success(entry.value)
                    }
                    if state.ended {
                        return state.error.map { .failure($0) } ?? .success(nil)
                    }
                    precondition(state.waiter == nil, "The acquisition handoff has one consumer")
                    state.waiter = continuation
                    return nil
                }
                if let result { continuation.resume(with: result) }
            }
        } onCancel: {
            self.cancel()
        }
    }
}

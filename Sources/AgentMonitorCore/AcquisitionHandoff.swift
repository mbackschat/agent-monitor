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

    init(limits: MonitoringPipelineLimits) {
        self.limits = limits
        state = Mutex(State(ring: Array(repeating: nil, count: limits.pendingScans)))
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

    func cancel() { finish(throwing: CancellationError()) }

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

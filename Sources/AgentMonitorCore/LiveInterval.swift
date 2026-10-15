import Synchronization

/// A sampling interval the user can change while a session waits.
///
/// Setting it wakes the waiting session, so a shorter interval applies at once without the
/// session polling for changes; a long-lived host must not wake on a timer just to look.
public final class LiveInterval: Sendable {
    private struct State {
        var seconds: Double
        var generation = 0
        var nextWaiter = 0
        var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    }

    private let state: Mutex<State>

    public init(_ seconds: Double) { state = Mutex(State(seconds: seconds)) }

    public var seconds: Double { state.withLock { $0.seconds } }

    public func set(_ seconds: Double) {
        let waiters = state.withLock { state in
            state.seconds = seconds
            state.generation += 1
            defer { state.waiters = [:] }
            return Array(state.waiters.values)
        }
        for waiter in waiters { waiter.resume() }
    }

    /// The current value with the generation that `changed(after:)` compares against.
    func current() -> (seconds: Double, generation: Int) {
        state.withLock { ($0.seconds, $0.generation) }
    }

    /// Returns once the interval is set after `generation`, or when the task is cancelled.
    func changed(after generation: Int) async {
        let id = state.withLock { state in
            defer { state.nextWaiter += 1 }
            return state.nextWaiter
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Registration and the cancellation handler share the lock, and cancellation is
                // flagged before its handler runs, so neither order loses the wake-up.
                let resumeNow = state.withLock { state in
                    guard state.generation == generation, !Task.isCancelled else { return true }
                    state.waiters[id] = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            state.withLock { $0.waiters.removeValue(forKey: id) }?.resume()
        }
    }
}

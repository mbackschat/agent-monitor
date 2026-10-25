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
        var observers: [Int: @Sendable () -> Void] = [:]
    }

    private let state: Mutex<State>

    public init(_ seconds: Double) { state = Mutex(State(seconds: seconds)) }

    public var seconds: Double { state.withLock { $0.seconds } }

    public func set(_ seconds: Double) {
        let (waiters, observers) = state.withLock { state in
            guard state.seconds != seconds else {
                return ([CheckedContinuation<Void, Never>](), [@Sendable () -> Void]())
            }
            state.seconds = seconds
            state.generation += 1
            defer { state.waiters = [:] }
            return (Array(state.waiters.values), Array(state.observers.values))
        }
        for waiter in waiters { waiter.resume() }
        for observer in observers { observer() }
    }

    func observe(_ changed: @escaping @Sendable () -> Void) -> Int {
        state.withLock { state in
            let id = state.nextWaiter
            state.nextWaiter += 1
            state.observers[id] = changed
            return id
        }
    }

    func removeObserver(_ id: Int) {
        _ = state.withLock { $0.observers.removeValue(forKey: id) }
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

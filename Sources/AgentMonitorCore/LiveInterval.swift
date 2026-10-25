import Synchronization

public final class LiveInterval: Sendable {
    private struct State {
        var seconds: Double
        var nextObserver = 0
        var observers: [Int: @Sendable () -> Void] = [:]
    }
    private let state: Mutex<State>
    public init(_ seconds: Double) { state = Mutex(State(seconds: seconds)) }
    public var seconds: Double { state.withLock { $0.seconds } }

    public func set(_ seconds: Double) {
        let observers = state.withLock { state -> [@Sendable () -> Void] in
            guard state.seconds != seconds else { return [] }
            state.seconds = seconds
            return Array(state.observers.values)
        }
        for observer in observers { observer() }
    }
    func observe(_ changed: @escaping @Sendable () -> Void) -> Int {
        state.withLock { state in
            let id = state.nextObserver
            state.nextObserver += 1
            state.observers[id] = changed
            return id
        }
    }
    func removeObserver(_ id: Int) {
        _ = state.withLock { $0.observers.removeValue(forKey: id) }
    }
}

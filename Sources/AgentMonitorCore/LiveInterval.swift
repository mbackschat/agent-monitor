import Synchronization

public final class LiveInterval: Sendable {
    private struct State {
        var settings: SamplingSettings
        var panelVisible = true
        var openings: UInt64 = 0
        var nextObserver = 0
        var observers: [Int: @Sendable () -> Void] = [:]
    }
    private let state: Mutex<State>
    public init(_ seconds: Double) {
        state = Mutex(State(settings: SamplingSettings(visibleMaximum: seconds)))
    }
    public init(settings: SamplingSettings) { state = Mutex(State(settings: settings)) }
    public var seconds: Double { settings.visibleMaximum }
    public var settings: SamplingSettings { state.withLock { $0.settings } }
    public var panelVisible: Bool { state.withLock { $0.panelVisible } }

    struct Value: Equatable, Sendable {
        var settings: SamplingSettings
        var panelVisible: Bool
        var openings: UInt64 = 0
    }
    var value: Value {
        state.withLock { Value(settings: $0.settings, panelVisible: $0.panelVisible, openings: $0.openings) }
    }

    public func set(_ seconds: Double) {
        let observers = state.withLock { state -> [@Sendable () -> Void] in
            guard state.settings.visibleMaximum != seconds else { return [] }
            state.settings.visibleMaximum = seconds
            return Array(state.observers.values)
        }
        for observer in observers { observer() }
    }

    @discardableResult public func setSettings(_ settings: SamplingSettings) -> Bool {
        guard settings.isValid else { return false }
        let observers = state.withLock { state -> [@Sendable () -> Void] in
            guard state.settings != settings else { return [] }
            state.settings = settings
            return Array(state.observers.values)
        }
        for observer in observers { observer() }
        return true
    }

    public func setPanelVisible(_ visible: Bool) {
        let observers = state.withLock { state -> [@Sendable () -> Void] in
            guard state.panelVisible != visible else { return [] }
            state.panelVisible = visible
            if visible { state.openings &+= 1 }
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

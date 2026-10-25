import Synchronization

@testable import AgentMonitorCore

final class ClockGate: Sendable {
    private struct State {
        var permits = 0
        var waiter: AcquisitionWake?
    }
    private let state = Mutex(State())
    func signal() {
        let wake = state.withLock { state in
            state.permits += 1
            return state.waiter
        }
        wake?.signal()
    }
    func wait(wake: AcquisitionWake) -> Bool {
        let ready = state.withLock { state in
            if state.permits > 0 {
                state.permits -= 1
                return true
            }
            state.waiter = wake
            return false
        }
        if ready { return true }
        wake.wait(seconds: 30)
        return state.withLock { state in
            state.waiter = nil
            guard state.permits > 0 else { return false }
            state.permits -= 1
            return true
        }
    }
}

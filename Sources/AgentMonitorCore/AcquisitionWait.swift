import Foundation

/// The real clock waits on the acquisition thread; deterministic clocks may implement the same
/// boundary without sleeping. Async-only injected clocks retain the asynchronous test adapter.
protocol BlockingSamplingClock: SamplingClock {
    func wait(until deadline: Double, wake: AcquisitionWake) throws
}

final class AcquisitionWake: Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    func signal() { semaphore.signal() }
    func wait(seconds: Double) {
        _ = semaphore.wait(timeout: .now() + max(0, seconds))
    }
}

extension ContinuousSamplingClock: BlockingSamplingClock {
    func wait(until deadline: Double, wake: AcquisitionWake) {
        wake.wait(seconds: deadline - monotonicNow())
    }
}

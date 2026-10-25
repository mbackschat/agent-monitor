import Foundation

/// Acquisition and deterministic clocks share the same synchronous deadline and wake boundary.
public protocol AcquisitionClock: SamplingClock {
    func wait(until deadline: Double, wake: AcquisitionWake) throws
}

public final class AcquisitionWake: Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    public func signal() { semaphore.signal() }
    public func wait(seconds: Double) {
        _ = semaphore.wait(timeout: .now() + max(0, seconds))
    }
}

extension ContinuousSamplingClock: AcquisitionClock {
    public func wait(until deadline: Double, wake: AcquisitionWake) {
        wake.wait(seconds: deadline - monotonicNow())
    }
}

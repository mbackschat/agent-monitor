public struct CPUAccounting: Equatable, Sendable {
    public let hostBusyPercent: Double?
    public let logicalCPUCount: Int
    public let measuredUserPercent: Double
    public let unmeasuredLifetimeCount: Int
    public let previousScanSeconds: Double?

    public init(
        hostBusyPercent: Double?, logicalCPUCount: Int, measuredUserPercent: Double,
        unmeasuredLifetimeCount: Int, previousScanSeconds: Double?
    ) {
        self.hostBusyPercent = hostBusyPercent
        self.logicalCPUCount = logicalCPUCount
        self.measuredUserPercent = measuredUserPercent
        self.unmeasuredLifetimeCount = unmeasuredLifetimeCount
        self.previousScanSeconds = previousScanSeconds
    }
}

public struct HostCPUTicks: Equatable, Sendable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public struct HostCPUCounters: Equatable, Sendable {
    public let processors: [HostCPUTicks]

    public init(processors: [HostCPUTicks]) { self.processors = processors }

    func busyPercent(since previous: HostCPUCounters?) -> Double? {
        guard let previous, !processors.isEmpty, processors.count == previous.processors.count else {
            return nil
        }
        var busy: UInt64 = 0
        var idle: UInt64 = 0
        for (current, old) in zip(processors, previous.processors) {
            // Check before summing: another CPU's increase can hide a 32-bit wrap.
            guard current.user >= old.user, current.system >= old.system,
                current.idle >= old.idle, current.nice >= old.nice
            else { return nil }
            busy +=
                UInt64(current.user - old.user) + UInt64(current.system - old.system)
                + UInt64(current.nice - old.nice)
            idle += UInt64(current.idle - old.idle)
        }
        guard busy + idle > 0 else { return nil }
        return 100 * Double(processors.count) * Double(busy) / Double(busy + idle)
    }
}

public protocol HostCPUReading: Sendable {
    func read() -> HostCPUCounters?
}

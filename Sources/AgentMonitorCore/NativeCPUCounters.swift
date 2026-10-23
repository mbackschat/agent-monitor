public struct NativeCPUCounters: Equatable, Sendable {
    public let user: UInt64
    public let system: UInt64
    public let numerator: UInt32
    public let denominator: UInt32

    func seconds(user: UInt64, system: UInt64) -> Double {
        ResourceMath.seconds(ticks: user, numerator: numerator, denominator: denominator)
            + ResourceMath.seconds(ticks: system, numerator: numerator, denominator: denominator)
    }

    public var seconds: Double { seconds(user: user, system: system) }
}

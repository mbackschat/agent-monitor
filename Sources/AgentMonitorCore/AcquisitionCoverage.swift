/// Timing coverage across all accepted scans, so a later on-time scan cannot hide an earlier gap.
public struct AcquisitionCoverage: Equatable, Codable, Sendable {
    public private(set) var scanCount = 0
    public private(set) var timedPeriodCount = 0
    public private(set) var maximumGapSeconds: Double?
    public private(set) var overrunCount = 0

    public init() {}

    mutating func append(_ timing: AcquisitionTiming?) {
        scanCount += 1
        guard let timing, let period = timing.achievedPeriodSeconds else { return }
        timedPeriodCount += 1
        maximumGapSeconds = max(maximumGapSeconds ?? period, period)
        if period > timing.requestedPeriodSeconds * 1.5 { overrunCount += 1 }
    }

    public mutating func merge(_ other: Self) {
        scanCount += other.scanCount
        timedPeriodCount += other.timedPeriodCount
        overrunCount += other.overrunCount
        if let gap = other.maximumGapSeconds { maximumGapSeconds = max(maximumGapSeconds ?? gap, gap) }
    }
}

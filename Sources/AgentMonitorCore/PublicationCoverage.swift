/// Closed-unit resolution, independent of ordinary display-window aggregation.
/// Counts and enclosing spans remain bounded even through arbitrarily many publication merges.
public struct PublicationCoverage: Equatable, Codable, Sendable {
    public private(set) var sourceUnitCount = 0
    public private(set) var publishedUnitCount = 0
    public private(set) var coalescedUnitCount = 0
    public private(set) var maximumUnitSpanSeconds = 0.0
    public private(set) var coalescedStartedAt: Double?
    public private(set) var coalescedEndedAt: Double?

    public init() {}

    init(start: Double, end: Double) {
        sourceUnitCount = 1
        publishedUnitCount = 1
        maximumUnitSpanSeconds = max(0, end - start)
    }

    public mutating func merge(_ other: Self) {
        sourceUnitCount += other.sourceUnitCount
        publishedUnitCount += other.publishedUnitCount
        coalescedUnitCount += other.coalescedUnitCount
        maximumUnitSpanSeconds = max(maximumUnitSpanSeconds, other.maximumUnitSpanSeconds)
        if let start = other.coalescedStartedAt {
            coalescedStartedAt = min(coalescedStartedAt ?? start, start)
        }
        if let end = other.coalescedEndedAt { coalescedEndedAt = max(coalescedEndedAt ?? end, end) }
    }

    mutating func coalesce(start: Double, end: Double) {
        publishedUnitCount = 1
        coalescedUnitCount = sourceUnitCount
        maximumUnitSpanSeconds = max(0, end - start)
        coalescedStartedAt = start
        coalescedEndedAt = end
    }
}

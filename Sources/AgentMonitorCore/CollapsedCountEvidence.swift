/// Monotonic provenance for count bounds, never wall-clock process identity timestamps.
/// Missing readings poison the bound: a later observation cannot bound an earlier unknown one.
struct LifetimeObservationTicks: Sendable {
    private(set) var birth: UInt64?
    private(set) var latest: UInt64?

    init(_ sample: ProcessSample) {
        latest = sample.sampledAtTicks.flatMap { $0 > 0 ? $0 : nil }
        birth = sample.startedAtTicks.flatMap { start in
            guard let latest, start > 0, start <= latest else { return nil }
            return start
        }
    }

    mutating func merge(_ other: Self) {
        birth = birth.flatMap { first in other.birth.map { min(first, $0) } }
        latest = latest.flatMap { first in other.latest.map { max(first, $0) } }
    }

    func wasBorn(after boundary: UInt64?) -> Bool {
        guard let birth, let boundary else { return false }
        return birth > boundary
    }
}

/// The boundary is private accounting state; released worker identities are not retained.
struct CollapsedWindowRecord: Sendable {
    var resources: CollapsedContribution
    var latestObservationTicks: UInt64?

    mutating func merge(_ other: Self, newProcesses: Int = 0, newWorkers: Int = 0) {
        resources.merge(other.resources, newProcesses: newProcesses, newWorkers: newWorkers)
        latestObservationTicks = latestObservationTicks.flatMap { first in
            other.latestObservationTicks.map { max(first, $0) }
        }
    }

    func droppingCategoryDetail() -> Self {
        Self(resources: resources.droppingCategoryDetail(), latestObservationTicks: latestObservationTicks)
    }
}

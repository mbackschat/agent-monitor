import Foundation

struct SamplingObservation: Sendable {
    var pid: Int32
    var identity: ProcessIdentity?
    var birth: Double?
    var eligible: Bool
    var countersAvailable: Bool
    var historical = false
}

struct SamplingEvidence: Sendable {
    private struct Lifetime: Sendable {
        var identity: ProcessIdentity?
        var eligible: Bool
        var countersAvailable: Bool
    }
    private var previousListing: Double?
    private var lifetimes: [Int32: Lifetime] = [:]

    mutating func ingest(
        _ observations: [SamplingObservation], contributions: [CPUContribution],
        listedAt: Double, closedAt: Double, window: Double, unidentifiedFailures: Bool
    ) -> (aggregate: AdaptiveSamplingController.Aggregate, uncertain: Bool) {
        var aggregate = AdaptiveSamplingController.Aggregate(
            opening: previousListing ?? listedAt, closing: closedAt)
        var current: [Int32: Lifetime] = [:]
        var eligible: [ProcessIdentity: SamplingObservation] = [:]
        var uncertain = unidentifiedFailures
        for observation in observations {
            let previous = lifetimes[observation.pid]
            let replacement =
                previous?.identity != nil && observation.identity != nil
                && previous?.identity != observation.identity
            if observation.eligible {
                if let identity = observation.identity { eligible[identity] = observation }
                if previousListing != nil && (previous == nil || replacement) { aggregate.arrivals += 1 }
                if !observation.countersAvailable { uncertain = true }
                if observation.countersAvailable && previous?.countersAvailable == false && !replacement {
                    aggregate.recovery = true
                }
            }
            if replacement && previous?.eligible == true { aggregate.event = true }
            if !observation.historical {
                current[observation.pid] = Lifetime(
                    identity: observation.identity ?? previous?.identity,
                    eligible: observation.eligible, countersAvailable: observation.countersAvailable)
            }
        }
        for (pid, previous) in lifetimes where current[pid] == nil && previous.eligible {
            aggregate.event = true
        }
        for contribution in contributions {
            guard let observation = eligible[contribution.id.closing.process] else { continue }
            aggregate.cpu += contribution.cpuSeconds
            aggregate.opening = min(aggregate.opening, contribution.startedAt)
            let young =
                observation.birth.map {
                    let age = contribution.endedAt - $0
                    return !age.isFinite || age < 0 || age <= window
                } ?? true
            if young {
                aggregate.youngCPU += contribution.cpuSeconds
            }
        }
        aggregate.event = aggregate.event || aggregate.arrivals > 0
        previousListing = listedAt
        lifetimes = current
        return (aggregate, uncertain)
    }
}

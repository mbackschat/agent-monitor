import Foundation

@testable import AgentMonitorCore

// Inject completed resolver results, never infer a child's resolution from a negative parent.
struct AdaptiveSamplingEvidence {
    enum Resolution: Sendable { case pending, negative, point, uncertain, supported }
    enum Read: Equatable, Sendable {
        case available
        case failure(code: Int, verified: Bool)
    }
    struct Observation: Sendable {
        let pid: Int32
        var identity: ProcessIdentity?
        var birth: Double?
        var resolution: Resolution?
        var invalidated = false
        var inScope = true
        var provenHelper = false
        var read: Read = .available
    }
    struct Output {
        var aggregate: AdaptiveSamplingPrototype.Aggregate
        var uncertain = false
        var persistentlyUnreadable = 0
    }
    var relaxPersistentFailures = false
    private var previousListing: Double?
    private var listingUnavailable = false
    private struct Lifetime {
        var observation: Observation
        var verifiedIdentity: ProcessIdentity?
        var resolution: Resolution = .pending
        var failureStart: Double?
        var failureCount = 0
        var eligible: Bool {
            observation.inScope && !observation.provenHelper
                && (observation.identity == nil || resolution != .negative)
        }
    }
    private var lifetimes: [Int32: Lifetime] = [:]

    init(relaxPersistentFailures: Bool = false) {
        self.relaxPersistentFailures = relaxPersistentFailures
    }

    mutating func ingest(
        _ observations: [Observation], contributions: [CPUContribution] = [],
        listedAt: Double, closedAt: Double, window: Double = 60, listingSucceeded: Bool = true
    ) -> Output {
        var output = Output(aggregate: .init(opening: previousListing ?? listedAt, closing: closedAt))
        guard listingSucceeded else {
            listingUnavailable = true
            output.uncertain = true
            return output
        }
        var current: [Int32: Lifetime] = [:]
        for observation in observations {
            let prior = lifetimes[observation.pid]
            let replaced =
                prior?.verifiedIdentity != nil && observation.identity != nil
                && prior?.verifiedIdentity != observation.identity
            let continuous = !replaced
            var lifetime =
                continuous
                ? (prior ?? Lifetime(observation: observation)) : Lifetime(observation: observation)
            let oldRead = lifetime.observation.read
            if observation.invalidated { lifetime = Lifetime(observation: observation) }
            lifetime.observation = observation
            if let identity = observation.identity { lifetime.verifiedIdentity = identity }
            if let resolution = observation.resolution, resolution != .pending {
                lifetime.resolution = resolution
            }
            if previousListing != nil {
                if (prior == nil || replaced) && lifetime.eligible { output.aggregate.arrivals += 1 }
                if replaced && prior?.eligible == true { output.aggregate.event = true }
            }
            switch observation.read {
            case .available:
                if lifetime.eligible
                    && (listingUnavailable
                        || (oldRead != .available && continuous && !observation.invalidated))
                {
                    output.aggregate.recovery = true
                }
                lifetime.failureStart = nil
                lifetime.failureCount = 0
            case .failure(_, let verified):
                if oldRead != observation.read || lifetime.failureStart == nil {
                    lifetime.failureStart = closedAt
                    lifetime.failureCount = 0
                }
                lifetime.failureCount += 1
                let persistent =
                    relaxPersistentFailures && verified && observation.identity != nil
                    && lifetime.failureCount >= 3 && closedAt - (lifetime.failureStart ?? closedAt) >= 5
                if lifetime.eligible {
                    output.uncertain = output.uncertain || !persistent
                    if persistent { output.persistentlyUnreadable += 1 }
                }
            }
            current[observation.pid] = lifetime
        }
        for (pid, prior) in lifetimes where current[pid] == nil && prior.eligible {
            output.aggregate.event = true
        }
        for contribution in contributions {
            let id = contribution.id.closing.process
            guard let lifetime = current[id.pid], lifetime.observation.identity == id, lifetime.eligible
            else { continue }
            output.aggregate.cpu += contribution.cpuSeconds
            output.aggregate.opening = min(output.aggregate.opening, contribution.startedAt)
            let young =
                lifetime.observation.birth.map {
                    $0 > contribution.endedAt || contribution.endedAt - $0 <= window
                } ?? true
            if young {
                output.aggregate.youngCPU += contribution.cpuSeconds
            }
        }
        output.aggregate.event = output.aggregate.event || output.aggregate.arrivals > 0
        previousListing = listedAt
        listingUnavailable = false
        lifetimes = current
        return output
    }
}

import Foundation

public struct AcquisitionScanID: Hashable, Sendable {
    public let runID: UUID
    public let sequence: UInt64
}

public struct CounterObservationID: Hashable, Sendable {
    public let scan: AcquisitionScanID
    public let process: ProcessIdentity
}

public enum CPUOpeningReference: Hashable, Sendable {
    case observation(CounterObservationID)
    case newbornZero(listing: AcquisitionScanID, verifiedBirth: Double)

    public var scan: AcquisitionScanID {
        switch self {
        case .observation(let id): id.scan
        case .newbornZero(let listing, _): listing
        }
    }
}

/// Endpoints identify accepted work independently of attribution and report refreshes.
/// See docs/architecture.md#retained-counter-accounting for boundary exclusions.
public struct CPUContribution: Equatable, Sendable {
    public struct ID: Hashable, Sendable {
        public let opening: CPUOpeningReference
        public let closing: CounterObservationID
    }

    public let id: ID
    public let cpuSeconds: Double
    public let startedAt: Double
    public let endedAt: Double
    public let executableChanged: Bool

    init(id: ID, cpuSeconds: Double, startedAt: Double, endedAt: Double, executableChanged: Bool = false) {
        self.id = id
        self.cpuSeconds = cpuSeconds
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.executableChanged = executableChanged
    }

    public var observedSeconds: Double { endedAt - startedAt }
    public var cpuPercent: Double { 100 * cpuSeconds / observedSeconds }
    public var spansMissingScans: Bool { id.closing.scan.sequence - id.opening.scan.sequence > 1 }
}

public enum CounterExclusionReason: Error, Equatable, Sendable {
    case counterUnavailable, invalidCounter, invalidTime, counterReset, incompatibleCounters
    case initialBaseline, birthUnavailable, preexistingLifetime, historyEvicted
}

public struct CounterExclusion: Equatable, Sendable {
    public let observation: CounterObservationID
    public let reason: CounterExclusionReason
}

public struct CounterObservation: Sendable {
    public let id: CounterObservationID
    public let sample: ProcessSample
}

public struct CounterScan: Sendable {
    public static let acceptanceVersion = 1
    public let observations: [CounterObservation]
    public let source: ProcessSnapshot?
    public var nativeOutcomes: [NativeCounterOutcome] { source?.nativeOutcomes ?? [] }
    public var nativeTiming: NativeScanTiming? { source?.nativeTiming }
    public let id: AcquisitionScanID
    public let listedAt: Double?
    public let endedAt: Double?
    public let contributions: [CPUContribution]
    public let exclusions: [CounterExclusion]
    public let evictedBaselines: [ProcessIdentity]
}

/// Retains counter baselines independently of the live attribution graph.
/// Eviction advances a conservative birth floor instead of keeping unbounded tombstones.
struct CounterLedger: Sendable {
    private struct Baseline: Sendable {
        let id: CounterObservationID
        let sampledAt: Double
        let cpu: Double
        let raw: NativeCPUCounters?
        let executable: String
        let name: String
    }

    private struct State: Sendable {
        var baseline: Baseline?
        var canUseNewbornOpening = true
        var lastSeen: UInt64
        var lastReadAt: Double
    }

    private struct Listing: Sendable {
        let id: AcquisitionScanID
        let time: Double
    }

    let runID: UUID
    private let maximumBaselines: Int
    private let maximumListings: Int
    private var sequence: UInt64 = 0
    private var initialListing: Double?
    private var newbornFloor: Double = -.infinity
    private var states: [ProcessIdentity: State] = [:]
    private var listings: [Listing] = []

    init(runID: UUID = UUID(), maximumBaselines: Int = 8_192, maximumListings: Int = 4_096) {
        precondition(maximumBaselines > 0 && maximumListings > 0)
        self.runID = runID
        self.maximumBaselines = maximumBaselines
        self.maximumListings = maximumListings
    }

    var retainedBaselineCount: Int { states.count }
    var retainedListingCount: Int { listings.count }

    mutating func ingest(
        _ samples: [ProcessSample], listedAt: Double?, scanSeconds: Double = 0,
        source: ProcessSnapshot? = nil
    ) -> CounterScan {
        let scan = AcquisitionScanID(runID: runID, sequence: sequence)
        sequence += 1
        if scan.sequence == 0 { initialListing = listedAt }
        if let listedAt, listedAt.isFinite { listings.append(Listing(id: scan, time: listedAt)) }
        var contributions: [CPUContribution] = []
        var exclusions: [CounterExclusion] = []
        let observations = samples.map {
            CounterObservation(id: CounterObservationID(scan: scan, process: $0.identity), sample: $0)
        }
        for observation in observations {
            let sample = observation.sample
            var state =
                states[sample.identity]
                ?? State(
                    lastSeen: scan.sequence,
                    lastReadAt: sample.sampledAt.isFinite ? sample.sampledAt : .infinity)
            state.lastSeen = scan.sequence
            if sample.sampledAt.isFinite { state.lastReadAt = max(state.lastReadAt, sample.sampledAt) }
            switch accept(observation, state: &state) {
            case .success(let contribution): contributions.append(contribution)
            case .failure(let reason):
                exclusions.append(CounterExclusion(observation: observation.id, reason: reason))
            }
            states[sample.identity] = state
        }
        let evicted = evictBaselines()
        if listings.count > maximumListings { listings.removeFirst(listings.count - maximumListings) }
        return CounterScan(
            observations: observations, source: source,
            id: scan, listedAt: listedAt, endedAt: listedAt.map { $0 + scanSeconds },
            contributions: contributions, exclusions: exclusions, evictedBaselines: evicted)
    }

    private func accept(_ observation: CounterObservation, state: inout State)
        -> Result<CPUContribution, CounterExclusionReason>
    {
        let sample = observation.sample
        guard let cpu = sample.rawCPU?.seconds ?? sample.cpuSeconds else {
            return .failure(.counterUnavailable)
        }
        guard cpu.isFinite, cpu >= 0 else {
            state.baseline = nil
            state.canUseNewbornOpening = false
            return .failure(.invalidCounter)
        }
        guard sample.sampledAt.isFinite else { return .failure(.invalidTime) }
        let next = Baseline(
            id: observation.id, sampledAt: sample.sampledAt, cpu: cpu, raw: sample.rawCPU,
            executable: sample.executable, name: sample.name)
        if let old = state.baseline {
            guard sample.sampledAt > old.sampledAt, observation.id.scan.sequence > old.id.scan.sequence else {
                return .failure(.invalidTime)
            }
            state.baseline = next
            let delta: Double
            switch (old.raw, sample.rawCPU) {
            case (.some(let before), .some(let after)):
                guard before.numerator == after.numerator, before.denominator == after.denominator else {
                    return .failure(.incompatibleCounters)
                }
                guard after.user >= before.user, after.system >= before.system else {
                    return .failure(.counterReset)
                }
                delta = after.seconds(user: after.user - before.user, system: after.system - before.system)
            case (.none, .none):
                guard cpu >= old.cpu else { return .failure(.counterReset) }
                delta = cpu - old.cpu
            case (.some, .none), (.none, .some): return .failure(.incompatibleCounters)
            }
            return .success(
                CPUContribution(
                    id: .init(opening: .observation(old.id), closing: observation.id), cpuSeconds: delta,
                    startedAt: old.sampledAt, endedAt: sample.sampledAt,
                    executableChanged: old.executable != sample.executable || old.name != sample.name))
        }
        let canUseNewbornOpening = state.canUseNewbornOpening
        state.baseline = next
        state.canUseNewbornOpening = false
        guard canUseNewbornOpening, observation.id.scan.sequence > 0 else {
            return .failure(.initialBaseline)
        }
        guard let birth = sample.startedAt, birth.isFinite, birth <= sample.sampledAt else {
            return .failure(.birthUnavailable)
        }
        guard let initialListing, birth > initialListing else { return .failure(.preexistingLifetime) }
        guard birth > newbornFloor, let opening = listings.last(where: { $0.time < birth }) else {
            return .failure(.historyEvicted)
        }
        return .success(
            CPUContribution(
                id: .init(
                    opening: .newbornZero(listing: opening.id, verifiedBirth: birth), closing: observation.id),
                cpuSeconds: cpu, startedAt: opening.time, endedAt: sample.sampledAt))
    }

    private mutating func evictBaselines() -> [ProcessIdentity] {
        guard states.count > maximumBaselines else { return [] }
        let oldest = states.sorted {
            if $0.value.lastSeen != $1.value.lastSeen { return $0.value.lastSeen < $1.value.lastSeen }
            if $0.key.pid != $1.key.pid { return $0.key.pid < $1.key.pid }
            return $0.key.startMicroseconds < $1.key.startMicroseconds
        }.prefix(states.count - maximumBaselines)
        for (identity, state) in oldest {
            newbornFloor = max(newbornFloor, state.lastReadAt)
            states[identity] = nil
        }
        return oldest.map(\.key)
    }
}

public enum CounterWindowError: Error { case invalidBounds, incompatibleContribution }

/// Projects unique deltas onto a scan window; recovered CPU is excluded from its rate.
/// Wider windows re-evaluate endpoints instead of summing percentages.
public struct CounterWindow: Sendable {
    public let contributions: [CPUContribution]
    public let recovered: [CPUContribution]
    public let observedSeconds: Double
    public var cpuSeconds: Double? {
        contributions.isEmpty ? nil : contributions.reduce(0) { $0 + $1.cpuSeconds }
    }
    public var cpuPercent: Double? { cpuSeconds.map { 100 * $0 / observedSeconds } }

    public init(baseline: CounterScan, final: CounterScan, contributions: [CPUContribution]) throws {
        guard baseline.id.runID == final.id.runID, baseline.id.sequence < final.id.sequence,
            let start = baseline.listedAt, let end = final.endedAt,
            start.isFinite, end.isFinite, end > start
        else { throw CounterWindowError.invalidBounds }
        var unique: [CPUContribution.ID: CPUContribution] = [:]
        for contribution in contributions {
            guard contribution.id.opening.scan.runID == baseline.id.runID,
                contribution.id.closing.scan.runID == baseline.id.runID
            else { throw CounterWindowError.incompatibleContribution }
            if let previous = unique[contribution.id], previous != contribution {
                throw CounterWindowError.incompatibleContribution
            }
            unique[contribution.id] = contribution
        }
        let members = unique.values.filter {
            $0.id.closing.scan.sequence > baseline.id.sequence
                && $0.id.closing.scan.sequence <= final.id.sequence
        }.sorted {
            if $0.id.closing.scan.sequence != $1.id.closing.scan.sequence {
                return $0.id.closing.scan.sequence < $1.id.closing.scan.sequence
            }
            if $0.id.closing.process.pid != $1.id.closing.process.pid {
                return $0.id.closing.process.pid < $1.id.closing.process.pid
            }
            return $0.id.closing.process.startMicroseconds < $1.id.closing.process.startMicroseconds
        }
        self.contributions = members.filter { $0.id.opening.scan.sequence >= baseline.id.sequence }
        recovered = members.filter { $0.id.opening.scan.sequence < baseline.id.sequence }
        observedSeconds = end - start
    }
}

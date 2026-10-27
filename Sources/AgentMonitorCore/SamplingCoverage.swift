/// Sampling decisions and override duty retained across accepted acquisition periods.
public struct SamplingCoverage: Equatable, Codable, Sendable {
    public private(set) var latest: SamplingDecision?
    public private(set) var modes: Set<SamplingMode> = []
    public private(set) var overrideActivations: [String: Int] = [:]
    public private(set) var overrideSeconds: [String: Double] = [:]
    public private(set) var policyChangeCount = 0
    public private(set) var minimumRequestedSeconds: Double?
    public private(set) var maximumRequestedSeconds: Double?

    public init() {}

    mutating func append(
        _ decision: SamplingDecision, duration: Double, activations: Set<SamplingOverride>,
        policyChanges: Int
    ) {
        setLatest(decision)
        let requested = decision.requestedSeconds
        minimumRequestedSeconds = min(minimumRequestedSeconds ?? requested, requested)
        maximumRequestedSeconds = max(maximumRequestedSeconds ?? requested, requested)
        for reason in activations { overrideActivations[reason.rawValue, default: 0] += 1 }
        for reason in decision.overrides { overrideSeconds[reason.rawValue, default: 0] += duration }
        policyChangeCount += policyChanges
    }

    mutating func setLatest(_ decision: SamplingDecision, policyChanges: Int = 0) {
        policyChangeCount += policyChanges
        latest = decision
        modes.insert(decision.mode)
    }

    public mutating func merge(_ other: Self) {
        if let latest = other.latest { self.latest = latest }
        modes.formUnion(other.modes)
        for (reason, count) in other.overrideActivations { overrideActivations[reason, default: 0] += count }
        for (reason, seconds) in other.overrideSeconds { overrideSeconds[reason, default: 0] += seconds }
        policyChangeCount += other.policyChangeCount
        if let requested = other.minimumRequestedSeconds {
            minimumRequestedSeconds = min(minimumRequestedSeconds ?? requested, requested)
        }
        if let requested = other.maximumRequestedSeconds {
            maximumRequestedSeconds = max(maximumRequestedSeconds ?? requested, requested)
        }
    }
}

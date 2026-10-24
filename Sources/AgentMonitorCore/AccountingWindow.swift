import Foundation

public struct ProcessWindowAccounting: Equatable, Codable, Sendable {
    public let cpuSeconds: Double?
    public let recoveredCPUSeconds: Double
    public let pointCandidateCPUSeconds: Double
    public let uncertainCPUSeconds: Double
    public let isHistorical: Bool
    public let lastObservedAt: Double
    public let lastObservedFootprintBytes: UInt64?
    public let currentAttribution: Attribution?

    init(
        cpuSeconds: Double?, recoveredCPUSeconds: Double, pointCandidateCPUSeconds: Double,
        uncertainCPUSeconds: Double, isHistorical: Bool, lastObservedAt: Double,
        lastObservedFootprintBytes: UInt64?, currentAttribution: Attribution? = nil
    ) {
        self.cpuSeconds = cpuSeconds
        self.recoveredCPUSeconds = recoveredCPUSeconds
        self.pointCandidateCPUSeconds = pointCandidateCPUSeconds
        self.uncertainCPUSeconds = uncertainCPUSeconds
        self.isHistorical = isHistorical
        self.lastObservedAt = lastObservedAt
        self.lastObservedFootprintBytes = lastObservedFootprintBytes
        self.currentAttribution = currentAttribution
    }
}

public struct FrozenCPUContribution: Equatable, Codable, Sendable {
    public let runID: UUID
    public let openingScan: UInt64
    public let closingScan: UInt64
    public let process: ProcessIdentity
    public let newbornOpening: Bool
    public let verifiedBirth: Double?
    public let cpuSeconds: Double
    public let startedAt: Double
    public let endedAt: Double
    public let attribution: Attribution
    public let pointEvidenceObservedAt: Double?
    public let revision: Int

    init(_ value: CPUContribution, attribution: Attribution, observedAt: Double?) {
        runID = value.id.closing.scan.runID
        openingScan = value.id.opening.scan.sequence
        closingScan = value.id.closing.scan.sequence
        process = value.id.closing.process
        if case .newbornZero(_, let birth) = value.id.opening {
            newbornOpening = true
            verifiedBirth = birth
        } else {
            newbornOpening = false
            verifiedBirth = nil
        }
        cpuSeconds = value.cpuSeconds
        startedAt = value.startedAt
        endedAt = value.endedAt
        self.attribution = attribution
        pointEvidenceObservedAt = observedAt
        revision = 1
    }
}

public struct ReportWindowSummary: Equatable, Codable, Sendable {
    public let runID: UUID
    public let baselineScan: UInt64
    public let finalScan: UInt64
    public let startedAt: Double
    public let endedAt: Double
    public let contributions: [FrozenCPUContribution]
    public let excludedObservationCount: Int
    public let evictedBaselineCount: Int
    public let unmeasuredLifetimeCount: Int
    public var durationSeconds: Double { max(0, endedAt - startedAt) }
}

/// Retains measured work, including vanished lifetimes, until its display window is delivered.
/// Coalescing follows the endpoint membership rule in docs/proposals/resource-accounting.md.
struct AccountingWindow: Sendable {
    private struct Observation: Sendable {
        let row: HeavyProcess
        let sequence: UInt64
        let time: Double
    }
    private(set) var baseline: CounterScan
    private(set) var final: CounterScan
    private var contributions: [CPUContribution.ID: FrozenCPUContribution] = [:]
    private var observations: [ProcessIdentity: Observation] = [:]
    private var exclusions: Set<CounterObservationID> = []
    private var evictions: Set<ProcessIdentity> = []

    init(baseline: CounterScan) {
        self.baseline = baseline
        final = baseline
    }

    mutating func append(
        _ scan: CounterScan, rows: [HeavyProcess], attributionTimes: [ProcessIdentity: Double] = [:]
    ) throws {
        guard scan.id.runID == baseline.id.runID else { throw CounterWindowError.incompatibleContribution }
        guard scan.id.sequence > baseline.id.sequence else { return }
        let byID = Dictionary(rows.map { ($0.process, $0) }, uniquingKeysWith: { _, last in last })
        for observation in scan.observations {
            let id = observation.id.process
            if let row = byID[id], observations[id].map({ $0.sequence <= scan.id.sequence }) ?? true {
                observations[id] = Observation(
                    row: row, sequence: scan.id.sequence, time: observation.sample.sampledAt)
            }
        }
        for contribution in scan.contributions {
            if let existing = contributions[contribution.id] {
                guard existing.cpuSeconds == contribution.cpuSeconds,
                    existing.startedAt == contribution.startedAt,
                    existing.endedAt == contribution.endedAt
                else { throw CounterWindowError.incompatibleContribution }
                continue
            }
            guard let row = byID[contribution.id.closing.process] else {
                throw CounterWindowError.incompatibleContribution
            }
            contributions[contribution.id] = FrozenCPUContribution(
                contribution, attribution: row.attribution, observedAt: attributionTimes[row.process])
        }
        exclusions.formUnion(scan.exclusions.map(\.observation))
        evictions.formUnion(scan.evictedBaselines)
        if scan.id.sequence >= final.id.sequence { final = scan }
    }

    mutating func merge(_ other: AccountingWindow) throws {
        guard baseline.id.runID == other.baseline.id.runID else {
            throw CounterWindowError.incompatibleContribution
        }
        for (id, value) in other.contributions {
            if let existing = contributions[id] {
                guard existing.cpuSeconds == value.cpuSeconds, existing.startedAt == value.startedAt,
                    existing.endedAt == value.endedAt
                else { throw CounterWindowError.incompatibleContribution }
            }
        }
        if other.baseline.id.sequence < baseline.id.sequence { baseline = other.baseline }
        if other.final.id.sequence > final.id.sequence { final = other.final }
        contributions.merge(other.contributions) { original, _ in original }
        observations.merge(other.observations) { old, new in old.sequence > new.sequence ? old : new }
        exclusions.formUnion(other.exclusions)
        evictions.formUnion(other.evictions)
    }

    var summary: ReportWindowSummary {
        ReportWindowSummary(
            runID: baseline.id.runID, baselineScan: baseline.id.sequence, finalScan: final.id.sequence,
            startedAt: baseline.listedAt ?? baseline.observations.map(\.sample.sampledAt).min() ?? 0,
            endedAt: final.endedAt ?? final.observations.map(\.sample.sampledAt).max() ?? 0,
            contributions: contributions.values.sorted {
                if $0.closingScan != $1.closingScan { return $0.closingScan < $1.closingScan }
                if $0.process.pid != $1.process.pid { return $0.process.pid < $1.process.pid }
                return $0.process.startMicroseconds < $1.process.startMicroseconds
            }, excludedObservationCount: exclusions.count, evictedBaselineCount: evictions.count,
            unmeasuredLifetimeCount: Set(exclusions.map(\.process)).count)
    }

    var payloadSize: MonitoringPayloadSize {
        var size = MonitoringPayloadSize(observations.values.map(\.row))
        for source in [baseline.source, final.source].compactMap({ $0 }) {
            let raw = MonitoringPayloadSize(source)
            size.observations += raw.observations
            size.textBytes += raw.textBytes
        }
        size.observations += contributions.count + exclusions.count + evictions.count
        size.textBytes += contributions.values.reduce(0) { total, value in
            total + (value.attribution.threadID?.utf8.count ?? 0)
                + (value.attribution.rootSessionID?.utf8.count ?? 0)
                + value.attribution.candidateThreadIDs.reduce(0) { $0 + $1.utf8.count }
                + (value.attribution.runtimeDirectory?.utf8.count ?? 0)
                + (value.attribution.terminal?.utf8.count ?? 0)
        }
        size.observations += contributions.values.reduce(0) {
            $0 + $1.attribution.ancestry.count + $1.attribution.candidateThreadIDs.count
        }
        return size
    }

    func counters() throws -> CounterWindow {
        try CounterWindow(
            baseline: baseline, final: final,
            contributions: contributions.map { id, value in
                CPUContribution(
                    id: id, cpuSeconds: value.cpuSeconds, startedAt: value.startedAt, endedAt: value.endedAt)
            })
    }

    func projection(scope: ProcessScope) throws -> (
        rows: [HeavyProcess], summary: ReportWindowSummary, counters: CounterWindow
    ) {
        let counters = try counters()
        let rows = findings(scope: scope, counters: counters)
        let window = summary
        guard rows.count != observations.count else { return (rows, window, counters) }
        let identities = Set(rows.map(\.process))
        let scoped = ReportWindowSummary(
            runID: window.runID, baselineScan: window.baselineScan, finalScan: window.finalScan,
            startedAt: window.startedAt, endedAt: window.endedAt,
            contributions: window.contributions.filter { identities.contains($0.process) },
            excludedObservationCount: window.excludedObservationCount,
            evictedBaselineCount: window.evictedBaselineCount,
            unmeasuredLifetimeCount: window.unmeasuredLifetimeCount)
        return (rows, scoped, counters)
    }

    func findings(scope: ProcessScope) throws -> [HeavyProcess] {
        try findings(scope: scope, counters: counters())
    }

    private func findings(scope: ProcessScope, counters: CounterWindow) -> [HeavyProcess] {
        let duration = counters.observedSeconds
        let eligibleByProcess = Dictionary(grouping: counters.contributions, by: \.id.closing.process)
        let recoveredByProcess = Dictionary(grouping: counters.recovered, by: \.id.closing.process)
        let live = Set(final.observations.map(\.id.process))
        let byProcess = Dictionary(grouping: contributions.values, by: \.process)
        return observations.values.compactMap { observation in
            let original = observation.row
            let records = byProcess[original.process] ?? []
            let eligible = eligibleByProcess[original.process] ?? []
            let seconds = eligible.isEmpty ? nil : eligible.reduce(0) { $0 + $1.cpuSeconds }
            let recovered = (recoveredByProcess[original.process] ?? []).reduce(0) { $0 + $1.cpuSeconds }
            let labels =
                records.map(\.attribution) + (live.contains(original.process) ? [original.attribution] : [])
            let owner = Self.combinedAttribution(labels.isEmpty ? [original.attribution] : labels)
            guard scope.includes(owner) || records.contains(where: { scope.includes($0.attribution) }) else {
                return nil
            }
            let candidate =
                owner.threadID != nil && owner.evidence != .ambiguous && owner.evidence != .unknown
            let historical = !live.contains(original.process)
            return HeavyProcess(
                process: original.process, executable: original.executable, name: original.name,
                cpuPercent: duration > 0 ? seconds.map { 100 * $0 / duration } : nil,
                footprintBytes: historical ? nil : original.footprintBytes,
                kernelPeakFootprintBytes: historical ? nil : original.kernelPeakFootprintBytes,
                cwd: original.cwd, command: original.command, metadataStatus: original.metadataStatus,
                attribution: owner,
                accounting: ProcessWindowAccounting(
                    cpuSeconds: seconds, recoveredCPUSeconds: recovered,
                    pointCandidateCPUSeconds: candidate ? (seconds ?? 0) : 0,
                    uncertainCPUSeconds: candidate ? 0 : (seconds ?? 0), isHistorical: historical,
                    lastObservedAt: observation.time, lastObservedFootprintBytes: original.footprintBytes,
                    currentAttribution: historical ? nil : original.attribution))
        }.sorted {
            if $0.process.pid != $1.process.pid { return $0.process.pid < $1.process.pid }
            return $0.process.startMicroseconds < $1.process.startMicroseconds
        }
    }

    private static func combinedAttribution(_ labels: [Attribution]) -> Attribution {
        let first = labels[0]
        if labels.allSatisfy({
            $0.provider == first.provider && $0.threadID == first.threadID
                && $0.rootSessionID == first.rootSessionID && $0.runtime == first.runtime
                && $0.candidateThreadIDs == first.candidateThreadIDs
        }) {
            return first
        }
        let candidates = Set(labels.flatMap { ($0.threadID.map { [$0] } ?? []) + $0.candidateThreadIDs })
            .sorted()
        return Attribution(
            provider: labels.allSatisfy { $0.provider == first.provider } ? first.provider : nil,
            evidence: .ambiguous, context: .unverified, threadID: nil, rootSessionID: nil,
            runtime: labels.allSatisfy { $0.runtime == first.runtime } ? first.runtime : nil,
            terminal: nil, runtimeDirectory: nil, candidateThreadIDs: candidates, ancestry: [])
    }
}

import Foundation

public struct RecentSession: Hashable, Sendable {
    public enum Resolution: String, Codable, Sendable { case candidate, unresolved, conflicting, shared }
    public let provider: AgentProvider?
    public let sessionID: String?
    public let rootSessionID: String?
    public let runtime: ProcessIdentity?
    public let candidates: [String]
    public let resolution: Resolution

    init(_ row: HeavyProcess, roots: SessionCorroboration) {
        self.init(row, corroboratedRoot: roots.root(for: row.attribution))
    }

    init(_ row: HeavyProcess, corroboratedRoot: String?) {
        let owner = row.attribution
        provider = owner.provider
        runtime = owner.runtime
        let exact = SessionCorroboration.isExact(owner) && owner.provider != nil && owner.threadID != nil
        sessionID = exact ? owner.threadID : nil
        rootSessionID = exact ? corroboratedRoot : nil
        candidates = owner.candidateThreadIDs.sorted()
        if exact {
            resolution = .candidate
        } else if row.isSharedRuntime {
            resolution = .shared
        } else if owner.evidence == .ambiguous {
            resolution = .conflicting
        } else {
            resolution = .unresolved
        }
    }

    var isAgent: Bool { provider != nil || runtime != nil }
    var textBytes: Int {
        ([sessionID, rootSessionID].compactMap { $0 } + candidates).reduce(0) { $0 + $1.utf8.count }
    }
}

public struct RecentWorkerCategory: Hashable, Sendable {
    public let process: ProcessIdentity
    public let owner: RecentSession
    public let executable: String
    public let isAgentRuntime: Bool
    public let executableName: String
    public let invocationName: String?
    /// The workload directory observed with this category's intervals; `nil` when it was unreadable.
    /// Frozen like the owner label, so a later `cd` opens a new category instead of relabeling
    /// earlier CPU (product contract: no historical CPU under a latest directory without evidence).
    public let cwd: String?

    init(
        process: ProcessIdentity, owner: RecentSession, executable: String, isAgentRuntime: Bool,
        cwd: String?, invocationName: String? = nil
    ) {
        self.process = process
        self.owner = owner
        self.executable = executable
        self.isAgentRuntime = isAgentRuntime
        self.cwd = cwd
        self.invocationName = invocationName
        executableName =
            invocationName ?? executable.split(separator: "/").last.map(String.init) ?? "Unknown executable"
    }
}

public struct RecentMemoryReading: Equatable, Codable, Sendable {
    public let bytes: UInt64
    public let scan: UInt64
    public let observedAt: Double
    public let evidence: AttributionEvidence
    public let evidenceObservedAt: Double?
}

public struct RecentWorkerRecord: Equatable, Sendable {
    public private(set) var category: RecentWorkerCategory
    public private(set) var sessionName: String?
    public private(set) var name: String
    public var cwd: String? { category.cwd }
    public private(set) var command: [String]?
    public private(set) var firstObservedAt: Double
    public private(set) var lastObservedAt: Double
    public private(set) var lastScan: UInt64
    public private(set) var atCensus = true
    public private(set) var latestFootprint: UInt64?
    public private(set) var maximumFootprint: RecentMemoryReading?
    public private(set) var kernelPeak: RecentMemoryReading?
    public private(set) var kernelPeakUnavailable = false
    public private(set) var cpuSeconds = 0.0
    public private(set) var measuredIntervals = 0
    public private(set) var excludedObservations = 0
    public private(set) var executableChangedIntervals = 0
    public private(set) var evidenceKinds: Set<AttributionEvidence> = []
    public private(set) var earliestEvidenceAt: Double?
    public private(set) var latestEvidenceAt: Double?
    public private(set) var missingEvidenceTimes = 0

    init(
        category: RecentWorkerCategory, row: HeavyProcess, scan: UInt64, time: Double, evidenceAt: Double?,
        atCensus: Bool = true
    ) {
        self.category = category
        name = row.name
        sessionName = row.sessionName
        command = row.command
        firstObservedAt = time
        lastObservedAt = time
        lastScan = scan
        self.atCensus = atCensus
        latestFootprint = row.footprintBytes
        observe(row, scan: scan, time: time, evidenceAt: evidenceAt, atCensus: atCensus)
    }

    mutating func observe(
        _ row: HeavyProcess, scan: UInt64, time: Double, evidenceAt: Double?, atCensus: Bool = true
    ) {
        name = row.name
        sessionName = row.sessionName
        command = row.command
        lastObservedAt = time
        lastScan = scan
        self.atCensus = atCensus
        latestFootprint = row.footprintBytes
        func reading(_ bytes: UInt64) -> RecentMemoryReading {
            RecentMemoryReading(
                bytes: bytes, scan: scan, observedAt: time,
                evidence: row.attribution.evidence, evidenceObservedAt: evidenceAt)
        }
        if let bytes = row.footprintBytes, maximumFootprint.map({ bytes > $0.bytes }) ?? true {
            maximumFootprint = reading(bytes)
        }
        kernelPeakUnavailable = row.kernelPeakFootprintBytes == nil
        if let bytes = row.kernelPeakFootprintBytes { kernelPeak = reading(bytes) }
        // Accounting admission retains the prior window for rollback. Avoid copying a shared
        // evidence set when this scan adds no new kind (CPU-01 unchanged-context optimization).
        if !evidenceKinds.contains(row.attribution.evidence) {
            evidenceKinds.insert(row.attribution.evidence)
        }
        if let evidenceAt {
            earliestEvidenceAt = min(earliestEvidenceAt ?? evidenceAt, evidenceAt)
            latestEvidenceAt = max(latestEvidenceAt ?? evidenceAt, evidenceAt)
        } else {
            missingEvidenceTimes += 1
        }
    }

    mutating func addCPU(_ seconds: Double, intervals: Int = 1) {
        cpuSeconds += seconds
        measuredIntervals += intervals
    }

    mutating func merge(_ other: RecentWorkerRecord) {
        precondition(category == other.category)
        firstObservedAt = min(firstObservedAt, other.firstObservedAt)
        if other.lastScan >= lastScan {
            name = other.name
            sessionName = other.sessionName
            command = other.command
            lastObservedAt = other.lastObservedAt
            lastScan = other.lastScan
            atCensus = other.atCensus
            latestFootprint = other.latestFootprint
            kernelPeakUnavailable = other.kernelPeakUnavailable
        }
        if let peak = other.maximumFootprint,
            maximumFootprint.map({
                peak.bytes > $0.bytes || (peak.bytes == $0.bytes && peak.observedAt < $0.observedAt)
            }) ?? true
        {
            maximumFootprint = peak
        }
        if let peak = other.kernelPeak, kernelPeak.map({ peak.scan > $0.scan }) ?? true { kernelPeak = peak }
        cpuSeconds += other.cpuSeconds
        measuredIntervals += other.measuredIntervals
        excludedObservations += other.excludedObservations
        executableChangedIntervals += other.executableChangedIntervals
        evidenceKinds.formUnion(other.evidenceKinds)
        if let time = other.earliestEvidenceAt { earliestEvidenceAt = min(earliestEvidenceAt ?? time, time) }
        if let time = other.latestEvidenceAt { latestEvidenceAt = max(latestEvidenceAt ?? time, time) }
        missingEvidenceTimes += other.missingEvidenceTimes
    }
    func sharingOwner(_ owner: RecentSession) -> Self {
        var copy = self
        copy.category = RecentWorkerCategory(
            process: category.process, owner: owner,
            executable: category.executable, isAgentRuntime: category.isAgentRuntime, cwd: category.cwd,
            invocationName: category.invocationName)
        return copy
    }

    mutating func executableChanged() { executableChangedIntervals += 1 }
    mutating func exclude() { excludedObservations += 1 }

    var payloadSize: MonitoringPayloadSize {
        let owner = category.owner
        var bytes = category.executable.utf8.count + category.executableName.utf8.count + name.utf8.count
        bytes += sessionName?.utf8.count ?? 0
        bytes += category.invocationName?.utf8.count ?? 0
        bytes +=
            (cwd?.utf8.count ?? 0) + (owner.sessionID?.utf8.count ?? 0)
            + (owner.rootSessionID?.utf8.count ?? 0)
        for value in owner.candidates { bytes += value.utf8.count }
        for value in command ?? [] { bytes += value.utf8.count }
        return MonitoringPayloadSize(
            observations: 1 + owner.candidates.count + (command?.count ?? 0), textBytes: bytes)
    }
}

public struct RecentCrossing: Equatable, Sendable {
    public let contribution: CPUContribution
    public let category: RecentWorkerCategory
}

public final class RecentActivityUnit: Sendable {
    public let id = UUID()
    public let runID: UUID
    public let baselineScan: UInt64
    public let finalScan: UInt64
    public let startedAt: Double
    public let endedAt: Double
    public let scope: ProcessScope
    public let records: [RecentWorkerRecord]
    public let crossings: [RecentCrossing]
    public let excludedObservationCount: Int
    public let readCoverage: ReadCoverage
    public let acquisitionCoverage: AcquisitionCoverage
    public let publicationCoverage: PublicationCoverage
    public let inspectionCoverage: InspectionCoverage
    public let collapsedContributions: [CollapsedContribution]
    let size: MonitoringPayloadSize

    init(
        runID: UUID, baseline: UInt64, final: UInt64, start: Double, end: Double,
        scope: ProcessScope, records: [RecentWorkerRecord], crossings: [RecentCrossing],
        excluded: Int, coverage: ReadCoverage = ReadCoverage(),
        acquisition: AcquisitionCoverage = AcquisitionCoverage(), publication: PublicationCoverage? = nil,
        inspection: InspectionCoverage = InspectionCoverage(),
        collapsed: [CollapsedContribution] = []
    ) {
        self.runID = runID
        baselineScan = baseline
        finalScan = final
        startedAt = start
        endedAt = end
        self.scope = scope
        // Writer-candidate lists are shared context, not a fresh allocation for every worker.
        // CPU-01's retention bound must charge the actual shared array once per closed unit.
        var owners: [RecentSession: RecentSession] = [:]
        func sharedOwner(_ owner: RecentSession) -> RecentSession {
            if let shared = owners[owner] { return shared }
            owners[owner] = owner
            return owner
        }
        self.records = records.map { $0.sharingOwner(sharedOwner($0.category.owner)) }
        self.crossings = crossings.map {
            RecentCrossing(
                contribution: $0.contribution,
                category: RecentWorkerCategory(
                    process: $0.category.process,
                    owner: sharedOwner($0.category.owner), executable: $0.category.executable,
                    isAgentRuntime: $0.category.isAgentRuntime, cwd: $0.category.cwd,
                    invocationName: $0.category.invocationName))
        }
        excludedObservationCount = excluded
        readCoverage = coverage
        acquisitionCoverage = acquisition
        publicationCoverage = publication ?? PublicationCoverage(start: start, end: end)
        inspectionCoverage = inspection
        collapsedContributions = collapsed
        var size = MonitoringPayloadSize(
            observations: 1 + crossings.count + coverage.retainedCount
                + collapsed.reduce(0) { $0 + 1 + $1.category.candidates.count },
            textBytes: collapsed.reduce(0) { $0 + $1.category.textBytes })
        for record in self.records {
            let payload = record.payloadSize
            size.observations += payload.observations - record.category.owner.candidates.count
            size.textBytes += payload.textBytes - record.category.owner.textBytes
        }
        for crossing in self.crossings {
            size.textBytes +=
                crossing.category.executable.utf8.count + crossing.category.executableName.utf8.count
                + (crossing.category.cwd?.utf8.count ?? 0)
        }
        for owner in owners.keys {
            size.observations += owner.candidates.count
            size.textBytes += owner.textBytes
        }
        self.size = size
    }
}

extension RecentActivityUnit {
    /// Whole-unit time spans preserve contributor history without retaining every scan in a lease.
    /// Existing record/text limits charge every span; publication may evict whole units under pressure.
    static func compacted(_ units: [RecentActivityUnit], maximumSpans: Int = 12) -> [RecentActivityUnit] {
        guard let first = units.first, let last = units.last else { return [] }
        let duration = last.endedAt - first.startedAt
        guard duration > 0 else { return merged(units) }
        var groups: [[RecentActivityUnit]] = []
        var previousBucket: Int?
        for unit in units {
            let bucket = min(
                maximumSpans - 1,
                max(0, Int((unit.startedAt - first.startedAt) / duration * Double(maximumSpans))))
            if bucket != previousBucket {
                groups.append([])
                previousBucket = bucket
            }
            groups[groups.count - 1].append(unit)
        }
        return groups.flatMap { merged($0) }
    }

    private static func merged(_ units: [RecentActivityUnit]) -> [RecentActivityUnit] {
        guard let first = units.first, let last = units.last else { return [] }
        if units.count == 1 { return units }
        var records: [RecentWorkerCategory: RecentWorkerRecord] = [:]
        var crossings: [RecentCrossing] = []
        var collapsed: [CollapsedCategory: CollapsedContribution] = [:]
        var coverage = ReadCoverage()
        var acquisition = AcquisitionCoverage()
        var publication = PublicationCoverage()
        var inspection: InspectionCoverage?
        var excluded = 0
        for unit in units {
            precondition(unit.runID == first.runID && unit.scope == first.scope)
            for record in unit.records {
                if records[record.category] == nil {
                    records[record.category] = record
                } else {
                    records[record.category]?.merge(record)
                }
            }
            crossings += unit.crossings
            for value in unit.collapsedContributions {
                if collapsed[value.category] == nil {
                    collapsed[value.category] = value
                } else {
                    collapsed[value.category]?.merge(value)
                }
            }
            coverage.merge(unit.readCoverage)
            acquisition.merge(unit.acquisitionCoverage)
            publication.merge(unit.publicationCoverage)
            if inspection == nil {
                inspection = unit.inspectionCoverage
            } else {
                inspection?.merge(unit.inspectionCoverage)
            }
            excluded += unit.excludedObservationCount
        }
        var recovered: [RecentCrossing] = []
        for crossing in crossings {
            if crossing.contribution.id.opening.scan.sequence >= first.baselineScan,
                records[crossing.category] != nil
            {
                records[crossing.category]?.addCPU(
                    crossing.contribution.cpuSeconds, intervals: crossing.contribution.intervalCount)
            } else {
                recovered.append(crossing)
            }
        }
        return [
            RecentActivityUnit(
                runID: first.runID, baseline: first.baselineScan, final: last.finalScan,
                start: first.startedAt, end: last.endedAt, scope: first.scope,
                records: Array(records.values), crossings: recovered, excluded: excluded,
                coverage: coverage, acquisition: acquisition, publication: publication,
                inspection: inspection ?? InspectionCoverage(),
                collapsed: Array(collapsed.values))
        ]
    }
}

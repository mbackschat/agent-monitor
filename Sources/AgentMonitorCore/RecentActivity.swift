import Foundation

public struct RecentSession: Hashable, Sendable {
    public enum Resolution: String, Sendable { case candidate, unresolved, conflicting, shared }
    public let provider: AgentProvider?
    public let sessionID: String?
    public let rootSessionID: String?
    public let runtime: ProcessIdentity?
    public let candidates: [String]
    public let resolution: Resolution

    init(_ row: HeavyProcess, roots: SessionCorroboration) {
        let owner = row.attribution
        provider = owner.provider
        runtime = owner.runtime
        let exact = SessionCorroboration.isExact(owner) && owner.provider != nil && owner.threadID != nil
        sessionID = exact ? owner.threadID : nil
        rootSessionID = exact ? roots.root(for: owner) : nil
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
}

public struct RecentWorkerCategory: Hashable, Sendable {
    public let process: ProcessIdentity
    public let owner: RecentSession
    public let executable: String
    public let isAgentRuntime: Bool
    public let executableName: String

    init(process: ProcessIdentity, owner: RecentSession, executable: String, isAgentRuntime: Bool) {
        self.process = process
        self.owner = owner
        self.executable = executable
        self.isAgentRuntime = isAgentRuntime
        executableName = executable.split(separator: "/").last.map(String.init) ?? "Unknown executable"
    }
}

public struct RecentMemoryReading: Equatable, Sendable {
    public let bytes: UInt64
    public let scan: UInt64
    public let observedAt: Double
    public let evidence: AttributionEvidence
    public let evidenceObservedAt: Double?
}

public struct RecentWorkerRecord: Equatable, Sendable {
    public let category: RecentWorkerCategory
    public private(set) var name: String
    public private(set) var cwd: String?
    public private(set) var command: [String]?
    public private(set) var firstObservedAt: Double
    public private(set) var lastObservedAt: Double
    public private(set) var lastScan: UInt64
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

    init(category: RecentWorkerCategory, row: HeavyProcess, scan: UInt64, time: Double, evidenceAt: Double?) {
        self.category = category
        name = row.name
        cwd = row.cwd
        command = row.command
        firstObservedAt = time
        lastObservedAt = time
        lastScan = scan
        latestFootprint = row.footprintBytes
        observe(row, scan: scan, time: time, evidenceAt: evidenceAt)
    }

    mutating func observe(_ row: HeavyProcess, scan: UInt64, time: Double, evidenceAt: Double?) {
        name = row.name
        cwd = row.cwd
        command = row.command
        lastObservedAt = time
        lastScan = scan
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
        evidenceKinds.insert(row.attribution.evidence)
        if let evidenceAt {
            earliestEvidenceAt = min(earliestEvidenceAt ?? evidenceAt, evidenceAt)
            latestEvidenceAt = max(latestEvidenceAt ?? evidenceAt, evidenceAt)
        } else {
            missingEvidenceTimes += 1
        }
    }

    mutating func addCPU(_ seconds: Double) {
        cpuSeconds += seconds
        measuredIntervals += 1
    }
    mutating func executableChanged() { executableChangedIntervals += 1 }
    mutating func exclude() { excludedObservations += 1 }

    var payloadSize: MonitoringPayloadSize {
        let owner = category.owner
        let strings =
            [category.executable, category.executableName, name, cwd, owner.sessionID, owner.rootSessionID]
            .compactMap { $0 }
            + owner.candidates + (command ?? [])
        return MonitoringPayloadSize(
            observations: 1 + owner.candidates.count + (command?.count ?? 0),
            textBytes: strings.reduce(0) { $0 + $1.utf8.count })
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
    public let unreadableObservationCount: Int
    let size: MonitoringPayloadSize

    init(
        runID: UUID, baseline: UInt64, final: UInt64, start: Double, end: Double,
        scope: ProcessScope, records: [RecentWorkerRecord], crossings: [RecentCrossing],
        excluded: Int, unreadable: Int
    ) {
        self.runID = runID
        baselineScan = baseline
        finalScan = final
        startedAt = start
        endedAt = end
        self.scope = scope
        self.records = records
        self.crossings = crossings
        excludedObservationCount = excluded
        unreadableObservationCount = unreadable
        var size = MonitoringPayloadSize(observations: 1 + crossings.count, textBytes: 0)
        for record in records {
            size.observations += record.payloadSize.observations
            size.textBytes += record.payloadSize.textBytes
        }
        for crossing in crossings {
            size.observations += crossing.category.owner.candidates.count
            size.textBytes +=
                crossing.category.executable.utf8.count + crossing.category.executableName.utf8.count
                + (crossing.category.owner.sessionID?.utf8.count ?? 0)
                + (crossing.category.owner.rootSessionID?.utf8.count ?? 0)
                + crossing.category.owner.candidates.reduce(0) { $0 + $1.utf8.count }
        }
        self.size = size
    }
}

struct RecentActivityAccumulator: Sendable {
    private let runID: UUID
    private let baseline: UInt64
    private let start: Double
    private var final: UInt64
    private var end: Double
    private var records: [RecentWorkerCategory: RecentWorkerRecord] = [:]
    private var crossings: [RecentCrossing] = []
    private var excluded = 0
    private var unreadable = 0
    private(set) var current: [RecentWorkerRecord] = []
    private(set) var present: Set<ProcessIdentity> = []

    init(baseline: CounterScan) {
        runID = baseline.id.runID
        self.baseline = baseline.id.sequence
        final = baseline.id.sequence
        start = baseline.listedAt ?? baseline.observations.map(\.sample.sampledAt).min() ?? 0
        end = baseline.endedAt ?? start
    }

    mutating func append(
        _ scan: CounterScan, rows: [HeavyProcess],
        runtimes: Set<ProcessIdentity> = [], attributionTimes: [ProcessIdentity: Double] = [:]
    ) {
        guard scan.id.sequence > final else { return }
        precondition(scan.id.runID == runID)
        final = scan.id.sequence
        end = scan.endedAt ?? scan.listedAt ?? end
        present = Set(scan.observations.map(\.id.process))
        let roots = SessionCorroboration(rows)
        let samples = Dictionary(uniqueKeysWithValues: scan.observations.map { ($0.id.process, $0.sample) })
        var categories: [ProcessIdentity: RecentWorkerCategory] = [:]
        current = rows.compactMap { row in
            guard let sample = samples[row.process] else { return nil }
            let category = RecentWorkerCategory(
                process: row.process,
                owner: RecentSession(row, roots: roots), executable: row.executable,
                isAgentRuntime: runtimes.contains(row.process))
            categories[row.process] = category
            let observation = RecentWorkerRecord(
                category: category, row: row, scan: final,
                time: sample.sampledAt, evidenceAt: attributionTimes[row.process])
            if var previous = records[category] {
                previous.observe(
                    row, scan: final, time: sample.sampledAt, evidenceAt: attributionTimes[row.process])
                records[category] = previous
            } else {
                records[category] = observation
            }
            return observation
        }
        for value in scan.contributions {
            guard let category = categories[value.id.closing.process] else { continue }
            if value.executableChanged { records[category]?.executableChanged() }
            if value.id.opening.scan.sequence < baseline {
                crossings.append(RecentCrossing(contribution: value, category: category))
            } else {
                records[category]?.addCPU(value.cpuSeconds)
            }
        }
        for value in scan.exclusions {
            if let category = categories[value.observation.process] { records[category]?.exclude() }
        }
        excluded += scan.exclusions.count
        unreadable += scan.source?.unreadableCount ?? 0
    }

    func seal(scope: ProcessScope) -> RecentActivityUnit {
        let identities = Set(
            records.keys.filter {
                scope == .allProcesses || $0.owner.isAgent
            }.map(\.process))
        return RecentActivityUnit(
            runID: runID, baseline: baseline, final: final, start: start, end: end,
            scope: scope, records: records.values.filter { identities.contains($0.category.process) },
            crossings: crossings.filter { identities.contains($0.category.process) },
            excluded: excluded, unreadable: unreadable)
    }

    var payloadSize: MonitoringPayloadSize {
        var size = seal(scope: .allProcesses).size
        size.observations += present.count
        for row in current {
            size.observations += row.payloadSize.observations
            size.textBytes += row.payloadSize.textBytes
        }
        return size
    }
}

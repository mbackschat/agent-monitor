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
    public let labelChangedInWindow: Bool
    public let lastObservedCorroboratedRootSessionID: String?

    init(
        cpuSeconds: Double?, recoveredCPUSeconds: Double, pointCandidateCPUSeconds: Double,
        uncertainCPUSeconds: Double, isHistorical: Bool, lastObservedAt: Double,
        lastObservedFootprintBytes: UInt64?, currentAttribution: Attribution? = nil,
        labelChangedInWindow: Bool = false, lastObservedCorroboratedRootSessionID: String? = nil
    ) {
        self.cpuSeconds = cpuSeconds
        self.recoveredCPUSeconds = recoveredCPUSeconds
        self.pointCandidateCPUSeconds = pointCandidateCPUSeconds
        self.uncertainCPUSeconds = uncertainCPUSeconds
        self.isHistorical = isHistorical
        self.lastObservedAt = lastObservedAt
        self.lastObservedFootprintBytes = lastObservedFootprintBytes
        self.currentAttribution = currentAttribution
        self.labelChangedInWindow = labelChangedInWindow
        self.lastObservedCorroboratedRootSessionID = lastObservedCorroboratedRootSessionID
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
    public let corroboratedRootSessionID: String?
    public let earliestEvidenceObservedAt: Double?
    public let latestEvidenceObservedAt: Double?
    public let missingEvidenceTimeCount: Int
    public let intervalCount: Int
    public let missingReadIntervalCount: Int
    public let executableChangedIntervalCount: Int

    init(
        _ value: CPUContribution, attribution: Attribution, observedAt: Double?,
        latestObservedAt: Double? = nil, missingEvidenceTimeCount: Int? = nil,
        corroboratedRootSessionID: String? = nil
    ) {
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
        self.corroboratedRootSessionID = corroboratedRootSessionID
        earliestEvidenceObservedAt = observedAt
        latestEvidenceObservedAt = latestObservedAt ?? observedAt
        self.missingEvidenceTimeCount =
            missingEvidenceTimeCount ?? (observedAt == nil ? value.intervalCount : 0)
        intervalCount = value.intervalCount
        missingReadIntervalCount = value.missingReadIntervalCount
        executableChangedIntervalCount = value.executableChangedIntervalCount
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
    public private(set) var unmeasuredLifetimeCountRange: LifetimeCountRange? = nil
    public private(set) var evictedBaselineCountRange: LifetimeCountRange? = nil
    public private(set) var readCoverage = ReadCoverage()
    public private(set) var acquisitionCoverage = AcquisitionCoverage()
    public private(set) var collapsedContributions: [CollapsedContribution] = []
    public var identityDetailsComplete: Bool { collapsedContributions.isEmpty }
    public var durationSeconds: Double { max(0, endedAt - startedAt) }
}

/// One accumulator for closed-unit accounting and recent memory statistics.
/// Categories conserve accepted deltas; only crossing intervals retain individual endpoints.
struct AccountingWindow: Sendable {
    private struct Key: Hashable, Sendable {
        let category: RecentWorkerCategory
        let attribution: Attribution
    }
    private struct Observation: Sendable {
        let row: HeavyProcess
        let sequence: UInt64
        let time: Double
        let run: Int
        let evidenceAt: Double?
    }
    private struct Run: Sendable {
        let key: Key
        var memory: RecentWorkerRecord
        var cpu: CPUContribution?
        var earliest: Double?
        var latest: Double?
        var missingTimes = 0

        mutating func add(_ value: CPUContribution, earliest: Double?, latest: Double?, missing: Int) {
            cpu = cpu.map { $0.adding(value) } ?? value
            memory.addCPU(value.cpuSeconds, intervals: value.intervalCount)
            if let earliest { self.earliest = min(self.earliest ?? earliest, earliest) }
            if let latest { self.latest = max(self.latest ?? latest, latest) }
            missingTimes += missing
        }
    }
    private struct Crossing: Sendable {
        let value: CPUContribution
        let key: Key
        let evidenceAt: Double?
    }

    private(set) var baseline: CounterScan
    private(set) var final: CounterScan
    private var runs: [Run] = []
    private var indices: [Key: Int] = [:]
    private var crossings: [Crossing] = []
    private var observations: [ProcessIdentity: Observation] = [:]
    private var excludedCount = 0
    private var excludedLifetimes: Set<ProcessIdentity> = []
    private var evictions: Set<ProcessIdentity> = []
    private var releasedExclusions: LifetimeCountRange?
    private var releasedEvictions: LifetimeCountRange?

    private func count(_ retained: Set<ProcessIdentity>, released: LifetimeCountRange?) -> LifetimeCountRange
    {
        var result = LifetimeCountRange(minimum: retained.count, maximum: retained.count)
        if let released { result.union(released) }
        return result
    }
    private var readCoverage = ReadCoverage()
    private var acquisitionCoverage = AcquisitionCoverage()
    private var collapsed: [CollapsedCategory: CollapsedContribution] = [:]

    init(baseline: CounterScan) {
        self.baseline = Self.endpoint(baseline)
        final = Self.endpoint(baseline)
    }

    private static func endpoint(_ scan: CounterScan) -> CounterScan {
        let source = scan.source.map {
            ProcessSnapshot(
                samples: [], enumeratedCount: $0.enumeratedCount, unreadableCount: $0.unreadableCount,
                listedAt: $0.listedAt, scanSeconds: $0.scanSeconds,
                hostCounters: $0.hostCounters, logicalCPUCount: $0.logicalCPUCount)
        }
        return CounterScan(
            observations: [], source: source, id: scan.id,
            listedAt: scan.listedAt ?? scan.observations.map(\.sample.sampledAt).min(),
            endedAt: scan.endedAt ?? scan.observations.map(\.sample.sampledAt).max(),
            contributions: [], exclusions: [], evictedBaselines: [])
    }

    mutating func append(
        _ scan: CounterScan, rows: [HeavyProcess], attributionTimes: [ProcessIdentity: Double] = [:],
        runtimes: Set<ProcessIdentity> = [], timing: AcquisitionTiming? = nil
    ) throws {
        guard scan.id.runID == baseline.id.runID, scan.id.sequence > final.id.sequence else {
            throw CounterWindowError.incompatibleContribution
        }
        let byID = Dictionary(rows.map { ($0.process, $0) }, uniquingKeysWith: { _, last in last })
        let roots = SessionCorroboration(rows)
        for observation in scan.observations {
            let id = observation.id.process
            guard let row = byID[id] else { continue }
            let category = RecentWorkerCategory(
                process: id, owner: RecentSession(row, roots: roots), executable: row.executable,
                isAgentRuntime: runtimes.contains(id))
            let index: Int
            if let previous = observations[id], previous.row.attribution == row.attribution,
                runs[previous.run].key.category == category
            {
                index = previous.run
                runs[index].memory.observe(
                    row, scan: scan.id.sequence,
                    time: observation.sample.sampledAt, evidenceAt: attributionTimes[id])
            } else {
                let key = Key(category: category, attribution: row.attribution)
                if let found = indices[key] {
                    index = found
                    runs[index].memory.observe(
                        row, scan: scan.id.sequence,
                        time: observation.sample.sampledAt, evidenceAt: attributionTimes[id])
                } else {
                    index = runs.count
                    indices[key] = index
                    runs.append(
                        Run(
                            key: key,
                            memory: RecentWorkerRecord(
                                category: category, row: row, scan: scan.id.sequence,
                                time: observation.sample.sampledAt, evidenceAt: attributionTimes[id])))
                }
            }
            observations[id] = Observation(
                row: row.usingAttribution(runs[index].key.attribution), sequence: scan.id.sequence,
                time: observation.sample.sampledAt, run: index, evidenceAt: attributionTimes[id])
        }
        for contribution in scan.contributions {
            guard let observation = observations[contribution.id.closing.process],
                observation.sequence == scan.id.sequence
            else {
                throw CounterWindowError.incompatibleContribution
            }
            let index = observation.run
            let time = observation.evidenceAt
            if contribution.executableChanged { runs[index].memory.executableChanged() }
            if contribution.id.opening.scan.sequence < baseline.id.sequence {
                crossings.append(Crossing(value: contribution, key: runs[index].key, evidenceAt: time))
            } else {
                runs[index].add(contribution, earliest: time, latest: time, missing: time == nil ? 1 : 0)
            }
        }
        for exclusion in scan.exclusions {
            excludedLifetimes.insert(exclusion.observation.process)
            if let observation = observations[exclusion.observation.process],
                observation.sequence == scan.id.sequence
            {
                runs[observation.run].memory.exclude()
            }
        }
        excludedCount += scan.exclusions.count
        readCoverage.append(scan.source)
        acquisitionCoverage.append(timing)
        evictions.formUnion(scan.evictedBaselines)
        final = Self.endpoint(scan)
    }

    mutating func merge(_ other: AccountingWindow) throws {
        // Compacted sums cannot deduplicate partial overlaps. The pipeline admits contiguous units once.
        guard baseline.id.runID == other.baseline.id.runID,
            final.id.sequence == other.baseline.id.sequence
        else {
            throw CounterWindowError.incompatibleContribution
        }
        var remapped: [Int] = []
        for incoming in other.runs {
            if let index = indices[incoming.key] {
                runs[index].memory.merge(incoming.memory)
                if let value = incoming.cpu {
                    runs[index].cpu = runs[index].cpu.map { $0.adding(value) } ?? value
                }
                if let time = incoming.earliest {
                    runs[index].earliest = min(runs[index].earliest ?? time, time)
                }
                if let time = incoming.latest { runs[index].latest = max(runs[index].latest ?? time, time) }
                runs[index].missingTimes += incoming.missingTimes
                remapped.append(index)
            } else {
                indices[incoming.key] = runs.count
                remapped.append(runs.count)
                runs.append(incoming)
            }
        }
        for crossing in other.crossings {
            guard let index = indices[crossing.key] else {
                preconditionFailure("A retained crossing must have a canonical run")
            }
            if crossing.value.id.opening.scan.sequence >= baseline.id.sequence {
                runs[index].add(
                    crossing.value, earliest: crossing.evidenceAt, latest: crossing.evidenceAt,
                    missing: crossing.evidenceAt == nil ? 1 : 0)
            } else {
                crossings.append(
                    Crossing(value: crossing.value, key: runs[index].key, evidenceAt: crossing.evidenceAt))
            }
        }
        for (identity, observation) in other.observations {
            if observations[identity].map({ $0.sequence > observation.sequence }) == true { continue }
            observations[identity] = Observation(
                row: observation.row.usingAttribution(runs[remapped[observation.run]].key.attribution),
                sequence: observation.sequence, time: observation.time,
                run: remapped[observation.run], evidenceAt: observation.evidenceAt)
        }
        for (category, contribution) in other.collapsed {
            if collapsed[category] == nil {
                collapsed[category] = contribution
            } else {
                collapsed[category]?.merge(contribution)
            }
        }
        excludedCount += other.excludedCount
        readCoverage.merge(other.readCoverage)
        acquisitionCoverage.merge(other.acquisitionCoverage)
        if let value = other.releasedExclusions {
            if releasedExclusions == nil {
                releasedExclusions = value
            } else {
                releasedExclusions?.union(value)
            }
        }
        if let value = other.releasedEvictions {
            if releasedEvictions == nil { releasedEvictions = value } else { releasedEvictions?.union(value) }
        }
        excludedLifetimes.formUnion(other.excludedLifetimes)
        evictions.formUnion(other.evictions)
        final = other.final
    }

    var summary: ReportWindowSummary {
        var records = runs.compactMap { run in
            run.cpu.map {
                FrozenCPUContribution(
                    $0, attribution: run.key.attribution, observedAt: run.earliest,
                    latestObservedAt: run.latest, missingEvidenceTimeCount: run.missingTimes,
                    corroboratedRootSessionID: run.key.category.owner.rootSessionID)
            }
        }
        records += crossings.map {
            FrozenCPUContribution(
                $0.value, attribution: $0.key.attribution, observedAt: $0.evidenceAt,
                corroboratedRootSessionID: $0.key.category.owner.rootSessionID)
        }
        records.sort {
            if $0.closingScan != $1.closingScan { return $0.closingScan < $1.closingScan }
            if $0.process.pid != $1.process.pid { return $0.process.pid < $1.process.pid }
            if $0.process.startMicroseconds != $1.process.startMicroseconds {
                return $0.process.startMicroseconds < $1.process.startMicroseconds
            }
            return $0.openingScan < $1.openingScan
        }
        return ReportWindowSummary(
            runID: baseline.id.runID, baselineScan: baseline.id.sequence, finalScan: final.id.sequence,
            startedAt: baseline.listedAt ?? 0, endedAt: final.endedAt ?? 0,
            contributions: records, excludedObservationCount: excludedCount,
            evictedBaselineCount: count(evictions, released: releasedEvictions).minimum,
            unmeasuredLifetimeCount: count(excludedLifetimes, released: releasedExclusions).minimum,
            unmeasuredLifetimeCountRange: releasedExclusions.map { _ in
                count(excludedLifetimes, released: releasedExclusions)
            },
            evictedBaselineCountRange: releasedEvictions.map { _ in
                count(evictions, released: releasedEvictions)
            },
            readCoverage: readCoverage, acquisitionCoverage: acquisitionCoverage,
            collapsedContributions: Array(collapsed.values))
    }

    var payloadSize: MonitoringPayloadSize {
        // Observation rows explicitly share their canonical run attribution, including after merge.
        // The storage-identity regression guards this omission from the row charge.
        var size = MonitoringPayloadSize(observations.values.map(\.row), includeAttribution: false)
        size.observations += collapsed.keys.reduce(0) {
            $0 + 1 + $1.candidates.count + ($1.runtime == nil ? 0 : 1)
        }
        size.textBytes += collapsed.keys.reduce(0) { $0 + $1.textBytes }
        size.observations +=
            crossings.count + excludedLifetimes.count + evictions.count + readCoverage.retainedCount
        for run in runs {
            let key = run.key
            let memorySize = run.memory.payloadSize
            let context = MonitoringPayloadSize(attribution: key.attribution)
            size.observations += 1 + context.observations + memorySize.observations
            size.textBytes += memorySize.textBytes + context.textBytes
        }
        return size
    }

    @discardableResult mutating func compact(to limits: MonitoringPipelineLimits) -> MonitoringPayloadSize {
        func fits(_ size: MonitoringPayloadSize) -> Bool {
            size.observations <= limits.pendingObservations && size.textBytes <= limits.pendingTextBytes
        }
        let originalSize = payloadSize
        guard !fits(originalSize) else { return originalSize }
        // Crossing endpoints must survive: a wider enclosing window can still make their CPU eligible.
        var keep = Set(crossings.compactMap { indices[$0.key] })
        keep.formUnion(crossings.compactMap { observations[$0.key.category.process]?.run })
        keep.formUnion(observations.values.filter { $0.sequence == final.id.sequence }.map(\.run))
        let agentMembers = Set(runs.filter { $0.key.category.owner.isAgent }.map(\.key.category.process))
        var batches: [CollapsedCategory: CollapsedContribution] = [:]
        var members: [CollapsedCategory: Set<ProcessIdentity>] = [:]
        var workers: [CollapsedCategory: Set<ProcessIdentity>] = [:]
        var retained: [Run] = []
        var remapped: [Int: Int] = [:]
        for (index, run) in runs.enumerated() {
            if keep.contains(index) {
                remapped[index] = retained.count
                retained.append(run)
                continue
            }
            let key = CollapsedCategory(
                run.key.category, includedInAgentScope: agentMembers.contains(run.key.category.process))
            let value = CollapsedContribution(
                category: key, memory: run.memory, cpu: run.cpu,
                earliestEvidence: run.earliest, latestEvidence: run.latest, missingEvidence: run.missingTimes)
            if batches[key] == nil { batches[key] = value } else { batches[key]?.merge(value) }
            members[key, default: []].insert(run.key.category.process)
            if !run.key.category.isAgentRuntime { workers[key, default: []].insert(run.key.category.process) }
        }
        for (key, var value) in batches {
            value.setCounts(processes: members[key]?.count ?? 0, workers: workers[key]?.count ?? 0)
            if collapsed[key] == nil { collapsed[key] = value } else { collapsed[key]?.merge(value) }
        }
        runs = retained
        indices = Dictionary(uniqueKeysWithValues: runs.enumerated().map { ($0.element.key, $0.offset) })
        observations = observations.compactMapValues { observation in
            guard let index = remapped[observation.run] else { return nil }
            return Observation(
                row: observation.row, sequence: observation.sequence, time: observation.time,
                run: index, evidenceAt: observation.evidenceAt)
        }
        let discardedExclusions = excludedLifetimes.subtracting(observations.keys)
        let discardedEvictions = evictions.subtracting(observations.keys)
        if !discardedExclusions.isEmpty {
            releasedExclusions = count(discardedExclusions, released: releasedExclusions)
        }
        if !discardedEvictions.isEmpty {
            releasedEvictions = count(discardedEvictions, released: releasedEvictions)
        }
        excludedLifetimes.formIntersection(observations.keys)
        evictions.formIntersection(observations.keys)
        if !fits(payloadSize), !collapsed.isEmpty {
            // Arbitrary session churn is also unbounded. Preserve resources and count bounds while
            // visibly releasing category names, separately for agent-associated and other work.
            var remainder: [CollapsedCategory: CollapsedContribution] = [:]
            for value in collapsed.values {
                let reduced = value.droppingCategoryDetail()
                if remainder[reduced.category] == nil {
                    remainder[reduced.category] = reduced
                } else {
                    remainder[reduced.category]?.merge(reduced)
                }
            }
            collapsed = remainder
        }
        return payloadSize
    }

    var collapsedCPUSeconds: Double { collapsed.values.reduce(0) { $0 + $1.cpuSeconds } }

    func counters() throws -> CounterWindow {
        try CounterWindow(
            baseline: baseline, final: final,
            contributions: runs.compactMap(\.cpu) + crossings.map(\.value))
    }

    var current: [RecentWorkerRecord] {
        observations.values.filter { $0.sequence == final.id.sequence }.map {
            RecentWorkerRecord(
                category: runs[$0.run].key.category, row: $0.row,
                scan: $0.sequence, time: $0.time, evidenceAt: $0.evidenceAt)
        }
    }
    var present: Set<ProcessIdentity> {
        Set(observations.values.filter { $0.sequence == final.id.sequence }.map(\.row.process))
    }

    func seal(scope: ProcessScope) -> RecentActivityUnit {
        let identities = Set(
            runs.filter { scope == .allProcesses || $0.key.category.owner.isAgent }
                .map(\.key.category.process))
        var records: [RecentWorkerCategory: RecentWorkerRecord] = [:]
        for run in runs where identities.contains(run.key.category.process) {
            let key = run.key
            if records[key.category] == nil {
                records[key.category] = run.memory
            } else {
                records[key.category]?.merge(run.memory)
            }
        }
        return RecentActivityUnit(
            runID: baseline.id.runID, baseline: baseline.id.sequence, final: final.id.sequence,
            start: baseline.listedAt ?? 0, end: final.endedAt ?? 0, scope: scope,
            records: Array(records.values),
            crossings: crossings.filter { identities.contains($0.key.category.process) }.map {
                RecentCrossing(contribution: $0.value, category: $0.key.category)
            }, excluded: excludedCount, coverage: readCoverage,
            collapsed: collapsed.values.filter { scope == .allProcesses || $0.category.includedInAgentScope })
    }

    func projection(scope: ProcessScope) throws -> (
        rows: [HeavyProcess], summary: ReportWindowSummary, counters: CounterWindow
    ) {
        let counters = try counters()
        let rows = findings(scope: scope, counters: counters)
        let window = summary
        guard scope != .allProcesses else { return (rows, window, counters) }
        let identities = Set(rows.map(\.process))
        let scoped = ReportWindowSummary(
            runID: window.runID, baselineScan: window.baselineScan, finalScan: window.finalScan,
            startedAt: window.startedAt, endedAt: window.endedAt,
            contributions: window.contributions.filter { identities.contains($0.process) },
            excludedObservationCount: window.excludedObservationCount,
            evictedBaselineCount: window.evictedBaselineCount,
            unmeasuredLifetimeCount: window.unmeasuredLifetimeCount,
            unmeasuredLifetimeCountRange: window.unmeasuredLifetimeCountRange,
            evictedBaselineCountRange: window.evictedBaselineCountRange, readCoverage: window.readCoverage,
            acquisitionCoverage: window.acquisitionCoverage,
            collapsedContributions: window.collapsedContributions.filter {
                scope == .allProcesses || $0.category.includedInAgentScope
            })
        return (rows, scoped, counters)
    }

    func findings(scope: ProcessScope) throws -> [HeavyProcess] {
        try findings(scope: scope, counters: counters())
    }

    private func findings(scope: ProcessScope, counters: CounterWindow) -> [HeavyProcess] {
        let duration = counters.observedSeconds
        let eligibleByProcess = Dictionary(grouping: counters.contributions, by: \.id.closing.process)
        let recoveredByProcess = Dictionary(grouping: counters.recovered, by: \.id.closing.process)
        let live = present
        let byProcess = Dictionary(grouping: summary.contributions, by: \.process)
        return observations.values.compactMap { observation in
            let original = observation.row
            let records = byProcess[original.process] ?? []
            let eligible = eligibleByProcess[original.process] ?? []
            let seconds = eligible.isEmpty ? nil : eligible.reduce(0) { $0 + $1.cpuSeconds }
            let recovered = (recoveredByProcess[original.process] ?? []).reduce(0) { $0 + $1.cpuSeconds }
            let owner = original.attribution
            let root = runs[observation.run].key.category.owner.rootSessionID
            let changed = records.contains {
                !Self.sameOwner($0.attribution, owner) || $0.corroboratedRootSessionID != root
            }
            guard scope.includes(owner) || records.contains(where: { scope.includes($0.attribution) })
            else {
                return nil
            }
            let candidateSeconds = records.filter {
                $0.openingScan >= baseline.id.sequence && SessionCorroboration.isExact($0.attribution)
                    && $0.attribution.threadID != nil && $0.attribution.provider != nil
            }.reduce(0) { $0 + $1.cpuSeconds }
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
                    pointCandidateCPUSeconds: candidateSeconds,
                    uncertainCPUSeconds: max(0, (seconds ?? 0) - candidateSeconds), isHistorical: historical,
                    lastObservedAt: observation.time, lastObservedFootprintBytes: original.footprintBytes,
                    currentAttribution: historical ? nil : original.attribution,
                    labelChangedInWindow: changed,
                    lastObservedCorroboratedRootSessionID: runs[observation.run].key.category.owner
                        .rootSessionID))
        }.sorted {
            if $0.process.pid != $1.process.pid { return $0.process.pid < $1.process.pid }
            return $0.process.startMicroseconds < $1.process.startMicroseconds
        }
    }

    private static func sameOwner(_ left: Attribution, _ right: Attribution) -> Bool {
        left.provider == right.provider && left.threadID == right.threadID
            && left.rootSessionID == right.rootSessionID && left.runtime == right.runtime
            && left.candidateThreadIDs == right.candidateThreadIDs
            && SessionCorroboration.isExact(left) == SessionCorroboration.isExact(right)
    }
}

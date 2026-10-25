import AgentMonitorCore
import Foundation

public enum ContributorSection: String, Sendable {
    case recent = "Recent contributors"
    case remainder = "More processes"
    case uncertain = "Unresolved / uncertain"
    case shared = "Shared agent runtimes"
    case released = "Older work · detail released"
}

public indirect enum ContributorID: Hashable, Sendable {
    case section(ContributorSection)
    case collapsed(CollapsedCategory)
    case session(provider: String, session: String, root: String?)
    case provider(parent: ContributorID, name: String)
    case executable(parent: ContributorID, name: String)
    case process(parent: ContributorID, identity: ProcessIdentity)
}

public struct ContributorStats: Equatable, Sendable {
    public var processes: Set<ProcessIdentity> = []
    public var collapsedProcesses: LifetimeCountRange?
    public var collapsedWorkers: LifetimeCountRange?
    public var current: Set<ProcessIdentity> = []
    public var workers: Set<ProcessIdentity> = []
    public var runtimes: Set<ProcessIdentity> = []
    public var noLongerObserved: Set<ProcessIdentity> = []
    public var membershipChanged: Set<ProcessIdentity> = []
    public var filtered: Set<ProcessIdentity> = []
    public var currentCPU = 0.0
    public var currentMeasurements = 0
    public var recentCPU = 0.0
    public var recentMeasurements = 0
    public var recoveredCPU = 0.0
    public var memoryBytes: UInt64 = 0
    public var missingMemory = 0
    public var currentAvailable = true
    public var exclusions = 0
    public var maximumWorkerFootprint: RecentMemoryReading?

    mutating func merge(_ other: Self) {
        currentAvailable = currentAvailable && other.currentAvailable
        if let counts = other.collapsedProcesses {
            if collapsedProcesses == nil {
                collapsedProcesses = counts
            } else {
                collapsedProcesses?.union(counts)
            }
        }
        if let counts = other.collapsedWorkers {
            if collapsedWorkers == nil { collapsedWorkers = counts } else { collapsedWorkers?.union(counts) }
        }
        processes.formUnion(other.processes)
        current.formUnion(other.current)
        workers.formUnion(other.workers)
        runtimes.formUnion(other.runtimes)
        noLongerObserved.formUnion(other.noLongerObserved)
        membershipChanged.formUnion(other.membershipChanged)
        filtered.formUnion(other.filtered)
        currentCPU += other.currentCPU
        currentMeasurements += other.currentMeasurements
        recentCPU += other.recentCPU
        recentMeasurements += other.recentMeasurements
        recoveredCPU += other.recoveredCPU
        memoryBytes += other.memoryBytes
        missingMemory += other.missingMemory
        exclusions += other.exclusions
        if let reading = other.maximumWorkerFootprint,
            maximumWorkerFootprint.map({
                reading.bytes > $0.bytes || (reading.bytes == $0.bytes && reading.scan < $0.scan)
            }) ?? true
        {
            maximumWorkerFootprint = reading
        }
    }

    public func cpuText(duration: Double) -> String {
        currentMeasurements > 0 && duration > 0 ? number(100 * currentCPU / duration) + "%" : "—"
    }
    public var memoryText: String {
        guard currentAvailable else { return "Unavailable" }
        let known =
            memoryBytes >= 1_000_000_000
            ? "\(number(Double(memoryBytes) / 1e9)) GB" : "\(number(Double(memoryBytes) / 1e6)) MB"
        return (missingMemory > 0 ? "≥ " : "") + known
    }
    public var recentCPUText: String { recentMeasurements > 0 ? number(recentCPU) + " s" : "—" }
    public func summary(duration: Double, cpuLabel: String = "CPU") -> String {
        "\(cpuLabel) \(cpuText(duration: duration)) · Memory \(memoryText) · Recent CPU \(recentCPUText)"
    }
    public var hasContributions: Bool {
        !processes.isEmpty || collapsedProcesses != nil
    }
    public var workerCountText: String {
        var counts = LifetimeCountRange(minimum: workers.count, maximum: workers.count)
        if let collapsedWorkers { counts.union(collapsedWorkers) }
        return counts.minimum == counts.maximum ? "\(counts.minimum)" : "\(counts.minimum)–\(counts.maximum)"
    }
    public var compactCensus: String {
        guard currentAvailable else { return "Current presence unavailable" }
        var parts = ["\(current.count) now"]
        if workers.count > current.count || !noLongerObserved.isEmpty || collapsedWorkers != nil {
            parts.append("\(workerCountText) observed workers")
        }
        if !noLongerObserved.isEmpty { parts.append("\(noLongerObserved.count) no longer observed") }
        if !runtimes.isEmpty { parts.append("\(runtimes.count) agent runtimes") }
        if !filtered.isEmpty { parts.append("\(filtered.count) filtered") }
        return parts.joined(separator: " · ")
    }

    public var census: String {
        (currentAvailable ? "\(current.count) processes now" : "Processes now unavailable")
            + " · \(workerCountText) observed workers"
            + (runtimes.isEmpty ? "" : " · \(runtimes.count) agent runtimes") + " · "
            + (currentAvailable ? "\(noLongerObserved.count) no longer observed" : "presence unavailable")
    }
}

public struct ContributorNode: Equatable, Sendable, Identifiable {
    public let id: ContributorID
    public var title: String
    public var stats = ContributorStats()
    public var children: [ContributorID] = []
    var labels: [String] = []
    var evidence: [ContributorEvidence] = []
    public var details: [String] { labels + evidence.flatMap(\.details) }
    public var process: ProcessIdentity?
    public func summary(duration: Double) -> String {
        func candidate(_ id: ContributorID) -> Bool {
            switch id {
            case .session: true
            case .executable(let parent, _), .process(let parent, _): candidate(parent)
            case .section, .provider, .collapsed: false
            }
        }
        return stats.summary(duration: duration, cpuLabel: candidate(id) ? "Candidate CPU" : "CPU")
    }
}

public struct ContributorRow: Equatable, Sendable, Identifiable {
    public let node: ContributorNode
    public let depth: Int
    public var id: ContributorID { node.id }
}

public enum ContributorOrder: String, Sendable { case cpu, memory }

/// One immutable-category projection and disclosure policy for native and terminal hosts.
public struct ContributorOverview: Equatable, Sendable {
    public private(set) var nodes: [ContributorID: ContributorNode] = [:]
    public private(set) var main: [ContributorID] = []
    public private(set) var totals = ContributorStats()
    public private(set) var duration = 0.0
    public private(set) var coverage = ""
    public private(set) var samplingCoverage: SamplingCoverageSummary?
    public private(set) var census = ""
    public private(set) var coverageWarning = ""
    public private(set) var order: ContributorOrder = .cpu
    public let memoryCapacityBytes: UInt64
    public private(set) var runID: UUID?
    private var scope: ProcessScope?
    public private(set) var selection: ContributorID?
    public private(set) var open: Set<ContributorID> = []
    public var showAll = false
    public var enabled = true
    public private(set) var pinned: [ContributorID] = []
    private var cpuRank: [ContributorID] = []
    private var memoryRank: [ContributorID] = []
    private var formerlySelected: [ContributorID: Double] = [:]
    private var latestTime = 0.0
    private var source: RecentActivitySnapshot?
    public private(set) var detailOffset = 0
    public private(set) var detailsVisible = false

    public init(memoryCapacityBytes: UInt64 = ProcessInfo.processInfo.physicalMemory) {
        self.memoryCapacityBytes = memoryCapacityBytes
    }

    public func cpuMeterFraction(_ stats: ContributorStats) -> Double {
        duration > 0 ? min(1, max(0, stats.currentCPU / duration)) : 0
    }
    public func memoryMeterFraction(_ stats: ContributorStats) -> Double {
        memoryCapacityBytes > 0 ? min(1, Double(stats.memoryBytes) / Double(memoryCapacityBytes)) : 0
    }
    public var meterScale: String {
        "Bars: CPU 100% = one core; memory 100% = \(number(Double(memoryCapacityBytes) / 1e9)) GB RAM"
    }
    public mutating func sort(by order: ContributorOrder) {
        self.order = order
        main = contributionOrder(main)
        sortChildren()
    }
    private mutating func sortChildren() {
        for id in Array(nodes.keys) {
            let children = contributionOrder(nodes[id]?.children ?? [])
            nodes[id]?.children = children
        }
    }
    private func contributionOrder(_ ids: [ContributorID], by metric: ContributorOrder? = nil)
        -> [ContributorID]
    {
        let metric = metric ?? order
        return ids.sorted {
            let first = nodes[$0]?.stats
            let second = nodes[$1]?.stats
            let a = metric == .cpu ? first?.currentCPU ?? 0 : Double(first?.memoryBytes ?? 0)
            let b = metric == .cpu ? second?.currentCPU ?? 0 : Double(second?.memoryBytes ?? 0)
            return a == b ? identity($0) < identity($1) : a > b
        }
    }
    public var sourceDurationLabel: String {
        guard let source else { return "unavailable" }
        return "\(number(source.duration)) s" + (source.retentionLimited ? " (retention limit / gap)" : "")
    }

    public var topLevel: [ContributorID] {
        let summaries: [ContributorID] = [
            .section(.recent), .section(.remainder), .section(.uncertain), .section(.shared),
            .section(.released),
        ]
        return pinned + main.filter { !pinned.contains($0) }
            + summaries.filter {
                $0 == .section(.uncertain) || (nodes[$0]?.stats.hasContributions ?? false)
            }
    }

    public var visibleRows: [ContributorRow] {
        var rows: [ContributorRow] = []
        func visit(_ id: ContributorID, depth: Int) {
            guard let node = nodes[id] else { return }
            if node.process != nil && !node.stats.filtered.isEmpty { return }
            rows.append(ContributorRow(node: node, depth: depth))
            if open.contains(id) || (showAll && (id == .section(.remainder) || id == .section(.recent))) {
                for child in node.children where !pinned.contains(child) { visit(child, depth: depth + 1) }
            }
        }
        for id in topLevel { visit(id, depth: 0) }
        return rows
    }

    public mutating func resetInspection() {
        source = nil
        detailsVisible = false
        main = []
        formerlySelected = [:]
        nodes = [:]
        totals = ContributorStats()
        selection = nil
        open = []
        detailOffset = 0
    }

    public mutating func toggle(_ id: ContributorID) {
        selection = id
        detailOffset = 0
        if !open.insert(id).inserted { open.remove(id) }
    }
    public mutating func select(_ id: ContributorID) { if nodes[id] != nil { selection = id } }
    public mutating func toggleDetails() {
        detailsVisible.toggle()
        detailOffset = 0
    }
    public mutating func scroll(by delta: Int) { detailOffset = max(0, detailOffset + delta) }
    public mutating func move(by delta: Int) {
        detailOffset = 0
        detailsVisible = false
        let ids = visibleRows.map(\.id)
        guard !ids.isEmpty else { return }
        let index = selection.flatMap { ids.firstIndex(of: $0) } ?? 0
        selection = ids[min(ids.count - 1, max(0, index + delta))]
    }
    public mutating func disclose(_ expanded: Bool) {
        guard let selection else { return }
        detailOffset = 0
        if expanded { open.insert(selection) } else { open.remove(selection) }
    }
    public mutating func togglePin() {
        func session(_ id: ContributorID) -> ContributorID? {
            switch id {
            case .session(let provider, let id, let root):
                return .session(provider: provider, session: root ?? id, root: nil)
            case .executable(let parent, _), .process(let parent, _): return session(parent)
            case .provider, .section, .collapsed: return nil
            }
        }
        guard let selection, let id = session(selection) else { return }
        if let index = pinned.firstIndex(of: id) { pinned.remove(at: index) } else { pinned.append(id) }
        partition()
    }

    public mutating func receive(_ snapshot: MonitoringSnapshot) {
        guard let recent = snapshot.recentActivity else { return }
        if runID != recent.runID || scope != recent.scope {
            let enabled = enabled
            let showAll = showAll
            let pinned = pinned
            let order = order
            self = Self(memoryCapacityBytes: memoryCapacityBytes)
            self.order = order
            self.enabled = enabled
            self.showAll = showAll
            self.pinned = pinned
            scope = recent.scope
            runID = recent.runID
        }
        latestTime = recent.endedAt
        let displayBaseline = recent.displayUnits.first?.baselineScan ?? recent.finalScan
        duration =
            snapshot.window?.durationSeconds
            ?? recent.displayUnits.first.map { recent.endedAt - $0.startedAt } ?? 0
        var entries: [RecentWorkerCategory: ContributorStats] = [:]
        var metadata: [RecentWorkerCategory: RecentWorkerRecord] = [:]
        var peaks: [RecentWorkerCategory: RecentMemoryReading] = [:]
        var first: [RecentWorkerCategory: Double] = [:]
        var changes: [RecentWorkerCategory: Int] = [:]
        var evidence: [RecentWorkerCategory: Set<String>] = [:]
        func remember(_ record: RecentWorkerRecord) {
            let key = record.category
            if metadata[key].map({ $0.lastScan < record.lastScan }) ?? true { metadata[key] = record }
            first[key] = min(first[key] ?? record.firstObservedAt, record.firstObservedAt)
            if let peak = record.kernelPeak, peaks[key].map({ $0.scan < peak.scan }) ?? true {
                peaks[key] = peak
            }
        }
        for unit in recent.units {
            for record in unit.records {
                let key = record.category
                remember(record)
                changes[key, default: 0] += record.executableChangedIntervals
                evidence[key, default: []].formUnion(record.evidenceKinds.map(\.rawValue))
                var stats = entries[key] ?? ContributorStats()
                if stats.processes.isEmpty {
                    stats.processes.insert(key.process)
                    if key.isAgentRuntime {
                        stats.runtimes.insert(key.process)
                    } else {
                        stats.workers.insert(key.process)
                    }
                }
                stats.recentCPU += record.cpuSeconds
                stats.recentMeasurements += record.measuredIntervals
                stats.exclusions += record.excludedObservations
                if !key.isAgentRuntime, let reading = record.maximumFootprint,
                    stats.maximumWorkerFootprint.map({ reading.bytes > $0.bytes }) ?? true
                {
                    stats.maximumWorkerFootprint = reading
                }
                entries[key] = stats
            }
            for crossing in unit.crossings {
                if crossing.contribution.id.opening.scan.sequence >= recent.baselineScan {
                    entries[crossing.category, default: ContributorStats()].recentCPU +=
                        crossing.contribution.cpuSeconds
                    entries[crossing.category, default: ContributorStats()].recentMeasurements += 1
                } else {
                    entries[crossing.category, default: ContributorStats()].recoveredCPU +=
                        crossing.contribution.cpuSeconds
                }
            }
        }
        for unit in recent.displayUnits {
            for record in unit.records {
                let key = record.category
                remember(record)
                entries[key, default: ContributorStats()].processes.insert(key.process)
                entries[key, default: ContributorStats()].currentCPU += record.cpuSeconds
                entries[key, default: ContributorStats()].currentMeasurements += record.measuredIntervals
            }
            for crossing in unit.crossings
            where crossing.contribution.id.opening.scan.sequence >= displayBaseline {
                entries[crossing.category, default: ContributorStats()].currentCPU +=
                    crossing.contribution.cpuSeconds
                entries[crossing.category, default: ContributorStats()].currentMeasurements += 1
            }
        }
        let currentCategories = Set(recent.current.map(\.category))
        for record in recent.current {
            let key = record.category
            remember(record)
            entries[key, default: ContributorStats()].processes.insert(key.process)
            entries[key, default: ContributorStats()].current.insert(key.process)
            if let bytes = record.latestFootprint {
                entries[key, default: ContributorStats()].memoryBytes += bytes
            } else {
                entries[key, default: ContributorStats()].missingMemory += 1
            }
        }
        let thresholds = Thresholds(
            cpuPercent: snapshot.cpuThresholdPercent, memoryBytes: snapshot.memoryThresholdBytes)
        var perProcess: [ProcessIdentity: ContributorStats] = [:]
        for (key, entry) in entries { perProcess[key.process, default: ContributorStats()].merge(entry) }
        var lastFootprints: [ProcessIdentity: RecentWorkerRecord] = [:]
        for record in metadata.values {
            if lastFootprints[record.category.process].map({ $0.lastScan < record.lastScan }) ?? true {
                lastFootprints[record.category.process] = record
            }
        }
        let filtered = Set(
            perProcess.compactMap { identity, stats -> ProcessIdentity? in
                let cpu =
                    stats.currentMeasurements > 0 && duration > 0 ? 100 * stats.currentCPU / duration : nil
                return thresholds.includes(
                    cpu: cpu,
                    footprint: stats.current.isEmpty
                        ? lastFootprints[identity]?.latestFootprint
                        : (stats.missingMemory > 0 ? nil : stats.memoryBytes)) ? nil : identity
            })
        nodes = [:]
        totals = ContributorStats()
        for section in [ContributorSection.recent, .remainder, .uncertain, .shared, .released] {
            let id = ContributorID.section(section)
            nodes[id] = ContributorNode(id: id, title: section.rawValue)
        }
        var projects: [ContributorID: Set<String?>] = [:]
        var exact: Set<ContributorID> = []
        for (key, var stats) in entries {
            stats.currentAvailable = recent.currentContextAvailable
            if recent.currentContextAvailable {
                stats.noLongerObserved = stats.workers.subtracting(recent.present)
                if recent.present.contains(key.process) && !currentCategories.contains(key) {
                    stats.membershipChanged.insert(key.process)
                }
            }
            if filtered.contains(key.process) { stats.filtered.insert(key.process) }
            totals.merge(stats)
            let path = path(for: key)
            if case .session = path[0].0 { exact.insert(path[0].0) }
            for (index, item) in path.enumerated() {
                let (id, title) = item
                if nodes[id] == nil { nodes[id] = ContributorNode(id: id, title: title) }
                nodes[id]?.stats.merge(stats)
                if case .session = id, !key.isAgentRuntime {
                    projects[id, default: []].insert(metadata[key]?.cwd)
                }
                if index + 1 < path.count, !(nodes[id]?.children.contains(path[index + 1].0) ?? false) {
                    nodes[id]?.children.append(path[index + 1].0)
                }
            }
            let leaf = path.last!.0
            nodes[leaf]?.process = key.process
            if let record = metadata[key] {
                nodes[leaf]?.evidence.append(
                    ContributorEvidence(
                        record: record, stats: stats,
                        first: first[key], peak: peaks[key], currentAvailable: recent.currentContextAvailable,
                        present: recent.present.contains(key.process), changes: changes[key] ?? 0,
                        evidence: evidence[key] ?? []))
            }
        }
        var collapsedDisplay: [CollapsedCategory: CollapsedContribution] = [:]
        var collapsedRecent: [CollapsedCategory: CollapsedContribution] = [:]
        for value in snapshot.window?.collapsedContributions ?? [] {
            if collapsedDisplay[value.category] == nil {
                collapsedDisplay[value.category] = value
            } else {
                collapsedDisplay[value.category]?.merge(value)
            }
        }
        for unit in recent.units {
            for value in unit.collapsedContributions {
                if collapsedRecent[value.category] == nil {
                    collapsedRecent[value.category] = value
                } else {
                    collapsedRecent[value.category]?.merge(value)
                }
            }
        }
        for key in Set(collapsedDisplay.keys).union(collapsedRecent.keys) {
            guard let value = collapsedDisplay[key] ?? collapsedRecent[key] else { continue }
            var stats = ContributorStats()
            stats.collapsedProcesses = value.processCount
            stats.collapsedWorkers = value.workerCount
            if collapsedDisplay[key] != nil, let historical = collapsedRecent[key] {
                // Time containment does not prove identity containment after detail release.
                // The pressure contract therefore requires max/sum bounds across both sources.
                stats.collapsedProcesses?.union(historical.processCount)
                stats.collapsedWorkers?.union(historical.workerCount)
            }
            if key.isAgentRuntime == false {
                stats.maximumWorkerFootprint = collapsedRecent[key]?.maximumFootprint
            }
            stats.currentCPU = collapsedDisplay[key]?.cpuSeconds ?? 0
            stats.currentMeasurements = collapsedDisplay[key]?.intervalCount ?? 0
            stats.recentCPU = collapsedRecent[key]?.cpuSeconds ?? 0
            stats.recentMeasurements = collapsedRecent[key]?.intervalCount ?? 0
            totals.merge(stats)
            let parent: ContributorID
            if !key.categoryDetailsRetained {
                parent = .section(.released)
            } else if let session = key.sessionID, key.resolution == .candidate {
                parent = .session(
                    provider: key.provider?.rawValue ?? "agent", session: key.rootSessionID ?? session,
                    root: nil)
                exact.insert(parent)
            } else {
                parent = .section(key.resolution == .shared ? .shared : .uncertain)
            }
            if nodes[parent] == nil {
                nodes[parent] = ContributorNode(
                    id: parent,
                    title:
                        "\(key.provider?.rawValue ?? "Agent") · \(key.rootSessionID ?? key.sessionID ?? "unresolved")"
                )
            }
            nodes[parent]?.stats.merge(stats)
            var leafParent = parent
            if let root = key.rootSessionID, let session = key.sessionID, key.resolution == .candidate {
                let thread = ContributorID.session(
                    provider: key.provider?.rawValue ?? "agent", session: session, root: root)
                if nodes[thread] == nil {
                    nodes[thread] = ContributorNode(id: thread, title: "Thread · " + session)
                }
                nodes[thread]?.stats.merge(stats)
                if !(nodes[parent]?.children.contains(thread) ?? false) {
                    nodes[parent]?.children.append(thread)
                }
                leafParent = thread
            }
            let id = ContributorID.collapsed(key)
            let label =
                key.executable?.split(separator: "/").last.map(String.init) ?? "category detail released"
            var node = ContributorNode(id: id, title: "Collapsed · " + label)
            node.stats = stats
            node.labels = [
                collapsedDisplay[key].map { "Display window: " + AccountingContext.collapsed($0) },
                collapsedRecent[key].map { "Recent history: " + AccountingContext.collapsed($0) },
            ].compactMap { $0 }
            nodes[id] = node
            nodes[leafParent]?.children.append(id)
        }
        for (id, projects) in projects {
            if case .session(let provider, let session, _) = id {
                nodes[id]?.title =
                    "\(ProjectLabel.make(Array(projects))) · \(provider)/\(session.prefix(8))"
                nodes[id]?.labels = ["Exact session: \(provider)/\(session)"]
            }
        }
        for id in exact {
            if let child = nodes[id]?.children, child.count == 1, case .session = child[0],
                let nested = nodes[child[0]]
            {
                nodes[id]?.children = nested.children
            }
        }
        let eligible = exact.filter {
            guard let stats = nodes[$0]?.stats else { return false }
            return stats.collapsedProcesses != nil || !stats.processes.subtracting(filtered).isEmpty
        }
        cpuRank = rank(cpuRank, candidates: eligible, floor: 25) {
            guard duration > 0, let stats = nodes[$0]?.stats, stats.currentMeasurements > 0 else {
                return nil
            }
            let percent = 100 * stats.currentCPU / duration
            return percent > 25 ? percent : nil
        }
        memoryRank = rank(memoryRank, candidates: eligible, floor: 100_000_000) {
            nodes[$0].map { Double($0.stats.memoryBytes) }
        }
        let selected = Set(cpuRank + memoryRank)
        let previous = main
        for id in previous where !selected.contains(id) { formerlySelected[id] = latestTime }
        formerlySelected = formerlySelected.filter { latestTime - $0.value <= 60 && nodes[$0.key] != nil }
        main = previous.filter { selected.contains($0) }
        let newcomers = selected.subtracting(main)
        let preferred = order == .cpu ? cpuRank : memoryRank
        let secondary = order == .cpu ? memoryRank : cpuRank
        let primaryArrivals = contributionOrder(preferred.filter { newcomers.contains($0) })
        main +=
            primaryArrivals
            + contributionOrder(
                secondary.filter { newcomers.contains($0) && !primaryArrivals.contains($0) },
                by: order == .cpu ? .memory : .cpu)
        partition()
        for id in pinned where nodes[id] == nil {
            nodes[id] = ContributorNode(id: id, title: "Pinned · outside retained range")
        }
        open.formIntersection(nodes.keys)
        if !visibleRows.contains(where: { $0.id == selection }) { selection = visibleRows.first?.id }
        if !recent.currentContextAvailable {
            totals.currentAvailable = false
            for id in nodes.keys { nodes[id]?.stats.currentAvailable = false }
        }
        let observed = Set(snapshot.observedFindings.map(\.process))
        let historical = snapshot.observedFindings.filter(\.isHistorical).count
        var observedBounds = LifetimeCountRange(minimum: observed.count, maximum: observed.count)
        for record in collapsedDisplay.values { observedBounds.union(record.processCount) }
        let observedText =
            observedBounds.minimum == observedBounds.maximum
            ? "\(observedBounds.minimum)" : "\(observedBounds.minimum)–\(observedBounds.maximum)"
        census =
            "\(observedText) observed \(recent.scope == .allProcesses ? "same-user" : "agent-associated") processes in this window, including \(historical) retained no-longer-observed identities"
        source = recent
        var warnings: [String] = []
        let collapsedValues = Array(collapsedDisplay.values) + Array(collapsedRecent.values)
        if !collapsedValues.isEmpty {
            let oldest = collapsedValues.map(\.startedAt).min() ?? recent.endedAt
            let newest = collapsedValues.map(\.endedAt).max() ?? recent.endedAt
            warnings.append(
                "\(Set(collapsedDisplay.keys).union(collapsedRecent.keys).count) collapsed categories · \(number(max(0, recent.endedAt - newest)))–\(number(max(0, recent.endedAt - oldest))) s ago"
            )
        }
        var publication = PublicationCoverage()
        for unit in recent.units { publication.merge(unit.publicationCoverage) }
        if let disclosure = AccountingContext.publication(publication, range: .recent) {
            warnings.append(disclosure)
        }
        if let timing = snapshot.window?.acquisitionCoverage, timing.overrunCount > 0 {
            warnings.append("\(timing.overrunCount) sampling overruns")
        }
        var readCoverage = ReadCoverage()
        for unit in recent.units { readCoverage.merge(unit.readCoverage) }
        if readCoverage.failedPIDCount.maximum > 0 {
            warnings.append("\(readCoverage.failedPIDCount.text) listed PIDs: read gaps")
        }
        if readCoverage.releasedAll != nil {
            let start = readCoverage.startedAt ?? recent.endedAt
            let end = readCoverage.endedAt ?? recent.endedAt
            warnings.append(
                "read-gap detail collapsed · \(number(max(0, recent.endedAt - end)))–\(number(max(0, recent.endedAt - start))) s ago"
            )
        }
        if readCoverage.unidentifiedFailureObservations > 0 {
            warnings.append("\(readCoverage.unidentifiedFailureObservations) unidentified failed reads")
        }
        if totals.exclusions > 0 { warnings.append("\(totals.exclusions) excluded") }
        if totals.missingMemory > 0 { warnings.append("\(totals.missingMemory) memory unavailable") }
        if !recent.currentContextAvailable { warnings.append("current data unavailable") }
        samplingCoverage = SamplingCoverageSummary(
            snapshot: snapshot, reads: readCoverage, observed: observedBounds,
            recentDuration: recent.duration, retentionLimited: recent.retentionLimited)
        coverageWarning = warnings.isEmpty ? "" : "⚠ " + warnings.joined(separator: " · ")
        coverage =
            "Recent \(number(recent.duration)) s"
            + (recent.retentionLimited ? " (retention limit / gap)" : "")
            + " · collection-wide failed PID values: \(readCoverage.failedPIDCount.text) distinct"
            + " (\(readCoverage.deniedPIDCount.text) denied, \(readCoverage.vanishedPIDCount.text) vanished, \(readCoverage.mismatchedPIDCount.text) identity changed, \(readCoverage.otherPIDCount.text) other; categories may overlap)"
            + " · failures per scan: mean \(number(readCoverage.meanFailedPIDsPerScan)), max \(readCoverage.maximumFailedPIDsPerScan)"
            + " · \(readCoverage.unidentifiedFailureObservations) unidentified failed-read observations"
            + " · \(totals.exclusions) excluded readings · \(number(totals.recoveredCPU)) s older-opening recovery"
            + (recent.currentContextAvailable ? "" : " · current presence unavailable")
            + " · run \(recent.runID.uuidString.prefix(6))"
        if let range = AccountingContext.publicationRange(publication, endingAt: recent.endedAt) {
            coverage += " · " + range
        }
        if let timing = snapshot.window?.acquisitionCoverage {
            coverage += " · " + AccountingContext.acquisition(timing)
        }
    }

    private mutating func partition() {
        for section in [ContributorSection.recent, .remainder] {
            nodes[.section(section)]?.stats = ContributorStats()
            nodes[.section(section)]?.children = []
        }
        for (id, node) in nodes {
            guard case .session(_, _, nil) = id, !main.contains(id), !pinned.contains(id) else { continue }
            let section: ContributorSection =
                node.stats.recentCPU >= 0.5
                    || (node.stats.maximumWorkerFootprint?.bytes ?? 0) >= 100_000_000
                    || formerlySelected[id] != nil ? .recent : .remainder
            nodes[.section(section)]?.children.append(id)
            nodes[.section(section)]?.stats.merge(node.stats)
        }
        sortChildren()
    }

    private func rank(
        _ previous: [ContributorID], candidates: Set<ContributorID>, floor: Double,
        metric: (ContributorID) -> Double?
    ) -> [ContributorID] {
        let values = Dictionary(
            uniqueKeysWithValues: candidates.compactMap { id -> (ContributorID, Double)? in
                guard let value = metric(id), value >= floor else { return nil }
                return (id, value)
            })
        var result = previous.filter { values[$0] != nil }
        let challengers = values.keys.sorted {
            values[$0] == values[$1] ? identity($0) < identity($1) : values[$0]! > values[$1]!
        }
        for id in challengers where !result.contains(id) {
            if result.count < 5 {
                result.append(id)
            } else if let weakest = result.min(by: {
                values[$0] == values[$1] ? identity($0) > identity($1) : values[$0]! < values[$1]!
            }), values[id]! > 1.2 * values[weakest]! {
                result[result.firstIndex(of: weakest)!] = id
            }
        }
        return result
    }

    private func path(for key: RecentWorkerCategory) -> [(ContributorID, String)] {
        let owner = key.owner
        let provider = owner.provider?.rawValue ?? "unknown provider"
        var result: [(ContributorID, String)] = []
        if let session = owner.sessionID, owner.resolution == .candidate {
            let top = ContributorID.session(
                provider: provider, session: owner.rootSessionID ?? session, root: nil)
            result.append((top, "\(provider) · \(owner.rootSessionID ?? session)"))
            if let root = owner.rootSessionID {
                result.append(
                    (.session(provider: provider, session: session, root: root), "Thread · \(session)"))
            }
        } else {
            let section = ContributorID.section(owner.resolution == .shared ? .shared : .uncertain)
            result.append(
                (section, owner.resolution == .shared ? "Shared agent runtimes" : "Unresolved / uncertain"))
            result.append(
                (
                    .provider(parent: section, name: provider + "/" + owner.resolution.rawValue),
                    "\(provider) · \(owner.resolution.rawValue)"
                ))
        }
        let family = ContributorID.executable(parent: result.last!.0, name: key.executableName)
        result.append((family, "executable \(key.executableName)"))
        result.append(
            (
                .process(parent: family, identity: key.process),
                "\(key.executableName) · PID \(key.process.pid)"
            ))
        return result
    }

}

struct ContributorEvidence: Equatable, Sendable {
    let record: RecentWorkerRecord
    let stats: ContributorStats
    let first: Double?
    let peak: RecentMemoryReading?
    let currentAvailable: Bool
    let present: Bool
    let changes: Int
    let evidence: Set<String>

    var details: [String] {
        let key = record.category
        let state =
            currentAvailable
            ? (present
                ? (stats.current.isEmpty
                    ? "Observed elsewhere; membership changed" : "Observed in final scan")
                : "No longer observed; exit unconfirmed")
            : "Final-scan presence unavailable"
        var result = [
            state, "Lifetime: PID \(key.process.pid), start µs \(key.process.startMicroseconds)",
            "\(key.isAgentRuntime ? "Adapter-recognised agent runtime" : "Worker") · \(key.executable)",
            "First/last observed: \(number(first ?? record.firstObservedAt))–\(number(record.lastObservedAt)) monotonic s",
            "Ownership: \(key.owner.resolution.rawValue); \(evidence.sorted().joined(separator: ", "))",
            "Frozen root: \(key.owner.rootSessionID ?? "not corroborated") · \(stats.membershipChanged.count) changed memberships",
            "\(stats.recentMeasurements) accepted intervals · \(stats.exclusions) excluded readings",
        ]
        if let maximum = stats.maximumWorkerFootprint {
            result.append(
                "Largest sampled worker footprint: \(number(Double(maximum.bytes) / 1e6)) MB at \(number(maximum.observedAt)) s, scan \(maximum.scan), \(maximum.evidence.rawValue)"
            )
        }
        if let peak {
            result.append(
                "Last observed kernel task peak: \(number(Double(peak.bytes) / 1e6)) MB at \(number(peak.observedAt)) s, scan \(peak.scan), \(peak.evidence.rawValue)\(record.kernelPeakUnavailable ? "; later reading unavailable" : "")"
            )
            result.append("Kernel peak time/exec epoch unverified; may predate this range and reset on exec")
        }
        if !key.owner.candidates.isEmpty {
            result.append("Conflicting candidates: " + key.owner.candidates.joined(separator: ", "))
        }
        if changes > 0 {
            result.append("Executable changed across interval (\(changes)); exec time unverified")
        }
        if let cwd = record.cwd { result.append("Directory: " + cwd) }
        if let command = record.command { result.append("Command: " + command.joined(separator: " ")) }
        return result
    }
}

private func number(_ value: Double) -> String { String(format: "%.1f", value) }
private func identity(_ id: ContributorID) -> String {
    func field(_ value: String) -> String { "\(value.utf8.count):" + value }
    switch id {
    case .section(let section): return "s" + section.rawValue
    case .collapsed(let category):
        return "c"
            + [
                category.provider?.rawValue, category.sessionID, category.rootSessionID,
                category.resolution?.rawValue, category.executable, category.isAgentRuntime.map(String.init),
                String(category.agentAssociated), String(category.categoryDetailsRetained),
            ].compactMap { $0 }.joined(separator: "|")
    case .session(let provider, let session, let root):
        return "g" + field(provider) + field(session) + field(root ?? "")
    case .provider(let parent, let name): return identity(parent) + "p" + field(name)
    case .executable(let parent, let name): return identity(parent) + "e" + field(name)
    case .process(let parent, let process):
        return identity(parent) + "i\(process.pid):\(process.startMicroseconds)"
    }
}

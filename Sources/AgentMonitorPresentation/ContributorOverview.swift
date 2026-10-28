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
    /// One contributor: a display name with its frozen workload directory (`nil` when unreadable,
    /// or for an agent runtime, whose directory is not a workload directory).
    case executable(parent: ContributorID, name: String, cwd: String?)
    /// The quantified remainder of a long contributor list.
    case more(parent: ContributorID)
    case process(parent: ContributorID, identity: ProcessIdentity)

    var parent: ContributorID? {
        switch self {
        case .section, .collapsed, .session: nil
        case .provider(let parent, _), .executable(let parent, _, _), .more(let parent),
            .process(let parent, _):
            parent
        }
    }
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

public struct ContributorRow: Equatable, Sendable, Identifiable {
    public let node: ContributorNode
    public let depth: Int
    public let isLastSibling: Bool
    public var id: ContributorID { node.id }
}

public enum ContributorOrder: String, Sendable { case contributor, cpu, memory }

/// One immutable-category projection and disclosure policy for native and terminal hosts.
public struct ContributorOverview: Equatable, Sendable {
    public private(set) var nodes: [ContributorID: ContributorNode] = [:]
    public private(set) var main: [ContributorID] = []
    public private(set) var totals = ContributorStats()
    public private(set) var duration = 0.0
    public private(set) var coverage = ""
    public private(set) var samplingCoverage: SamplingCoverageSummary?
    public private(set) var census = ""
    public private(set) var coverageStatus = CoverageStatus(notes: [])
    public private(set) var order: ContributorOrder = .cpu
    public private(set) var ascending = false
    public private(set) var runID: UUID?
    private var scope: ProcessScope?
    public private(set) var selection: ContributorID?
    public private(set) var open: Set<ContributorID> = []
    public var showAll = false
    public var enabled = true
    public private(set) var pinned: [ContributorID] = []
    public private(set) var pinNotice: String?
    private var unavailablePins: Set<ContributorID> = []
    private var cpuRank: [ContributorID] = []
    private var memoryRank: [ContributorID] = []
    private var formerlySelected: [ContributorID: Double] = [:]
    private var latestTime = 0.0
    public private(set) var activity = ContributorActivity()
    private var logicalCPUCount = 1
    private var source: RecentActivitySnapshot?
    var workloadDirectoryLabels: [String: String] = [:]
    public private(set) var detailOffset = 0
    public enum Focus: Sendable { case rows, details }
    public private(set) var focus: Focus = .rows
    public private(set) var detailsVisible = false {
        didSet { if !detailsVisible { focus = .rows } }
    }

    public init() {}

    public mutating func sort(by order: ContributorOrder, ascending: Bool = false) {
        self.order = order
        self.ascending = ascending
        expandRemainders()
        main = contributionOrder(main)
        sortChildren()
        limitContributors()
        rebuildActivity()
    }
    private mutating func sortChildren() {
        for id in Array(nodes.keys) {
            let children = contributionOrder(nodes[id]?.children ?? [])
            nodes[id]?.children = children
        }
    }
    private func value(_ id: ContributorID, _ metric: ContributorOrder) -> Double {
        let stats = nodes[id]?.stats
        switch metric {
        case .contributor: return 0
        case .cpu: return stats?.currentCPU ?? 0
        case .memory: return Double(stats?.memoryBytes ?? 0)
        }
    }
    private func contributionOrder(_ ids: [ContributorID]) -> [ContributorID] {
        let secondary: ContributorOrder = order == .cpu ? .memory : .cpu
        return ids.sorted {
            if order == .contributor {
                let a = nodes[$0]?.title ?? ""
                let b = nodes[$1]?.title ?? ""
                if a != b { return ascending ? a < b : a > b }
                return ascending ? identity($0) < identity($1) : identity($0) > identity($1)
            }
            let a = value($0, order)
            let b = value($1, order)
            guard a == b else { return ascending ? a < b : a > b }
            let c = value($0, secondary)
            let d = value($1, secondary)
            return c == d ? identity($0) < identity($1) : c > d
        }
    }
    /// Refresh order: rows keep their previous positions unless one exceeds a row above it by
    /// more than the 120% challenger band, so values jittering under a selection do not reshuffle
    /// the list while a sustained leader still rises. Each insertion goes before the first row it
    /// beats, which keeps every row within the band of all rows above it; explicit sorting stays exact.
    private func refreshOrder(_ ids: [ContributorID], previous: [ContributorID]) -> [ContributorID] {
        if order == .contributor || ascending { return contributionOrder(ids) }
        let present = Set(ids)
        let survivors = previous.filter { present.contains($0) }
        let known = Set(survivors)
        var result: [ContributorID] = []
        for id in survivors + contributionOrder(ids.filter { !known.contains($0) }) {
            let metric = value(id, order)
            if let index = result.firstIndex(where: { metric > 1.2 * value($0, order) }) {
                result.insert(id, at: index)
            } else {
                result.append(id)
            }
        }
        return result
    }
    public var sourceDurationLabel: String {
        guard let source else { return "unavailable" }
        return "\(number(source.duration)) s" + (source.retentionLimited ? " (retention limit / gap)" : "")
    }

    public var population: (main: Int, total: Int) {
        let retained = Set(
            nodes.values.compactMap { node -> ContributorID? in
                guard case .session(_, _, nil) = node.id, node.stats.hasContributions else { return nil }
                return node.id
            })
        let selected = retained.intersection(Set(main + pinned)).count
        return (selected, retained.count)
    }

    public var title: String {
        let counts = population
        return showAll
            ? "All contributors (\(counts.total))"
            : "Main contributors (\(counts.main)/\(counts.total))"
    }

    public var populationHelp: String {
        "Main or pinned / all retained session groups. A root and its threads count once. Shared, unresolved and released-detail work are shown separately."
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
        func visit(_ id: ContributorID, depth: Int, last: Bool = false) {
            guard let node = nodes[id] else { return }
            if node.process != nil && !node.stats.filtered.isEmpty { return }
            rows.append(ContributorRow(node: node, depth: depth, isLastSibling: last))
            if isExpanded(id) {
                let children = node.children.filter {
                    guard !pinned.contains($0), let child = nodes[$0] else { return false }
                    return child.process == nil || child.stats.filtered.isEmpty
                }
                for (index, child) in children.enumerated() {
                    visit(child, depth: depth + 1, last: index == children.count - 1)
                }
            }
        }
        for id in topLevel { visit(id, depth: 0) }
        return rows
    }

    public func isExpanded(_ id: ContributorID) -> Bool {
        open.contains(id) || (showAll && (id == .section(.remainder) || id == .section(.recent)))
    }

    public mutating func resetInspection() {
        source = nil
        activity = ContributorActivity()
        unavailablePins = []
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
        detailsVisible = false
        detailOffset = 0
        if !open.insert(id).inserted { open.remove(id) }
    }
    public mutating func activateRow(_ id: ContributorID) {
        guard visibleRows.contains(where: { $0.id == id }) else { return }
        select(id)
        setDisclosure(expanded: !isExpanded(id), for: id)
    }

    public mutating func select(_ id: ContributorID) {
        guard nodes[id] != nil, selection != id else { return }
        selection = id
        detailsVisible = false
        detailOffset = 0
    }
    public mutating func toggleDetails() {
        detailsVisible.toggle()
        focus = detailsVisible ? .details : .rows
        detailOffset = 0
    }
    public mutating func toggleFocus() {
        guard detailsVisible else { return }
        focus = focus == .rows ? .details : .rows
    }
    public mutating func scroll(by delta: Int, maximum: Int = .max) {
        detailOffset = min(maximum, max(0, min(detailOffset, maximum) + delta))
    }
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
        setDisclosure(expanded: expanded, for: selection)
    }
    public mutating func setDisclosure(expanded: Bool, for id: ContributorID) {
        guard let node = nodes[id], !node.children.isEmpty,
            visibleRows.contains(where: { $0.id == id })
        else { return }
        detailOffset = 0
        if !expanded, showAll, id == .section(.recent) || id == .section(.remainder) {
            open.formUnion([.section(.recent), .section(.remainder)])
            showAll = false
        }
        if expanded { open.insert(id) } else { open.remove(id) }
        if let selection, !visibleRows.contains(where: { $0.id == selection }) {
            select(id)
        }
    }
    @discardableResult public mutating func togglePin() -> Bool {
        func session(_ id: ContributorID) -> ContributorID? {
            switch id {
            case .session(let provider, let id, let root):
                return .session(provider: provider, session: root ?? id, root: nil)
            case .executable(let parent, _, _), .more(let parent), .process(let parent, _):
                return session(parent)
            case .provider, .section, .collapsed: return nil
            }
        }
        guard let selection, let id = session(selection) else { return false }
        if let index = pinned.firstIndex(of: id) {
            pinned.remove(at: index)
            if unavailablePins.remove(id) != nil { nodes.removeValue(forKey: id) }
        } else {
            guard
                PinLimits.admits(
                    count: pinned.count, bytes: pinned.reduce(0) { $0 + $1.pinTextBytes },
                    adding: id.pinTextBytes)
            else {
                pinNotice = PinLimits.refusal
                return false
            }
            pinned.append(id)
        }
        reconcilePins()
        return true
    }

    public mutating func unpinAll() {
        pinned.removeAll()
        for id in unavailablePins { nodes.removeValue(forKey: id) }
        unavailablePins.removeAll()
        reconcilePins()
    }

    private mutating func reconcilePins() {
        pinNotice = nil
        partition(previous: nodes.mapValues(\.children))
        rebuildActivity()
        open.formIntersection(nodes.keys)
        if !visibleRows.contains(where: { $0.id == selection }) {
            selection = visibleRows.first?.id
            detailsVisible = false
            detailOffset = 0
        }
    }

    private mutating func rebuildActivity() {
        guard let source else { return }
        activity = ContributorActivity(recent: source, nodes: nodes, logicalCPUCount: logicalCPUCount) {
            path(for: $0).last!.0
        }
    }

    public mutating func receive(_ snapshot: MonitoringSnapshot) {
        guard let recent = snapshot.recentActivity else { return }
        if runID != recent.runID || scope != recent.scope {
            let enabled = enabled
            let showAll = showAll
            let pinned = pinned
            let order = order
            self = Self()
            self.order = order
            self.enabled = enabled
            self.showAll = showAll
            self.pinned = pinned
            scope = recent.scope
            runID = recent.runID
        }
        logicalCPUCount = snapshot.cpuAccounting.logicalCPUCount
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
        let previousChildren = nodes.mapValues(\.children)
        nodes = [:]
        totals = ContributorStats()
        for section in [ContributorSection.recent, .remainder, .uncertain, .shared, .released] {
            let id = ContributorID.section(section)
            nodes[id] = ContributorNode(id: id, title: section.rawValue)
        }
        var projects: [ContributorID: Set<String?>] = [:]
        var runtimeContributors: Set<ContributorID> = []
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
                    projects[id, default: []].insert(key.cwd)
                }
                if index + 1 < path.count, !(nodes[id]?.children.contains(path[index + 1].0) ?? false) {
                    nodes[id]?.children.append(path[index + 1].0)
                }
            }
            let leaf = path.last!.0
            if key.isAgentRuntime { runtimeContributors.insert(path[path.count - 2].0) }
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
                key.invocationName ?? key.executable?.split(separator: "/").last.map(String.init)
                ?? "category detail released"
            var node = ContributorNode(id: id, title: "Collapsed · " + label)
            node.stats = stats
            node.labels =
                (collapsedDisplay[key].map { InspectionField.collapsed($0, window: "Display window") } ?? [])
                + (collapsedRecent[key].map { InspectionField.collapsed($0, window: "Recent history") } ?? [])
            nodes[id] = node
            nodes[leafParent]?.children.append(id)
        }
        let names = SessionDisplayNames(records: metadata.values)
        let directoryLabels = WorkloadDirectory.compactLabels(
            for: Set(entries.keys.filter { !$0.isAgentRuntime }.compactMap(\.cwd)))
        workloadDirectoryLabels = directoryLabels
        for id in Array(nodes.keys) {
            switch id {
            case .session(let provider, let session, let root):
                let directories = projects[id] ?? []
                let name = names.name(provider: provider, session: session)
                nodes[id]?.label = .session(
                    identity: (root == nil ? "\(provider) · " : "Thread · ") + session.prefix(8),
                    name: name,
                    directory: directories.isEmpty
                        ? nil : WorkloadDirectory.summary(directories, labels: directoryLabels))
                nodes[id]?.labels =
                    [InspectionField("Exact session", "\(provider)/\(session)")]
                    + (name.map { [InspectionField("Listed name", $0)] } ?? [])
                    + directories.map { $0 ?? "unavailable" }.sorted().map {
                        InspectionField("Directory", $0)
                    }
            case .executable(let parent, let name, let cwd):
                let owner = sequence(first: parent, next: \.parent).first {
                    if case .session = $0 { true } else { false }
                }
                let workers = nodes[id]?.stats.processes.count ?? 0
                // A single directory is already shown on the owning session row.
                let directoryOnOwner = owner.map { (projects[$0]?.count ?? 0) <= 1 } ?? false
                nodes[id]?.label = .workload(
                    name: name + (workers > 1 ? " ×\(workers)" : ""),
                    directory: runtimeContributors.contains(id) || directoryOnOwner
                        ? nil
                        : (cwd.map { directoryLabels[$0] ?? WorkloadDirectory.compact($0) }
                            ?? "CWD unavailable")
                )
                var labels: [InspectionField] = []
                if case .session(let provider, let session, _) = owner {
                    labels = [InspectionField("Agent", provider), InspectionField("Session", session)]
                    if let name = names.name(provider: provider, session: session) {
                        labels.append(InspectionField("Listed name", name))
                    }
                }
                labels.append(InspectionField("Directory", cwd ?? "Unavailable"))
                labels.append(InspectionField("Executable group", name))
                nodes[id]?.labels = labels
            case .section, .collapsed, .provider, .more, .process: continue
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
        for id in main where !selected.contains(id) { formerlySelected[id] = latestTime }
        formerlySelected = formerlySelected.filter { latestTime - $0.value <= 60 && nodes[$0.key] != nil }
        main = refreshOrder(Array(selected), previous: main)
        partition(previous: previousChildren)
        unavailablePins = Set(pinned.filter { nodes[$0] == nil })
        for id in unavailablePins {
            nodes[id] = ContributorNode(id: id, title: "Pinned · outside retained range")
        }
        open.formIntersection(nodes.keys)
        if !visibleRows.contains(where: { $0.id == selection }) {
            detailsVisible = false
            selection = visibleRows.first?.id
        }
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
        rebuildActivity()
        var notes: [CoverageStatus.Note] = []
        let collapsedValues = Array(collapsedDisplay.values) + Array(collapsedRecent.values)
        if !collapsedValues.isEmpty {
            let oldest = collapsedValues.map(\.startedAt).min() ?? recent.endedAt
            let newest = collapsedValues.map(\.endedAt).max() ?? recent.endedAt
            notes.append(
                CoverageStatus.Note(
                    "\(Set(collapsedDisplay.keys).union(collapsedRecent.keys).count) collapsed categories · \(number(max(0, recent.endedAt - newest)))–\(number(max(0, recent.endedAt - oldest))) s ago",
                    .warning,
                    help:
                        "Retention pressure released identity detail; collapsed rows keep quantified totals.")
            )
        }
        var publication = PublicationCoverage()
        for unit in recent.units { publication.merge(unit.publicationCoverage) }
        notes += [CoverageStatus.publication(publication, range: .recent, endingAt: recent.endedAt)]
            .compactMap { $0 }
        let acquisition = recent.acquisitionCoverage
        notes += [CoverageStatus.overruns(acquisition)].compactMap { $0 }
        var readCoverage = ReadCoverage()
        for unit in recent.units { readCoverage.merge(unit.readCoverage) }
        notes += CoverageStatus.reads(readCoverage)
        if readCoverage.releasedAll != nil {
            let start = readCoverage.startedAt ?? recent.endedAt
            let end = readCoverage.endedAt ?? recent.endedAt
            notes.append(
                CoverageStatus.Note(
                    "read-gap detail collapsed · \(number(max(0, recent.endedAt - end)))–\(number(max(0, recent.endedAt - start))) s ago",
                    .notice, help: "Released PID detail turns read-gap counts into ranges."))
        }
        if readCoverage.unidentifiedFailureObservations > 0 {
            notes.append(CoverageStatus.unidentified(readCoverage.unidentifiedFailureObservations))
        }
        if totals.exclusions > 0 {
            notes.append(
                CoverageStatus.Note(
                    "\(totals.exclusions) excluded", .warning,
                    help:
                        "Counter readings that contributed no CPU: unavailable, invalid or reset counters, or no usable baseline."
                ))
        }
        if totals.missingMemory > 0 {
            notes.append(
                CoverageStatus.Note(
                    "\(totals.missingMemory) memory unavailable", .warning,
                    help: "Current processes without a footprint reading; memory totals are lower bounds."))
        }
        if !recent.currentContextAvailable {
            notes.append(
                CoverageStatus.Note(
                    "current data unavailable", .warning, help: "Current presence could not be published."))
        }
        samplingCoverage = SamplingCoverageSummary(
            snapshot: snapshot, reads: readCoverage, observed: observedBounds,
            recentDuration: recent.duration, retentionLimited: recent.retentionLimited,
            inspection: recent.inspectionCoverage, acquisition: acquisition)
        coverageStatus = CoverageStatus(notes: notes)
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
        coverage += " · " + AccountingContext.acquisition(acquisition)
    }

    private mutating func partition(previous: [ContributorID: [ContributorID]]) {
        expandRemainders()
        let previous = previous.mapValues { children in
            children.flatMap { child -> [ContributorID] in
                if case .more = child { previous[child] ?? [] } else { [child] }
            }
        }
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
        for id in Array(nodes.keys) {
            let children = refreshOrder(nodes[id]?.children ?? [], previous: previous[id] ?? [])
            nodes[id]?.children = children
        }
        limitContributors()
    }

    /// Visible contributors per session or provider before the quantified remainder row.
    private static let visibleContributors = 3

    /// Long contributor lists show the leaders and one remainder row carrying the hidden rows' merged
    /// statistics, so expansion finds the contributing executables (product contract) while the
    /// list still conserves CPU, memory and lifetimes. A selection inside the remainder opens it.
    private mutating func limitContributors() {
        for id in Array(nodes.keys) {
            switch id {
            case .session, .provider: break
            case .section, .collapsed, .executable, .more, .process: continue
            }
            guard let children = nodes[id]?.children, children.count > Self.visibleContributors + 1 else {
                continue
            }
            let hidden = Array(children.dropFirst(Self.visibleContributors))
            let more = ContributorID.more(parent: id)
            var node = ContributorNode(id: more, title: "+\(hidden.count) more")
            for child in hidden { node.stats.merge(nodes[child]?.stats ?? ContributorStats()) }
            node.children = hidden
            nodes[more] = node
            nodes[id]?.children = Array(children.prefix(Self.visibleContributors)) + [more]
            let concealed = Set(hidden)
            if let selection, sequence(first: selection, next: \.parent).contains(where: concealed.contains) {
                open.insert(more)
            }
        }
    }

    private mutating func expandRemainders() {
        for id in Array(nodes.keys) {
            guard case .more(let parent) = id, let hidden = nodes[id]?.children else { continue }
            let shown = nodes[parent]?.children.filter { $0 != id } ?? []
            nodes[parent]?.children = shown + hidden
            nodes[id] = nil
        }
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
        // An adapter-recognised runtime's basename can be a version string (Claude's
        // `versions/<version>` install), so the runtime role names it instead.
        let name = key.isAgentRuntime ? "\(provider) runtime" : key.executableName
        let family = ContributorID.executable(
            parent: result.last!.0, name: name, cwd: key.isAgentRuntime ? nil : key.cwd)
        result.append((family, name))
        result.append((.process(parent: family, identity: key.process), "\(name) · PID \(key.process.pid)"))
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
                category.resolution?.rawValue, category.executable, category.invocationName,
                category.isAgentRuntime.map(String.init),
                String(category.agentAssociated), String(category.categoryDetailsRetained),
            ].compactMap { $0 }.joined(separator: "|")
    case .session(let provider, let session, let root):
        return "g" + field(provider) + field(session) + field(root ?? "")
    case .provider(let parent, let name): return identity(parent) + "p" + field(name)
    case .executable(let parent, let name, let cwd):
        return identity(parent) + "e" + field(name) + (cwd.map { "d" + field($0) } ?? "u")
    case .more(let parent): return identity(parent) + "m"
    case .process(let parent, let process):
        return identity(parent) + "i\(process.pid):\(process.startMicroseconds)"
    }
}

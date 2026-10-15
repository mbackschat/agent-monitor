import AgentMonitorCore

public enum ReportSort: String, CaseIterable, Sendable {
    case stable = "Stable order"
    case cpu = "CPU"
    case memory = "Footprint"
    case pid = "PID"
}

public enum ThresholdAdjustment: Sendable { case cpuDown, cpuUp, memoryDown, memoryUp }

public enum DetailsPaneMode: Sendable { case minimized, split, maximized }

public enum IntervalAdjustment: Sendable { case faster, slower }

public struct LiveReportState: Equatable, Sendable {
    public var actionPanel: ActionPanel?
    mutating func setActionNotice(_ text: String) { notice = text }

    public var historyMetric: HistoryMetric = .cpu
    public var historyWindow: HistoryWindow = .tenMinutes
    private var collectedHistory = ReportHistory()
    private var pausedHistory: ReportHistory?
    public var history: ReportHistory { pausedHistory ?? collectedHistory }

    public mutating func recordHistory(_ snapshot: MonitoringSnapshot) {
        collectedHistory.receive(snapshot)
    }

    public private(set) var pins: [ReportPin] = []
    public private(set) var snapshot: MonitoringSnapshot?
    public private(set) var sortKey: ReportSort = .stable
    public private(set) var ascending = false
    public private(set) var selection: LiveReportRowID?
    public private(set) var grouping: ReportGrouping
    public private(set) var openGroups: Set<SessionGroupID> = []
    public var selected: ProcessIdentity? {
        if case .process(let identity) = selection { return identity }
        return nil
    }
    public var selectedGroup: SessionGroupID? {
        if case .group(let id) = selection { return id }
        return nil
    }
    public private(set) var expanded: ProcessIdentity?
    public private(set) var notice: String?
    public private(set) var detailOffset = 0
    public private(set) var detailsMode: DetailsPaneMode = .minimized
    public private(set) var detailsPercent = 50
    public private(set) var updates = 0

    public private(set) var thresholds: Thresholds
    /// Requested seconds between samples; the session reads it live.
    public private(set) var interval: Double
    /// A frozen view keeps its snapshot while sampling continues; the latest one waits here.
    public private(set) var frozen = false
    private var heldSnapshot: MonitoringSnapshot?
    private var stableProcessRanks: [ProcessIdentity: Int] = [:]
    private var stableGroupRanks: [SessionGroupID: Int] = [:]

    /// Each sample walks every process, so the TUI does not step below 0.5 s; an explicit faster
    /// `--interval` is kept until the user slows down.
    public static let intervalSteps: [Double] = [0.5, 1, 2, 5, 10, 30, 60]

    public init(grouping: ReportGrouping = .none, thresholds: Thresholds = Thresholds(), interval: Double = 1)
    {
        self.grouping = grouping
        self.thresholds = thresholds
        self.interval = interval
    }

    public mutating func adjustInterval(_ adjustment: IntervalAdjustment) {
        switch adjustment {
        case .faster: interval = Self.intervalSteps.last { $0 < interval } ?? interval
        case .slower: interval = Self.intervalSteps.first { $0 > interval } ?? interval
        }
    }

    public mutating func setInterval(_ seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        interval = seconds
    }

    public mutating func setThresholds(_ value: Thresholds) {
        guard value.cpuPercent.isFinite, value.cpuPercent >= 0 else { return }
        thresholds = value
    }

    public mutating func toggleFreeze() {
        pausedHistory = frozen ? nil : collectedHistory
        frozen.toggle()
        if !frozen, let held = heldSnapshot {
            heldSnapshot = nil
            receive(held)
        }
    }

    public mutating func adjustThreshold(_ adjustment: ThresholdAdjustment) {
        let cpu = thresholds.cpuPercent
        let memory = thresholds.memoryBytes
        let gigabyte: UInt64 = 1_000_000_000
        switch adjustment {
        case .cpuDown: thresholds = Thresholds(cpuPercent: max(0, cpu - 10), memoryBytes: memory)
        case .cpuUp: thresholds = Thresholds(cpuPercent: cpu + 10, memoryBytes: memory)
        case .memoryDown:
            thresholds = Thresholds(cpuPercent: cpu, memoryBytes: memory - min(memory, gigabyte))
        case .memoryUp:
            thresholds = Thresholds(cpuPercent: cpu, memoryBytes: memory + min(UInt64.max - memory, gigabyte))
        }
    }

    public var groups: [SessionGroup] {
        SessionGrouping.groups(rows).sorted { left, right in
            switch sortKey {
            case .stable:
                let leftRank = stableGroupRanks[left.id] ?? Int.max
                let rightRank = stableGroupRanks[right.id] ?? Int.max
                if leftRank != rightRank { return leftRank < rightRank }
                if left.cpuTotal != right.cpuTotal { return compare(left.cpuTotal, right.cpuTotal) }
            case .cpu:
                if left.cpuTotal != right.cpuTotal { return compare(left.cpuTotal, right.cpuTotal) }
            case .memory:
                if left.memoryGBTotal != right.memoryGBTotal {
                    return compare(left.memoryGBTotal, right.memoryGBTotal)
                }
            case .pid:
                return ascending ? left.minimumPID < right.minimumPID : left.minimumPID > right.minimumPID
            }
            return left.minimumPID < right.minimumPID
        }
    }

    public var visibleRows: [LiveReportRow] {
        let projection = projection
        return (projection.pinnedRows + projection.unpinnedRows).flatMap { row in
            switch row {
            case .group(let group):
                return [row]
                    + (openGroups.contains(group.id) ? children(of: group).map(LiveReportRow.process) : [])
            case .process, .unavailable: return [row]
            }
        }
    }

    public mutating func togglePin(_ id: LiveReportRowID) {
        guard actionPanel == nil else { return }
        if let index = pins.firstIndex(where: { $0.id == id }) {
            pins.remove(at: index)
        } else {
            let label: String
            switch id {
            case .process(let identity):
                guard let row = rows.first(where: { $0.process == identity }) else { return }
                label = "\(row.name) · PID \(identity.pid)"
            case .group(let identity):
                guard let group = groups.first(where: { $0.id == identity }) else { return }
                label =
                    "\(group.project) · \(group.provider?.rawValue ?? "unknown")/\(group.sessionID ?? "unresolved")"
            }
            pins.append(ReportPin(id: id, label: label))
        }
        if !visibleRows.contains(where: { $0.id == selection }) {
            selection = visibleRows.first?.id
            expanded = nil
        }
    }

    public mutating func toggleSelectedPin() {
        if let selection { togglePin(selection) }
    }

    public mutating func resetCollection() {
        var fresh = LiveReportState(grouping: grouping, thresholds: thresholds, interval: interval)
        fresh.collectedHistory = collectedHistory
        fresh.historyMetric = historyMetric
        fresh.historyWindow = historyWindow
        fresh.pins = pins
        fresh.sortKey = sortKey
        fresh.ascending = ascending
        fresh.stableProcessRanks = stableProcessRanks
        fresh.stableGroupRanks = stableGroupRanks
        self = fresh
    }

    public var rows: [HeavyProcess] {
        (snapshot?.findings ?? []).sorted { left, right in
            switch sortKey {
            case .stable:
                let leftRank = stableProcessRanks[left.process] ?? Int.max
                let rightRank = stableProcessRanks[right.process] ?? Int.max
                if leftRank != rightRank { return leftRank < rightRank }
                if left.cpuPercent != right.cpuPercent { return compare(left.cpuPercent, right.cpuPercent) }
            case .cpu:
                if left.cpuPercent != right.cpuPercent {
                    return compare(left.cpuPercent, right.cpuPercent)
                }
            case .memory:
                if left.footprintBytes != right.footprintBytes {
                    return compare(left.footprintBytes, right.footprintBytes)
                }
            case .pid:
                if left.process.pid != right.process.pid {
                    return ascending
                        ? left.process.pid < right.process.pid : left.process.pid > right.process.pid
                }
            }
            if left.process.pid != right.process.pid { return left.process.pid < right.process.pid }
            return left.process.startMicroseconds < right.process.startMicroseconds
        }
    }

    public mutating func receive(_ snapshot: MonitoringSnapshot) {
        recordHistory(snapshot)
        guard !frozen else {
            heldSnapshot = snapshot
            return
        }
        self.snapshot = snapshot
        if sortKey == .stable { rememberOrder() }
        updates += 1
        if let selected, !snapshot.findings.contains(where: { $0.process == selected }) {
            notice = "PID \(selected.pid) left the heavy findings; details cleared."
            if !isPinned(.process(selected)) { selection = nil }
            expanded = nil
            detailOffset = 0
        }
        openGroups.formIntersection(
            Set(groups.map(\.id)).union(
                pins.compactMap {
                    if case .group(let id) = $0.id { return id }
                    return nil
                }))
        if let selected, grouping == .session,
            let group = groups.first(where: { $0.processes.contains { $0.process == selected } })
        {
            openGroups.insert(group.id)
        }
        if !visibleRows.contains(where: { $0.id == selection }) {
            selection = visibleRows.first?.id
            expanded = nil
            detailOffset = 0
        }
    }

    public mutating func sort(by key: ReportSort) {
        if key == .stable, sortKey != .stable { rememberOrder() }
        sortKey = key
        ascending = key == .pid
    }

    public mutating func reverseSort() {
        guard sortKey != .stable else { return }
        ascending.toggle()
    }

    private mutating func rememberOrder() {
        let processes = rows.map(\.process)
        let sessions = groups.map(\.id)
        stableProcessRanks = Dictionary(
            processes.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        stableGroupRanks = Dictionary(
            sessions.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
    }

    public var sortDescription: String {
        sortKey == .stable
            ? sortKey.rawValue : "\(sortKey.rawValue) \(ascending ? "ascending" : "descending")"
    }

    public mutating func moveSelection(by delta: Int) {
        let ordered = visibleRows
        guard !ordered.isEmpty else { return }
        let index = ordered.firstIndex { $0.id == selection } ?? 0
        select(ordered[min(max(index + delta, 0), ordered.count - 1)].id)
    }

    public mutating func select(_ id: LiveReportRowID) {
        guard visibleRows.contains(where: { $0.id == id }) else { return }
        selection = id
        if expanded != nil || detailsMode != .minimized { expanded = selected }
        detailOffset = 0
        notice = nil
    }

    public mutating func toggleDisclosure() {
        if let group = selectedGroup {
            if !openGroups.insert(group).inserted { openGroups.remove(group) }
            expanded = nil
            detailOffset = 0
            return
        }
        if detailsMode != .minimized, expanded == selected {
            expanded = nil
            minimizeDetails()
        } else {
            restoreDetails()
        }
        detailOffset = 0
    }

    public mutating func toggleGrouping() {
        let pinnedSelection = selection.flatMap { isPinned($0) ? $0 : nil }
        switch grouping {
        case .none:
            let process = selected
            grouping = .session
            selection =
                groups.first(where: { group in group.processes.contains { $0.process == process } })
                .map { .group($0.id) } ?? visibleRows.first?.id
        case .session:
            let process =
                selected ?? groups.first(where: { $0.id == selectedGroup })?.processes.first?.process
            grouping = .none
            selection = process.map { .process($0) } ?? visibleRows.first?.id
        }
        if let pinnedSelection { selection = pinnedSelection }
        expanded = nil
        detailOffset = 0
        notice = nil
    }

    public mutating func minimizeDetails() { detailsMode = .minimized }

    public mutating func maximizeDetails() {
        expanded = selected
        detailsMode = .maximized
    }

    public mutating func restoreDetails() {
        expanded = selected
        detailsMode = .split
    }

    public mutating func adjustDetails(by percentagePoints: Int) {
        detailsPercent = min(90, max(10, detailsPercent + percentagePoints))
        restoreDetails()
    }

    public mutating func scrollDetails(by delta: Int, maximum: Int) {
        let limit = max(0, maximum)
        detailOffset = min(limit, max(0, min(detailOffset, limit) + delta))
    }

    private func compare<T: Comparable>(_ left: T?, _ right: T?) -> Bool {
        switch (left, right) {
        case (nil, _): false
        case (_, nil): true
        case (.some(let left), .some(let right)): ascending ? left < right : left > right
        }
    }
}

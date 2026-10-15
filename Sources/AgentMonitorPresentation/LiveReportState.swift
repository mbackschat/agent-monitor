import AgentMonitorCore

public enum ReportSort: String, CaseIterable, Sendable {
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

    public private(set) var snapshot: MonitoringSnapshot?
    public private(set) var sortKey: ReportSort = .cpu
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

    /// Each sample walks every process, so the TUI does not step below 0.5 s; an explicit faster
    /// `--interval` is kept until the user slows down.
    static let intervalSteps: [Double] = [0.5, 1, 2, 5, 10, 30, 60]

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

    public mutating func toggleFreeze() {
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
        switch grouping {
        case .none: return rows.map { .process($0) }
        case .session:
            return groups.flatMap { group in
                [.group(group)] + (openGroups.contains(group.id) ? group.processes.map { .process($0) } : [])
            }
        }
    }

    public var rows: [HeavyProcess] {
        (snapshot?.findings ?? []).sorted { left, right in
            switch sortKey {
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
        guard !frozen else {
            heldSnapshot = snapshot
            return
        }
        self.snapshot = snapshot
        updates += 1
        if let selected, !snapshot.findings.contains(where: { $0.process == selected }) {
            notice = "PID \(selected.pid) left the heavy findings; details cleared."
            selection = nil
            expanded = nil
            detailOffset = 0
        }
        openGroups.formIntersection(Set(groups.map(\.id)))
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
        sortKey = key
        ascending = key == .pid
    }

    public mutating func reverseSort() { ascending.toggle() }

    public mutating func moveSelection(by delta: Int) {
        let ordered = visibleRows
        guard !ordered.isEmpty else { return }
        let index = ordered.firstIndex { $0.id == selection } ?? 0
        selection = ordered[min(max(index + delta, 0), ordered.count - 1)].id
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

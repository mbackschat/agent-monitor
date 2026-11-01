import AgentMonitorCore

public enum ReportSort: String, CaseIterable, Sendable {
    case stable = "Stable order"
    case cpu = "CPU"
    case memory = "Footprint"
    case pid = "PID"
}

public enum ThresholdAdjustment: Sendable { case cpuDown, cpuUp, memoryDown, memoryUp }

public enum ContributorChartStyle: Sendable { case stacked, compact }

public enum DetailsPaneMode: Sendable { case minimized, split, maximized }

public enum IntervalAdjustment: Sendable { case faster, slower }

public struct LiveReportState: Equatable, Sendable {
    public static let displayIntervalSeconds = 5.0

    public private(set) var referencePage: ReportReferencePage?
    public private(set) var referenceOffset = 0

    public mutating func showReference(_ page: ReportReferencePage) {
        guard actionPanel == nil, !diagnosis.isVisible else { return }
        referencePage = page
        referenceOffset = 0
    }

    public mutating func dismissReference() {
        referencePage = nil
        referenceOffset = 0
    }

    public mutating func scrollReference(by delta: Int, width: Int, height: Int) {
        let maximum = ReportReferenceLayout.maximumOffset(state: self, width: width, height: height)
        let offset = min(referenceOffset, maximum)
        referenceOffset =
            delta > 0
            ? offset + min(delta, maximum - offset)
            : max(0, offset + max(delta, -offset))
    }

    public var displayCoverageStatus: CoverageStatus {
        if showsOverview {
            return overview.coverageStatus.addingInspection(overview.samplingCoverage?.inspection)
        }
        return (snapshot.map(CoverageStatus.init(snapshot:)) ?? CoverageStatus(notes: []))
            .addingInspection(snapshot?.window?.inspectionCoverage)
    }

    public var displaySamplingCoverage: SamplingCoverageSummary? {
        if showsOverview { return overview.samplingCoverage }
        return snapshot.map { SamplingCoverageSummary(snapshot: $0) }
    }

    public var diagnosis = DiagnosisViewState() {
        didSet {
            if diagnosis.phase != oldValue.phase { diagnosisOffset = 0 }
        }
    }
    public private(set) var diagnosisOffset = 0

    public mutating func scrollDiagnosis(by delta: Int, width: Int, height: Int) {
        diagnosisOffset = min(
            diagnosis.maximumOffset(width: width, height: height), max(0, diagnosisOffset + delta))
    }

    public var actionPanel: ActionPanel? {
        didSet {
            if actionPanel != nil { returningDetails = nil }
        }
    }
    mutating func setActionNotice(_ text: String) { notice = text }

    public var chartStyle: ContributorChartStyle = .stacked
    public var overview = ContributorOverview()
    public var commandInspection: CommandInspection?
    public var showsOverview: Bool { overview.enabled && snapshot?.recentActivity != nil }

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
    private var rememberedOpenGroups: [SessionGroupID] = []
    private var returningDetails: ProcessIdentity?
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
    var contributorTableAnchor: TableScrollAnchor<ContributorID>?
    var processTableAnchor: TableScrollAnchor<LiveReportRowID>?
    public private(set) var processFocus: ContributorOverview.Focus = .rows
    public var detailsFocused: Bool {
        showsOverview
            ? overview.detailsVisible && overview.focus == .details
            : detailsMode != .minimized && processFocus == .details
    }

    public mutating func togglePaneFocus() {
        if showsOverview {
            overview.toggleFocus()
        } else if detailsMode != .minimized {
            processFocus = processFocus == .rows ? .details : .rows
        }
    }

    public private(set) var updates = 0

    public private(set) var thresholds: Thresholds
    public private(set) var samplingSettings: SamplingSettings
    public var interval: Double { samplingSettings.visibleMaximum }
    /// A frozen view keeps its snapshot while sampling continues; the latest one waits here.
    public private(set) var frozen = false
    private var heldSnapshot: MonitoringSnapshot?
    private var stableProcessRanks: [ProcessIdentity: Int] = [:]
    private var stableGroupRanks: [SessionGroupID: Int] = [:]

    public static let intervalSteps: [Double] = [0.1, 0.25, 0.5, 1, 2, 5, 10, 30, 60]

    public init(
        grouping: ReportGrouping = .none, thresholds: Thresholds = Thresholds(), interval: Double = 1,
        sampling: SamplingSettings? = nil, cpuTopology: ProcessorTopology? = nil
    ) {
        overview = ContributorOverview(topology: cpuTopology)
        self.grouping = grouping
        self.thresholds = thresholds
        samplingSettings = sampling ?? SamplingSettings(visibleMaximum: interval)
    }

    public mutating func inspectOverviewProcess() {
        guard showsOverview, !overview.selectionIsFolded, let id = overview.selection,
            let identity = overview.nodes[id]?.process,
            snapshot?.findings.contains(where: { $0.process == identity && !$0.isHistorical }) == true
        else { return }
        overview.enabled = false
        if let group = groups.first(where: { $0.processes.contains { $0.process == identity } }) {
            setGroupDisclosure(group.id, expanded: true)
        }
        select(.process(identity))
        setDisclosure(expanded: true)
    }

    public mutating func adjustInterval(_ adjustment: IntervalAdjustment) {
        let validSteps = Self.intervalSteps.filter { seconds in
            var settings = samplingSettings
            settings.visibleMaximum = seconds
            return settings.isValid
        }
        switch adjustment {
        case .faster: setInterval(validSteps.last { $0 < interval } ?? interval)
        case .slower: setInterval(validSteps.first { $0 > interval } ?? interval)
        }
    }

    public mutating func setInterval(_ seconds: Double) {
        var settings = samplingSettings
        settings.visibleMaximum = seconds
        setSamplingSettings(settings)
    }

    @discardableResult public mutating func setSamplingSettings(_ settings: SamplingSettings) -> Bool {
        guard settings.isValid else { return false }
        samplingSettings = settings
        return true
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

    public var groups: [SessionGroup] { groups(from: rows) }

    /// Takes the already-sorted `rows` so callers holding them avoid a second full sort.
    func groups(from displayed: [HeavyProcess]) -> [SessionGroup] {
        let identities = Set(displayed.map(\.process))
        let hidden = (snapshot?.observedFindings ?? []).filter { !identities.contains($0.process) }
        return SessionGrouping.groups(displayed + hidden, window: snapshot?.window).sorted { left, right in
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
        visibleRows(in: projection)
    }

    func visibleRows(in projection: ReportProjection) -> [LiveReportRow] {
        return (projection.pinnedRows + projection.unpinnedRows).flatMap { row in
            switch row {
            case .group(let group):
                return [row]
                    + (openGroups.contains(group.id)
                        ? (projection.childrenByGroup[group.id] ?? []).map(LiveReportRow.process) : [])
            case .process, .unavailable: return [row]
            }
        }
    }

    @discardableResult public mutating func togglePin(_ id: LiveReportRowID) -> Bool {
        guard actionPanel == nil else { return false }
        if let index = pins.firstIndex(where: { $0.id == id }) {
            pins.remove(at: index)
        } else {
            let label: String
            switch id {
            case .process(let identity):
                guard let row = rows.first(where: { $0.process == identity }) else { return false }
                label = "\(row.observedName) · PID \(identity.pid)"
            case .group(let identity):
                guard let group = groups.first(where: { $0.id == identity }) else { return false }
                label =
                    "\(group.project) · \(group.provider?.rawValue ?? "unknown")/\(group.sessionID ?? "unresolved")"
            }
            let pin = ReportPin(id: id, label: label)
            guard
                PinLimits.admits(
                    count: pins.count, bytes: pins.reduce(0) { $0 + $1.textBytes }, adding: pin.textBytes)
            else {
                notice = PinLimits.refusal
                return false
            }
            pins.append(pin)
        }
        notice = nil
        let visible = visibleRows
        if !visible.contains(where: { $0.id == selection }) {
            selection = visible.first?.id
            expanded = nil
        }
        return true
    }

    public mutating func toggleSelectedPin() {
        if showsOverview {
            overview.togglePin()
            return
        }
        if let selection { togglePin(selection) }
    }

    public var hasPins: Bool { !pins.isEmpty || !overview.pinned.isEmpty }

    public mutating func unpinAll() {
        guard actionPanel == nil else { return }
        pins.removeAll()
        overview.unpinAll()
        notice = nil
        let visible = visibleRows
        if !visible.contains(where: { $0.id == selection }) {
            selection = visible.first?.id
            expanded = nil
        }
    }

    public mutating func resetCollection() {
        var fresh = LiveReportState(grouping: grouping, thresholds: thresholds, sampling: samplingSettings)
        fresh.overview = overview
        fresh.overview.resetInspection()
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
        if frozen, let previous = self.snapshot?.recentActivity,
            let next = snapshot.recentActivity,
            previous.runID != next.runID || previous.scope != next.scope
        {
            frozen = false
            heldSnapshot = nil
            pausedHistory = nil
        }
        guard !frozen else {
            heldSnapshot = snapshot
            return
        }
        self.snapshot = snapshot
        overview.receive(snapshot)
        if overview.inspectedProcess != nil, contributorProcessTarget == nil {
            overview.showContributorSummary()
        }
        if sortKey == .stable { rememberOrder() }
        updates += 1
        if let selected, !snapshot.findings.contains(where: { $0.process == selected }) {
            if expanded == selected, detailsMode != .minimized { returningDetails = selected }
            notice = "PID \(selected.pid) left the displayed findings; details cleared."
            if !isPinned(.process(selected)) { selection = nil }
            expanded = nil
            detailOffset = 0
        }
        reconcileOpenGroups()
        if let returning = returningDetails {
            if snapshot.findings.contains(where: { $0.process == returning }), actionPanel == nil {
                selection = .process(returning)
                expanded = returning
                returningDetails = nil
                notice = nil
            } else if snapshot.findings.contains(where: { $0.process.pid == returning.pid }) {
                returningDetails = nil
            }
        }
        if let selected, grouping == .session,
            let group = groups.first(where: { $0.processes.contains { $0.process == selected } })
        {
            rememberOpenGroup(group.id)
        }
        let visible = visibleRows
        if !visible.contains(where: { $0.id == selection }) {
            selection = visible.first?.id
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
        let displayed = rows
        let processes = displayed.map(\.process)
        let sessions = groups(from: displayed).map(\.id)
        stableProcessRanks = Dictionary(
            processes.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        stableGroupRanks = Dictionary(
            sessions.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
    }

    public mutating func moveSelection(by delta: Int) {
        if showsOverview {
            overview.move(by: delta)
            return
        }
        let ordered = visibleRows
        guard !ordered.isEmpty else { return }
        let index = ordered.firstIndex { $0.id == selection } ?? 0
        select(ordered[min(max(index + delta, 0), ordered.count - 1)].id)
    }

    public mutating func select(_ id: LiveReportRowID) {
        guard visibleRows.contains(where: { $0.id == id }) else { return }
        returningDetails = nil
        selection = id
        if expanded != nil || detailsMode != .minimized { expanded = selected }
        detailOffset = 0
        notice = nil
    }

    public mutating func setChildDisclosure(expanded: Bool) {
        guard showsOverview || selectedGroup != nil else { return }
        setDisclosure(expanded: expanded)
    }

    public mutating func showDetails() {
        if showsOverview {
            if !overview.detailsVisible { overview.toggleDetails() }
        } else if detailsMode == .minimized {
            toggleDetails()
        }
    }

    public mutating func toggleDetails() {
        if showsOverview {
            overview.toggleDetails()
            if !overview.detailsVisible { detailsMode = .minimized }
            return
        }
        returningDetails = nil
        if detailsMode != .minimized {
            expanded = nil
            minimizeDetails()
        } else {
            guard selected != nil || selectedGroup != nil else { return }
            restoreDetails()
        }
        detailOffset = 0
    }

    public mutating func setDisclosure(expanded: Bool) {
        if showsOverview {
            overview.disclose(expanded)
            return
        }
        returningDetails = nil
        let isExpanded: Bool
        if let group = selectedGroup {
            isExpanded = openGroups.contains(group)
        } else {
            guard selected != nil else { return }
            isExpanded = detailsMode != .minimized && self.expanded == selected
        }
        if isExpanded != expanded { toggleDisclosure() }
    }

    @discardableResult
    public mutating func setSessionDisclosure(
        expanded: Bool, from row: LiveReportRowID?, flattenSingletons: Bool = false
    ) -> Bool {
        guard actionPanel == nil else { return false }
        let projection = projection
        let topLevel = projection.pinnedRows + projection.unpinnedRows
        let groups = topLevel.compactMap { row -> SessionGroup? in
            if case .group(let group) = row { return group }
            return nil
        }
        func flattened(_ group: SessionGroup) -> Bool {
            flattenSingletons && group.canFlatten && !children(of: group).isEmpty
                && !isPinned(.group(group.id))
        }
        var targets = groups.filter { !flattened($0) }
        if let row, !topLevel.contains(where: { $0.id == row }) {
            guard case .process(let process) = row,
                let parent = groups.first(where: { children(of: $0).contains { $0.process == process } }),
                openGroups.contains(parent.id) || flattened(parent)
            else { return false }
            if !flattened(parent) { targets = [parent] }
        }
        guard !targets.isEmpty else { return false }
        returningDetails = nil
        for group in targets { setGroupDisclosure(group.id, expanded: expanded) }
        if !expanded {
            let hidden = targets.flatMap { children(of: $0).map(\.process) }
            let hiddenSelection = [row, selection].compactMap { value -> ProcessIdentity? in
                guard case .process(let process) = value, hidden.contains(process) else { return nil }
                return process
            }.first
            if let process = hiddenSelection,
                let parent = targets.first(where: { $0.processes.contains { $0.process == process } })
            {
                selection =
                    row.flatMap { candidate in
                        visibleRows.contains { $0.id == candidate } ? candidate : nil
                    } ?? .group(parent.id)
                detailOffset = 0
            }
            if let inspected = self.expanded, hidden.contains(inspected) { self.expanded = nil }
        }
        return true
    }

    public mutating func toggleDisclosure() {
        returningDetails = nil
        if let group = selectedGroup {
            setGroupDisclosure(group, expanded: !openGroups.contains(group))
            expanded = nil
            detailOffset = 0
            return
        }
        toggleDetails()
    }

    public mutating func toggleGrouping() {
        returningDetails = nil
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

    public mutating func minimizeDetails() {
        returningDetails = nil
        detailsMode = .minimized
        processFocus = .rows
    }

    public mutating func maximizeDetails() {
        if showsOverview { showDetails() }
        returningDetails = nil
        expanded = selected
        detailsMode = .maximized
        processFocus = .details
    }

    public mutating func restoreDetails() {
        if showsOverview { showDetails() }
        returningDetails = nil
        expanded = selected
        detailsMode = .split
        processFocus = .details
    }

    public mutating func adjustDetails(by percentagePoints: Int) {
        detailsPercent = min(90, max(10, detailsPercent + percentagePoints))
        restoreDetails()
    }

    public mutating func scrollDetails(by delta: Int, maximum: Int) {
        let limit = max(0, maximum)
        detailOffset = min(limit, max(0, min(detailOffset, limit) + delta))
    }

    private mutating func setGroupDisclosure(_ id: SessionGroupID, expanded: Bool) {
        if expanded {
            rememberOpenGroup(id)
        } else {
            openGroups.remove(id)
            rememberedOpenGroups.removeAll { $0 == id }
        }
    }

    private mutating func rememberOpenGroup(_ id: SessionGroupID) {
        if openGroups.insert(id).inserted {
            rememberedOpenGroups.removeAll { $0 == id }
            rememberedOpenGroups.append(id)
        }
    }

    private mutating func reconcileOpenGroups() {
        let available = Set(groups.map(\.id)).union(
            pins.compactMap {
                if case .group(let id) = $0.id { return id }
                return nil
            })
        // A missing observation cannot establish that a session ended; see docs/architecture.md.
        // Bound absent identities without evicting visible expansion (docs/architecture.md).
        var remainingAbsent = 256
        rememberedOpenGroups = rememberedOpenGroups.reversed().filter { id in
            if available.contains(id) { return true }
            guard remainingAbsent > 0 else { return false }
            remainingAbsent -= 1
            return true
        }.reversed()
        openGroups = Set(rememberedOpenGroups).intersection(available)
    }

    private func compare<T: Comparable>(_ left: T?, _ right: T?) -> Bool {
        switch (left, right) {
        case (nil, _): false
        case (_, nil): true
        case (.some(let left), .some(let right)): ascending ? left < right : left > right
        }
    }
}

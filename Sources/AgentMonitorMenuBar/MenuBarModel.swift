import AgentMonitorActions
import AgentMonitorCore
import AgentMonitorPresentation
import Foundation
import Observation

/// Live display thresholds, acquisition interval and snapshot consumer.
typealias MenuBarSource =
    @Sendable (
        @escaping @Sendable () async -> Thresholds, LiveInterval,
        @escaping @Sendable (MonitoringSnapshot) async throws -> Void
    ) async throws -> Void

@MainActor @Observable
final class MenuBarModel {
    var report = LiveReportState(grouping: .session, interval: 0.1) {
        didSet {
            if oldValue.samplingSettings != report.samplingSettings {
                liveInterval.setSettings(report.samplingSettings)
            }
            commands.reconcile(with: report)
            if MenuBarRowIndex.needsUpdate(from: oldValue, to: report) {
                rowIndex = MenuBarRowIndex(state: report)
            }
        }
    }
    private(set) var rowIndex = MenuBarRowIndex(state: LiveReportState(grouping: .session))
    let diagnosis: CPUDiagnosisController
    let commands = CommandInspectionController()
    var panelSize: MenuBarPanelSize = .standard {
        didSet {
            customPanelHeight = nil
            onPanelSizeChange?()
        }
    }
    private(set) var customPanelHeight: CGFloat?
    var panelHeight: CGFloat { customPanelHeight ?? panelSize.height }
    var isSummaryOnly: Bool {
        report.showsOverview && report.overview.tableCollapsed
            && !diagnosis.state.isVisible && report.actionPanel == nil
    }
    @ObservationIgnored var onPanelSizeChange: (() -> Void)?

    func rememberPanelHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        customPanelHeight = abs(height - panelSize.height) < 1 ? nil : height
    }
    var referencePage: MenuBarReferencePage? {
        didSet { if referencePage != .glossary { glossaryTopic = nil } }
    }
    private(set) var glossaryTopic: String?

    func showGlossary(_ entry: ReportGlossary.Entry? = nil) {
        referencePage = .glossary
        glossaryTopic = entry?.id
    }

    private(set) var arrivals = MenuBarArrivals()
    @ObservationIgnored private var arrivalExpiry: Task<Void, Never>?
    @ObservationIgnored private var arrivalDeadline: ContinuousClock.Instant?
    private(set) var isOpen = false
    private(set) var error: String?
    private(set) var lastActionResult: ActionResult?
    private(set) var diagnosisCopyStatus: String?
    private(set) var liveIcon = true
    private(set) var isPerformingAction = false
    private(set) var indicator = MenuBarIndicator()
    @ObservationIgnored var onIndicatorChange: (() -> Void)?
    @ObservationIgnored private let liveInterval = LiveInterval(settings: SamplingSettings())
    @ObservationIgnored private(set) var collection: Task<Void, Never>?
    @ObservationIgnored private(set) var action: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var collectionGeneration = UUID()
    @ObservationIgnored private var restartCollectionAfterDrain = false
    @ObservationIgnored private var latestSnapshot: MonitoringSnapshot?
    @ObservationIgnored private let source: MenuBarSource
    @ObservationIgnored private let actions: any ProcessActions

    init(
        cpuTopology: ProcessorTopology? = nil,
        actions: any ProcessActions = SessionActions.local(),
        diagnosisSource: @escaping CPUDiagnosisSource = CPUDiagnosisSession.collectLocal,
        source: @escaping MenuBarSource
    ) {
        diagnosis = CPUDiagnosisController(source: diagnosisSource)
        self.actions = actions
        self.source = source
        report = LiveReportState(grouping: .session, interval: 0.1, cpuTopology: cpuTopology)
        diagnosis.onChange = { [weak self] _ in self?.diagnosisCopyStatus = nil }
    }

    @discardableResult func beginDiagnosis() -> Bool {
        guard isOpen, report.actionPanel == nil else { return false }
        return diagnosis.start()
    }

    @discardableResult
    func copyDiagnosisReport(using write: @MainActor (String) -> Bool = MenuBarClipboard.copy) -> Bool {
        guard isOpen, let text = diagnosis.state.reportText else { return false }
        let copied = write(text)
        diagnosisCopyStatus = copied ? "Copied" : "Copy failed"
        return copied
    }

    func start() {
        if liveIcon { startCollection() }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        liveInterval.setPanelVisible(true)
        generation = UUID()
        report.resetCollection()
        if let latestSnapshot { report.receive(latestSnapshot) }
        updateArrivals()
        refreshIndicator()
        startCollection()
    }

    func setLiveIcon(_ enabled: Bool) {
        guard liveIcon != enabled else { return }
        liveIcon = enabled
        indicator = MenuBarIndicator()
        if enabled || isOpen { startCollection() } else { cancelCollection() }
        refreshIndicator()
        onIndicatorChange?()
    }

    private func startCollection() {
        liveInterval.setSettings(report.samplingSettings)
        liveInterval.setPanelVisible(isOpen)
        if let collection {
            if collection.isCancelled { restartCollectionAfterDrain = true }
            return
        }
        error = nil
        let previousAction = action
        let token = UUID()
        collectionGeneration = token
        collection = Task { [self] in
            defer {
                collection = nil
                if restartCollectionAfterDrain {
                    restartCollectionAfterDrain = false
                    startCollection()
                }
            }
            await previousAction?.value
            do {
                try Task.checkCancellation()
                try await source(
                    { [weak self] in await self?.report.thresholds ?? Thresholds() }, liveInterval
                ) { [weak self] snapshot in
                    try Task.checkCancellation()
                    await self?.receive(snapshot, generation: token)
                }
            } catch is CancellationError {
                return
            } catch {
                guard collectionGeneration == token else { return }
                self.error = error.localizedDescription
                indicator.fail()
                latestSnapshot = nil
                onIndicatorChange?()
            }
        }
    }

    func toggleFreeze() {
        guard isOpen, !diagnosis.state.isVisible, report.snapshot != nil, report.actionPanel == nil else {
            return
        }
        report.toggleFreeze()
        updateArrivals()
        refreshIndicator()
    }

    func close() {
        referencePage = nil
        commands.dismiss()
        diagnosis.dismiss()
        isOpen = false
        liveInterval.setPanelVisible(false)
        generation = UUID()
        if !liveIcon { cancelCollection() }
        action?.cancel()
        report.resetCollection()
        updateArrivals()
        refreshIndicator()
    }

    func stop() async {
        close()
        cancelCollection()
        await collection?.value
        await action?.value
        await diagnosis.stop()
        await commands.wait()
        collection = nil
        action = nil
    }

    func waitForCollection() async {
        while let current = collection { await current.value }
    }
    func waitForAction() async { await action?.value }

    private func cancelCollection() {
        restartCollectionAfterDrain = false
        collectionGeneration = UUID()
        collection?.cancel()
        latestSnapshot = nil
        indicator = MenuBarIndicator()
        onIndicatorChange?()
    }

    private func receive(_ snapshot: MonitoringSnapshot, generation token: UUID) {
        guard collectionGeneration == token else { return }
        latestSnapshot = snapshot
        if isOpen {
            report.receive(snapshot)
            updateArrivals()
        } else {
            report.recordHistory(snapshot)
        }
        refreshIndicator()
    }

    var observedProcessCount: Int? {
        report.snapshot.map { Set($0.observedFindings.map(\.process)).count }
    }

    private func refreshIndicator() {
        guard liveIcon, let snapshot = isOpen ? report.snapshot : latestSnapshot else { return }
        indicator.receive(snapshot, paused: isOpen && report.frozen)
        onIndicatorChange?()
    }

    private func updateArrivals() {
        arrivals.update(report.snapshot, now: .now)
        scheduleArrivalExpiry()
    }

    private func scheduleArrivalExpiry() {
        let next = arrivals.deadlines.values.min()
        guard next != arrivalDeadline else { return }
        arrivalExpiry?.cancel()
        arrivalDeadline = next
        guard let next else {
            arrivalExpiry = nil
            return
        }
        arrivalExpiry = Task { [weak self] in
            do { try await ContinuousClock().sleep(until: next) } catch { return }
            guard let self, !Task.isCancelled else { return }
            arrivalDeadline = nil
            arrivals.expire(at: .now)
            scheduleArrivalExpiry()
        }
    }

    func canBegin(_ kind: ProcessActionKind, row: LiveReportRowID) -> Bool {
        guard isOpen, !isPerformingAction, !diagnosis.state.isVisible, report.actionPanel == nil,
            rowIndex.visible.contains(row)
        else { return false }
        switch row {
        case .group(let id):
            guard case .focus = kind,
                let process = rowIndex.groupFocusTargets[id]
            else { return false }
            return SessionActions.canFocusTerminal(process)
        case .process(let id):
            guard let process = rowIndex.processes[id], !process.isHistorical else { return false }
            switch kind {
            case .terminate: return true
            case .focus: return SessionActions.canFocusTerminal(process)
            case .message: return false
            }
        }
    }

    func begin(_ kind: ProcessActionKind, row: LiveReportRowID) {
        guard isOpen, !isPerformingAction, !diagnosis.state.isVisible, report.actionPanel == nil else {
            return
        }
        guard canBegin(kind, row: row) else { return }
        selectRow(row)
        guard report.selection == row else { return }
        perform(report.beginAction(kind))
    }

    func adjustInterval(_ adjustment: IntervalAdjustment) {
        report.adjustInterval(adjustment)
    }

    func setInterval(_ seconds: Double) {
        report.setInterval(seconds)
    }

    @discardableResult func togglePin(_ row: LiveReportRowID) -> Bool {
        guard isOpen, !diagnosis.state.isVisible, report.actionPanel == nil, rowIndex.visible.contains(row)
        else { return false }
        return report.togglePin(row)
    }

    func unpinAll() {
        guard !diagnosis.state.isVisible, report.actionPanel == nil else { return }
        report.unpinAll()
    }

    func selectRow(_ row: LiveReportRowID) {
        guard rowIndex.visible.contains(row) else { return }
        if !report.visibleRows.contains(where: { $0.id == row }),
            case .process(let identity) = row,
            let group = report.groups.first(where: { $0.processes.contains { $0.process == identity } })
        {
            report.select(.group(group.id))
            guard report.selectedGroup == group.id else { return }
            if !report.openGroups.contains(group.id) { report.toggleDisclosure() }
        }
        report.select(row)
    }

    func setDetails(for process: ProcessIdentity, expanded: Bool) {
        selectRow(.process(process))
        guard report.selected == process else { return }
        report.setDisclosure(expanded: expanded)
    }

    var visibleRowIDs: [LiveReportRowID] { rowIndex.visibleIDs }

    func moveFocus(from row: LiveReportRowID?, by delta: Int) -> LiveReportRowID? {
        let rows = visibleRowIDs
        guard !rows.isEmpty else { return nil }
        let next: LiveReportRowID
        switch row.flatMap({ rows.firstIndex(of: $0) }) {
        case .some(let index): next = rows[min(max(index + delta, 0), rows.count - 1)]
        case nil: next = rows[0]
        }
        selectRow(next)
        return next
    }

    func input(_ input: ActionInput) {
        guard isOpen else { return }
        perform(report.actionInput(input))
    }

    func perform(_ effect: ActionEffect?) {
        guard let effect, !isPerformingAction else { return }
        isPerformingAction = true
        let token = generation
        action = Task {
            defer {
                action = nil
                isPerformingAction = false
            }
            lastActionResult = nil
            do {
                let result: ActionResult
                switch effect {
                case .terminate(let processes):
                    result = await TerminationExecution.perform(processes, using: actions)
                case .focus(let process):
                    try Task.checkCancellation()
                    result = .accepted(FocusWording.result(try await actions.focusTerminal(of: process)))
                }
                finish(result, generation: token)
            } catch is CancellationError {
                return
            } catch {
                finish(
                    (error as? ActionFailure)?.uncertain == true
                        ? .uncertain(error.localizedDescription) : .failed(error.localizedDescription),
                    generation: token)
            }
        }
    }

    private func finish(_ result: ActionResult, generation token: UUID) {
        lastActionResult = result
        guard isOpen, generation == token else { return }
        report.actionFinished(result)
    }
}

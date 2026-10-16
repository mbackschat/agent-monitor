import AgentMonitorActions
import AgentMonitorCore
import AgentMonitorPresentation
import Foundation
import Observation

/// Live inputs: thresholds, interval, whether session identities are shown (the panel is open),
/// and the snapshot consumer.
typealias MenuBarSource =
    @Sendable (
        @escaping @Sendable () async -> Thresholds, LiveInterval, @escaping @Sendable () async -> Bool,
        @escaping @Sendable (MonitoringSnapshot) async throws -> Void
    ) async throws -> Void

@MainActor @Observable
final class MenuBarModel {
    var report = LiveReportState(grouping: .session, interval: 5)
    var panelSize: MenuBarPanelSize = .standard
    var showsKeyboardHelp = false
    private(set) var arrivals = MenuBarArrivals()
    @ObservationIgnored private var arrivalExpiry: Task<Void, Never>?
    @ObservationIgnored private var arrivalDeadline: ContinuousClock.Instant?
    private(set) var isOpen = false
    private(set) var error: String?
    private(set) var lastActionResult: ActionResult?
    private(set) var savedMessage: SavedMessage?
    private(set) var messageCopyStatus: String?
    private(set) var liveIcon = true
    private(set) var indicator = MenuBarIndicator()
    @ObservationIgnored var onIndicatorChange: (() -> Void)?
    @ObservationIgnored private let liveInterval = LiveInterval(0.25)
    @ObservationIgnored private var needsStartupSample = true
    @ObservationIgnored private var collection: Task<Void, Never>?
    @ObservationIgnored private var action: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var collectionGeneration = UUID()
    @ObservationIgnored private var isCollecting = false
    @ObservationIgnored private var latestSnapshot: MonitoringSnapshot?
    @ObservationIgnored private let source: MenuBarSource
    @ObservationIgnored private let actions: any ProcessActions

    init(actions: any ProcessActions = SessionActions.local(), source: @escaping MenuBarSource) {
        self.actions = actions
        self.source = source
    }

    func start() {
        if liveIcon { startCollection() }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
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

    private var samplingInterval: Double {
        let regular = isOpen ? report.interval : 15
        return needsStartupSample ? min(0.25, regular) : regular
    }

    private func startCollection() {
        liveInterval.set(samplingInterval)
        guard !isCollecting else { return }
        isCollecting = true
        error = nil
        let previous = collection
        let previousAction = action
        let token = UUID()
        collectionGeneration = token
        collection = Task { [self] in
            await previous?.value
            await previousAction?.value
            defer { if collectionGeneration == token { isCollecting = false } }
            do {
                try Task.checkCancellation()
                try await source(
                    { [weak self] in await self?.report.thresholds ?? Thresholds() }, liveInterval,
                    { [weak self] in await self?.isOpen ?? false }
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
        guard isOpen, report.snapshot != nil, report.actionPanel == nil else { return }
        report.toggleFreeze()
        updateArrivals()
        refreshIndicator()
    }

    func close() {
        if let panel = report.actionPanel {
            switch panel.phase {
            case .compose, .review:
                if !panel.text.isEmpty {
                    savedMessage = SavedMessage(
                        process: panel.process, sampledAt: panel.sampledAt,
                        text: panel.text, recipientID: panel.recipient?.id)
                }
            default: break
            }
        }
        messageCopyStatus = nil
        isOpen = false
        generation = UUID()
        if liveIcon { liveInterval.set(samplingInterval) } else { cancelCollection() }
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
        collection = nil
        action = nil
    }

    func waitForCollection() async { await collection?.value }
    func waitForAction() async { await action?.value }

    private func cancelCollection() {
        collectionGeneration = UUID()
        collection?.cancel()
        isCollecting = false
        latestSnapshot = nil
        indicator = MenuBarIndicator()
        onIndicatorChange?()
    }

    private func receive(_ snapshot: MonitoringSnapshot, generation token: UUID) {
        guard collectionGeneration == token else { return }
        latestSnapshot = snapshot
        if needsStartupSample {
            needsStartupSample = false
            liveInterval.set(samplingInterval)
        }
        if isOpen {
            report.receive(snapshot)
            updateArrivals()
        } else {
            report.recordHistory(snapshot)
        }
        refreshIndicator()
    }

    var displayedProcessCount: Int? {
        report.snapshot.map { Set($0.findings.map(\.process)).count }
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
        guard isOpen, report.actionPanel == nil, visibleRowIDs.contains(row) else { return false }
        switch row {
        case .group(let id):
            guard case .focus = kind,
                let group = report.groups.first(where: { $0.id == id }),
                Set(group.processes.compactMap(\.attribution.runtime)).count == 1,
                let process = group.processes.first(where: { $0.attribution.runtime != nil })
            else { return false }
            return SessionActions.canFocusTerminal(process)
        case .process(let id):
            guard let process = report.rows.first(where: { $0.process == id }) else { return false }
            switch kind {
            case .terminate: return true
            case .focus: return SessionActions.canFocusTerminal(process)
            case .message: return savedMessage == nil && SessionActions.canMessage(process)
            }
        }
    }

    func begin(_ kind: ProcessActionKind, row: LiveReportRowID) {
        guard isOpen, report.actionPanel == nil else { return }
        if case .message = kind, let savedMessage {
            if row == .process(savedMessage.process.process) { resumeMessage() }
            return
        }
        guard canBegin(kind, row: row) else { return }
        selectRow(row)
        guard report.selection == row else { return }
        perform(report.beginAction(kind))
    }

    func adjustInterval(_ adjustment: IntervalAdjustment) {
        report.adjustInterval(adjustment)
        liveInterval.set(samplingInterval)
    }

    func setInterval(_ seconds: Double) {
        report.setInterval(seconds)
        liveInterval.set(samplingInterval)
    }

    @discardableResult func togglePin(_ row: LiveReportRowID) -> Bool {
        guard isOpen, report.actionPanel == nil, visibleRowIDs.contains(row) else { return false }
        report.togglePin(row)
        return true
    }

    func selectRow(_ row: LiveReportRowID) {
        guard visibleRowIDs.contains(row) else { return }
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

    var visibleRowIDs: [LiveReportRowID] {
        let projection = report.projection
        return (projection.pinnedRows + projection.unpinnedRows).flatMap { row in
            switch row {
            case .group(let group):
                if !report.isPinned(row.id), group.processes.count == 1, let process = group.processes.first {
                    return [LiveReportRowID.process(process.process)]
                }
                return [row.id]
                    + (report.openGroups.contains(group.id)
                        ? report.children(of: group).map { .process($0.process) } : [])
            case .process, .unavailable: return [row.id]
            }
        }
    }

    func moveFocus(from row: LiveReportRowID, by delta: Int) -> LiveReportRowID? {
        let rows = visibleRowIDs
        guard !rows.isEmpty else { return nil }
        let index = rows.firstIndex(of: row) ?? 0
        let next = rows[min(max(index + delta, 0), rows.count - 1)]
        selectRow(next)
        return next
    }

    func resumeMessage() {
        guard isOpen, report.actionPanel == nil, let savedMessage else { return }
        perform(report.beginMessage(for: savedMessage.process, sampledAt: savedMessage.sampledAt))
    }

    func discardMessage() {
        guard isOpen, report.actionPanel == nil else { return }
        savedMessage = nil
    }

    func input(_ input: ActionInput) {
        guard isOpen else { return }
        messageCopyStatus = nil
        perform(report.actionInput(input))
    }

    func setMessage(_ text: String) {
        guard report.actionPanel?.phase == .compose else { return }
        messageCopyStatus = nil
        report.actionPanel?.text = ""
        _ = report.actionInput(.text(text))
    }

    @discardableResult
    func copyMessage(using write: @MainActor (String) -> Bool = MenuBarClipboard.copy) -> Bool {
        guard isOpen, let panel = report.actionPanel, let draft = panel.draft else { return false }
        switch panel.phase {
        case .compose, .review:
            let copied = write(draft.message(panel.text))
            messageCopyStatus = copied ? "Copied" : "Copy failed"
            return copied
        default: return false
        }
    }

    private func perform(_ effect: ActionEffect?) {
        guard let effect else { return }
        let token = generation
        action = Task {
            lastActionResult = nil
            do {
                try Task.checkCancellation()
                let result: ActionResult
                switch effect {
                case .prepare(let process):
                    let draft = try await actions.prepareMessage(for: process)
                    try Task.checkCancellation()
                    guard isOpen, generation == token else { return }
                    if let saved = savedMessage {
                        guard saved.process == process,
                            let index = draft.recipients.choices.firstIndex(where: {
                                $0.id == saved.recipientID && $0.unavailableReason == nil
                            })
                        else {
                            throw ActionFailure(
                                "The original recipient is unavailable. Your draft is still saved.")
                        }
                        report.messagePrepared(draft)
                        report.actionPanel?.text = saved.text
                        report.actionPanel?.recipientIndex = index
                        savedMessage = nil
                        return
                    }
                    report.messagePrepared(draft)
                    return
                case .terminate(let process):
                    try await actions.terminate(process)
                    result = .accepted(ActionWording.terminationAccepted(pid: process.process.pid))
                case .send(let draft, let text, let recipient):
                    try await actions.send(draft, text: text, recipient: recipient)
                    result = .accepted(MessageWording.accepted(draft, recipient: recipient))
                case .focus(let process):
                    result = .accepted(FocusWording.result(try await actions.focusTerminal(of: process)))
                }
                finish(result, generation: token)
            } catch is CancellationError {
                switch effect {
                case .send, .terminate:
                    finish(
                        .uncertain("Action interrupted. Check its outcome before trying again."),
                        generation: token)
                case .prepare, .focus: break
                }
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

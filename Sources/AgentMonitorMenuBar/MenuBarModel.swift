import AgentMonitorActions
import AgentMonitorCore
import AgentMonitorPresentation
import Foundation
import Observation

typealias MenuBarSource =
    @Sendable (@escaping @Sendable (MonitoringSnapshot) async throws -> Void) async throws -> Void

@MainActor @Observable
final class MenuBarModel {
    var report = LiveReportState(grouping: .session)
    var panelSize: MenuBarPanelSize = .standard
    private(set) var isOpen = false
    private(set) var error: String?
    private(set) var lastActionResult: ActionResult?
    private(set) var savedMessage: SavedMessage?
    @ObservationIgnored private var collection: Task<Void, Never>?
    @ObservationIgnored private var action: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let source: MenuBarSource
    @ObservationIgnored private let actions: any ProcessActions

    init(actions: any ProcessActions = SessionActions.local(), source: @escaping MenuBarSource) {
        self.actions = actions
        self.source = source
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        error = nil
        let previous = collection
        let previousAction = action
        let token = UUID()
        generation = token
        report = LiveReportState(grouping: .session)
        collection = Task { [self] in
            await previous?.value
            await previousAction?.value
            do {
                try Task.checkCancellation()
                try await source { [weak self] snapshot in
                    try Task.checkCancellation()
                    await self?.receive(snapshot, generation: token)
                }
            } catch is CancellationError {
                return
            } catch {
                guard isOpen, generation == token else { return }
                self.error = error.localizedDescription
            }
        }
    }

    func toggleFreeze() {
        guard isOpen, report.snapshot != nil, report.actionPanel == nil else { return }
        report.toggleFreeze()
    }

    func close() {
        if let panel = report.actionPanel {
            switch panel.phase {
            case .compose, .review:
                if !panel.text.isEmpty {
                    savedMessage = SavedMessage(
                        process: panel.process, text: panel.text, recipientID: panel.recipient?.id)
                }
            default: break
            }
        }
        isOpen = false
        generation = UUID()
        collection?.cancel()
        action?.cancel()
        report = LiveReportState(grouping: .session)
    }

    func stop() async {
        close()
        await collection?.value
        await action?.value
        collection = nil
        action = nil
    }

    func waitForCollection() async { await collection?.value }
    func waitForAction() async { await action?.value }

    private func receive(_ snapshot: MonitoringSnapshot, generation token: UUID) {
        guard isOpen, generation == token else { return }
        report.receive(snapshot)
    }

    func begin(_ kind: ProcessActionKind, row: LiveReportRowID) {
        guard isOpen, report.actionPanel == nil else { return }
        if case .message = kind, let savedMessage {
            if row == .process(savedMessage.process.process) { resumeMessage() }
            return
        }
        if case .process(let identity) = row,
            let group = report.groups.first(where: {
                $0.processes.count == 1 && $0.processes.first?.process == identity
            }), !report.openGroups.contains(group.id)
        {
            // Singleton rows bypass group disclosure in the native view; shared action selection
            // still addresses the process inside LiveReportState's session hierarchy.
            report.select(.group(group.id))
            report.toggleDisclosure()
        }
        guard report.visibleRows.contains(where: { $0.id == row }) else { return }
        report.select(row)
        perform(report.beginAction(kind))
    }

    func resumeMessage() {
        guard isOpen, report.actionPanel == nil, let savedMessage else { return }
        perform(report.beginMessage(for: savedMessage.process))
    }

    func discardMessage() {
        guard isOpen, report.actionPanel == nil else { return }
        savedMessage = nil
    }

    func input(_ input: ActionInput) {
        guard isOpen else { return }
        perform(report.actionInput(input))
    }

    func setMessage(_ text: String) {
        guard report.actionPanel?.phase == .compose else { return }
        report.actionPanel?.text = ""
        _ = report.actionInput(.text(text))
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

import AgentMonitorActions
import AgentMonitorCore
import AgentMonitorPresentation
import Foundation
import SwiftTUICLI
import SwiftTUIRuntime

public typealias SnapshotSource =
    @Sendable (
        _ thresholds: @escaping @Sendable () async -> Thresholds,
        _ interval: LiveInterval,
        _ receive: @escaping @Sendable (MonitoringSnapshot) async throws -> Void
    ) async throws -> Void

@MainActor
public enum TerminalReport {
    public static func run(session: MonitoringSession, grouping: ReportGrouping = .none, color: Bool = true)
        async throws
    {
        try await run(
            grouping: grouping, thresholds: session.initialThresholds, interval: session.initialInterval,
            color: color
        ) { thresholds, interval, receive in
            try await session.run(thresholds: thresholds, interval: interval, receive)
        }
    }

    public static func run(
        grouping: ReportGrouping = .none, thresholds: Thresholds = Thresholds(), interval: Double = 1,
        color: Bool = true,
        actions: any ProcessActions = SessionActions.local(),
        diagnosisSource: @escaping CPUDiagnosisSource = CPUDiagnosisSession.collectLocal,
        source: @escaping SnapshotSource
    ) async throws {
        let identity = Identity(components: ["agent-monitor"])
        let liveInterval = LiveInterval(interval)
        let state = StateContainer(
            initialState: LiveReportState(grouping: grouping, thresholds: thresholds, interval: interval),
            invalidationIdentities: [identity])
        let outcome = TerminalOutcome()
        let diagnosis = CPUDiagnosisController(source: diagnosisSource)
        diagnosis.onChange = { [weak state] value in state?.mutate { $0.diagnosis = value } }
        // SwiftTUI 0.14.0 defaults to mouse reporting, which captures terminal selection drags.
        let host = TerminalHost(
            environment: hostEnvironment(color: color, base: ProcessInfo.processInfo.environment),
            mouseInputResolution: .preResolved(.disabled))
        // SwiftTUI 0.14.0 Running-Apps.md exposes RunLoop for custom hosts.
        // The single-screen monitor needs no scene-discovery IPC or web host.
        let runtime = RunLoop(
            rootIdentity: identity,
            presentationSurface: host,
            terminalInputReader: ActionInputReader { text in
                state.mutate { _ = $0.actionInput(.text(text)) }
            },
            signalReader: SignalReader(),
            stateContainer: state,
            focusTracker: FocusTracker(invalidationIdentities: [identity]),
            keyHandler: { key, _, state in
                if state.state.diagnosis.isVisible {
                    guard key.modifiers.isEmpty else { return .handled }
                    let size = host.surfaceSize
                    switch key.key {
                    case .character("q"): return .exit(.userExit(key))
                    case .escape: diagnosis.dismiss()
                    case .character("x"): diagnosis.cancel()
                    case .character("d"):
                        if size.width >= 40, size.height >= 8 { diagnosis.start() }
                    case .arrowUp, .arrowDown, .pageUp, .pageDown:
                        let delta: Int
                        switch key.key {
                        case .arrowUp: delta = -1
                        case .arrowDown: delta = 1
                        case .pageUp: delta = -max(1, size.height - 3)
                        default: delta = max(1, size.height - 3)
                        }
                        state.mutate {
                            $0.diagnosis.scroll(by: delta, width: size.width, height: size.height)
                        }
                    default: break
                    }
                    return .handled
                }
                if state.state.actionPanel != nil {
                    guard host.surfaceSize.width >= 40, host.surfaceSize.height >= 8 else { return .handled }
                    if let input = actionInput(key) {
                        var effect: ActionEffect?
                        state.mutate { effect = $0.actionInput(input) }
                        outcome.perform(effect, actions: actions, state: state)
                    }
                    return .handled
                }
                if key.modifiers == .shift {
                    let expanded: Bool
                    switch key.key {
                    case .arrowLeft: expanded = false
                    case .arrowRight: expanded = true
                    default: return .ignored
                    }
                    state.mutate { $0.setSessionDisclosure(expanded: expanded, from: $0.selection) }
                    return .handled
                }
                guard key.modifiers.isEmpty else { return .ignored }
                @MainActor func begin(_ kind: ProcessActionKind) {
                    var effect: ActionEffect?
                    state.mutate { effect = $0.beginAction(kind) }
                    outcome.perform(effect, actions: actions, state: state)
                }
                let shortcut: ReportShortcut?
                switch key.key {
                case .character(let character): shortcut = ReportShortcut(rawValue: String(character))
                default: shortcut = nil
                }
                if let shortcut {
                    let previousInterval = state.state.interval
                    state.mutate { $0.apply(shortcut) }
                    if state.state.interval != previousInterval { liveInterval.set(state.state.interval) }
                    return .handled
                }
                switch key.key {
                case .character("q"): return .exit(.userExit(key))
                case .character("d"):
                    if host.surfaceSize.width >= 40, host.surfaceSize.height >= 8 { diagnosis.start() }
                case .character("k"): begin(.terminate)
                case .character("s"): begin(.message)
                case .character("f"): begin(.focus)
                case .arrowUp: state.mutate { $0.moveSelection(by: -1) }
                case .arrowDown: state.mutate { $0.moveSelection(by: 1) }
                case .arrowLeft: state.mutate { $0.setDisclosure(expanded: false) }
                case .arrowRight: state.mutate { $0.setDisclosure(expanded: true) }
                case .character("-"): state.mutate { $0.adjustDetails(by: -5) }
                case .character("+"): state.mutate { $0.adjustDetails(by: 5) }
                case .character("0"): state.mutate { $0.minimizeDetails() }
                case .character("9"): state.mutate { $0.maximizeDetails() }
                case .character("="): state.mutate { $0.restoreDetails() }
                case .character("["), .character("]"):
                    let size = host.surfaceSize
                    state.mutate {
                        let maximum = LiveReportLayout.maximumDetailOffset(
                            state: $0, width: size.width, height: size.height)
                        $0.scrollDetails(by: key.key == .character("[") ? -1 : 1, maximum: maximum)
                    }
                default: return .ignored
                }
                return .handled
            },
            viewBuilder: { value, _ in
                TerminalReportView(
                    state: value, container: state, interval: liveInterval, source: source, outcome: outcome)
            }
        )
        do {
            _ = try await runtime.run()
        } catch {
            await diagnosis.stop()
            outcome.actionTask?.cancel()
            await outcome.actionTask?.value
            throw error
        }
        await diagnosis.stop()
        outcome.actionTask?.cancel()
        await outcome.actionTask?.value
        if let error = outcome.error { throw error }
    }
    /// SwiftTUI 0.14.0 resolves color from the host environment and gives NO_COLOR precedence
    /// (EnvironmentResolver.swift), so `--no-color` is passed as NO_COLOR to this host only.
    nonisolated public static func hostEnvironment(color: Bool, base: [String: String]) -> [String: String] {
        color ? base : base.merging(["NO_COLOR": "1"]) { _, new in new }
    }

    private static func actionInput(_ key: KeyPress) -> ActionInput? {
        if key.modifiers == .ctrl, key.key == .character("y") { return .confirm }
        guard key.modifiers.isEmpty || key.modifiers == .shift else { return nil }
        switch key.key {
        case .escape: return .escape
        case .return: return .review
        case .tab: return .recipient
        case .backspace: return .backspace
        case .arrowUp: return .scroll(-1)
        case .arrowDown: return .scroll(1)
        case .pageUp: return .scroll(-10)
        case .pageDown: return .scroll(10)
        case .space: return .text(" ")
        case .character(let character): return .text(String(character))
        default: return nil
        }
    }

}

@MainActor
private final class TerminalOutcome {
    var error: (any Error)?
    var actionTask: Task<Void, Never>?

    func perform(_ effect: ActionEffect?, actions: any ProcessActions, state: StateContainer<LiveReportState>)
    {
        guard let effect else { return }
        actionTask = Task {
            do {
                switch effect {
                case .prepare(let process):
                    let draft = try await actions.prepareMessage(for: process)
                    try Task.checkCancellation()
                    state.mutate { $0.messagePrepared(draft) }
                case .terminate(let process):
                    try await actions.terminate(process)
                    state.mutate {
                        $0.actionFinished(
                            .accepted(ActionWording.terminationAccepted(pid: process.process.pid))
                        )
                    }
                case .send(let draft, let text, let recipient):
                    try await actions.send(draft, text: text, recipient: recipient)
                    state.mutate {
                        $0.actionFinished(.accepted(MessageWording.accepted(draft, recipient: recipient)))
                    }
                case .focus(let process):
                    let result = try await actions.focusTerminal(of: process)
                    state.mutate { $0.actionFinished(.accepted(FocusWording.result(result))) }
                }
            } catch is CancellationError {
                return
            } catch {
                state.mutate {
                    $0.actionFinished(
                        (error as? ActionFailure)?.uncertain == true
                            ? .uncertain(error.localizedDescription) : .failed(error.localizedDescription))
                }
            }
        }
    }
}

private struct TerminalReportView: View {
    let state: LiveReportState
    let container: StateContainer<LiveReportState>
    let interval: LiveInterval
    let source: SnapshotSource
    let outcome: TerminalOutcome
    @Environment(\.requestTermination) private var requestTermination

    var body: some View {
        GeometryReader { geometry in
            let lines = LiveReportLayout.lines(
                state: state, width: geometry.size.width, height: geometry.size.height)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { item in
                    line(item.element).lineLimit(1).frame(height: 1).clipped()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task {
            do {
                try await source({ await container.state.thresholds }, interval) {
                    snapshot in
                    _ = await MainActor.run { container.mutate { $0.receive(snapshot) } }
                }
            } catch is CancellationError {
                return
            } catch {
                outcome.error = error
            }
            _ = requestTermination()
        }
    }

    @ViewBuilder
    private func line(_ line: ReportLine) -> some View {
        switch line.style {
        case .title: Text(line.text).foregroundStyle(.blue).bold()
        case .heading: Text(line.text).bold()
        case .separator: Text(line.text).foregroundStyle(.cyan).bold()
        case .selected: Text(line.text).foregroundStyle(.cyan).bold()
        case .heavy: Text(line.text).foregroundStyle(.yellow)
        case .muted: Text(line.text).foregroundStyle(.gray)
        case .warning: Text(line.text).foregroundStyle(.yellow)
        case .success: Text(line.text).foregroundStyle(.green)
        case .failure: Text(line.text).foregroundStyle(.red)
        case .normal: Text(line.text)
        }
    }
}

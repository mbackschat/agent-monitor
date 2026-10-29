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
        let inspection = session.inspectionObservations ? LiveInspection(active: true) : nil
        try await run(
            grouping: grouping, thresholds: session.initialThresholds, interval: session.initialInterval,
            sampling: session.initialSampling, cpuTopology: .readSystem(), color: color,
            inspection: inspection
        ) { thresholds, interval, receive in
            try await session.run(thresholds: thresholds, interval: interval, inspection: inspection, receive)
        }
    }

    public static func run(
        grouping: ReportGrouping = .none, thresholds: Thresholds = Thresholds(), interval: Double = 1,
        sampling: SamplingSettings? = nil, cpuTopology: ProcessorTopology? = nil,
        color: Bool = true, inspection: LiveInspection? = nil,
        actions: any ProcessActions = SessionActions.local(),
        diagnosisSource: @escaping CPUDiagnosisSource = CPUDiagnosisSession.collectLocal,
        commandSource: @escaping CommandInspectionController.Source = NativeProcessReader.inspectCommand,
        source: @escaping SnapshotSource
    ) async throws {
        defer {
            inspection?.set(false)
            if let coverage = inspection?.terminalCoverage, coverage.discardedReadings > 0 {
                print("Between-scan reads | \(coverage.discardedReadings) unadmitted readings discarded")
            }
        }
        let identity = Identity(components: ["agent-monitor"])
        let settings = sampling ?? SamplingSettings(visibleMaximum: interval)
        let liveInterval = LiveInterval(settings: settings)
        let state = StateContainer(
            initialState: LiveReportState(
                grouping: grouping, thresholds: thresholds, sampling: settings, cpuTopology: cpuTopology),
            invalidationIdentities: [identity])
        let outcome = TerminalOutcome()
        let diagnosis = CPUDiagnosisController(source: diagnosisSource)
        let commands = CommandInspectionController(source: commandSource)
        commands.onChange = { [weak state] value in state?.mutate { $0.commandInspection = value } }
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
            terminalInputReader: ActionInputReader(),
            signalReader: SignalReader(),
            stateContainer: state,
            focusTracker: FocusTracker(invalidationIdentities: [identity]),
            keyHandler: { key, _, state in
                defer {
                    commands.reconcile(with: state.state)
                    inspection?.set(!state.state.frozen)
                }
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
                            $0.scrollDiagnosis(by: delta, width: size.width, height: size.height)
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
                if state.state.referencePage != nil {
                    guard key.modifiers.isEmpty || key.modifiers == .shift else { return .handled }
                    let size = host.surfaceSize
                    switch key.key {
                    case .character("q"): return .exit(.userExit(key))
                    case .escape: state.mutate { $0.dismissReference() }
                    case .character("?"): state.mutate { $0.showReference(.glossary) }
                    case .character("D"): state.mutate { $0.showReference(.diagnostics) }
                    case .arrowUp, .arrowDown, .pageUp, .pageDown, .character("["), .character("]"):
                        let delta: Int
                        switch key.key {
                        case .arrowUp, .character("["): delta = -1
                        case .arrowDown, .character("]"): delta = 1
                        case .pageUp: delta = -max(1, size.height - 3)
                        default: delta = max(1, size.height - 3)
                        }
                        state.mutate { $0.scrollReference(by: delta, width: size.width, height: size.height) }
                    default: break
                    }
                    return .handled
                }
                if key.modifiers.isEmpty || key.modifiers == .shift {
                    switch key.key {
                    case .character("?"):
                        state.mutate { $0.showReference(.glossary) }
                        return .handled
                    case .character("D"):
                        state.mutate { $0.showReference(.diagnostics) }
                        return .handled
                    default: break
                    }
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
                @MainActor func scrollInspection(by delta: Int) {
                    let size = host.surfaceSize
                    state.mutate {
                        if $0.showsOverview {
                            if $0.overview.detailsVisible {
                                let maximum = ContributorLayout.maximumDetailOffset(
                                    state: $0, width: size.width, height: size.height)
                                $0.overview.scroll(by: delta, maximum: maximum)
                            }
                        } else if $0.detailsMode != .minimized {
                            let maximum = LiveReportLayout.maximumDetailOffset(
                                state: $0, width: size.width, height: size.height)
                            $0.scrollDetails(by: delta, maximum: maximum)
                        }
                    }
                }
                if state.state.showsOverview, state.state.overview.detailsVisible {
                    switch key.key {
                    case .tab:
                        state.mutate { $0.overview.toggleFocus() }
                        return .handled
                    case .escape:
                        state.mutate { $0.overview.toggleDetails() }
                        return .handled
                    case .arrowUp
                    where state.state.overview.focus == .details
                        && ContributorLayout.hasDetailPane(
                            state: state.state, width: host.surfaceSize.width, height: host.surfaceSize.height
                        ):
                        scrollInspection(by: -1)
                        return .handled
                    case .arrowDown
                    where state.state.overview.focus == .details
                        && ContributorLayout.hasDetailPane(
                            state: state.state, width: host.surfaceSize.width, height: host.surfaceSize.height
                        ):
                        scrollInspection(by: 1)
                        return .handled
                    default: break
                    }
                }
                let shortcut: ReportShortcut?
                switch key.key {
                case .character(let character): shortcut = ReportShortcut(rawValue: String(character))
                default: shortcut = nil
                }
                if let shortcut {
                    let previousSettings = state.state.samplingSettings
                    state.mutate { $0.apply(shortcut) }
                    if state.state.samplingSettings != previousSettings {
                        liveInterval.setSettings(state.state.samplingSettings)
                    }
                    return .handled
                }
                switch key.key {
                case .character("q"): return .exit(.userExit(key))
                case .character("d"):
                    if host.surfaceSize.width >= 40, host.surfaceSize.height >= 8 { diagnosis.start() }
                case .character("k"): begin(.terminate)
                case .character("s"): begin(.message)
                case .character("f"): begin(.focus)
                case .character("x"):
                    if commands.state != nil {
                        commands.dismiss()
                    } else if let row = state.state.commandInspectionTarget {
                        commands.start(row)
                    }
                case .return: state.mutate { $0.inspectOverviewProcess() }
                case .character("i"):
                    state.mutate { $0.toggleDetails() }
                case .pageUp: scrollInspection(by: -5)
                case .pageDown: scrollInspection(by: 5)
                case .arrowUp: state.mutate { $0.moveSelection(by: -1) }
                case .arrowDown: state.mutate { $0.moveSelection(by: 1) }
                case .arrowLeft: state.mutate { $0.setChildDisclosure(expanded: false) }
                case .arrowRight: state.mutate { $0.setChildDisclosure(expanded: true) }
                case .character("-"): state.mutate { $0.adjustDetails(by: -5) }
                case .character("+"): state.mutate { $0.adjustDetails(by: 5) }
                case .character("0"): state.mutate { $0.minimizeDetails() }
                case .character("9"): state.mutate { $0.maximizeDetails() }
                case .character("="): state.mutate { $0.restoreDetails() }
                case .character("["), .character("]"):
                    scrollInspection(by: key.key == .character("[") ? -1 : 1)
                default: return .ignored
                }
                return .handled
            },
            viewBuilder: { value, _ in
                TerminalReportView(
                    state: value, container: state, interval: liveInterval, source: source, outcome: outcome,
                    commands: commands)
            }
        )
        do {
            _ = try await runtime.run()
        } catch {
            await outcome.collection.stop()
            commands.dismiss()
            await commands.wait()
            await diagnosis.stop()
            outcome.actionTask?.cancel()
            await outcome.actionTask?.value
            throw error
        }
        await outcome.collection.stop()
        await diagnosis.stop()
        commands.dismiss()
        await commands.wait()
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
        case .arrowUp: return .scroll(-1)
        case .arrowDown: return .scroll(1)
        case .pageUp: return .scroll(-10)
        case .pageDown: return .scroll(10)
        default: return nil
        }
    }

}

@MainActor
private final class TerminalOutcome {
    var error: (any Error)?
    let collection = TerminalCollectionTask()
    var actionTask: Task<Void, Never>?

    func perform(_ effect: ActionEffect?, actions: any ProcessActions, state: StateContainer<LiveReportState>)
    {
        guard let effect else { return }
        actionTask = Task {
            do {
                switch effect {
                case .terminate(let process):
                    try await actions.terminate(process)
                    state.mutate {
                        $0.actionFinished(
                            .accepted(ActionWording.terminationAccepted(pid: process.process.pid))
                        )
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
    let commands: CommandInspectionController
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
            guard
                let task = outcome.collection.start({
                    do {
                        try await source({ await container.state.thresholds }, interval) {
                            snapshot in
                            _ = await MainActor.run {
                                container.mutate { $0.receive(snapshot) }
                                commands.reconcile(with: container.state)
                            }
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        outcome.error = error
                    }
                    _ = requestTermination()
                })
            else { return }
            await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
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

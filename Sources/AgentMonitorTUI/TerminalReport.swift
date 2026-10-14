import AgentMonitorCore
import AgentMonitorPresentation
import SwiftTUICLI
import SwiftTUIRuntime

public typealias SnapshotSource =
    @Sendable (
        _ thresholds: @escaping @Sendable () async -> Thresholds,
        _ receive: @escaping @Sendable (MonitoringSnapshot) async throws -> Void
    ) async throws -> Void

@MainActor
public enum TerminalReport {
    public static func run(session: MonitoringSession, grouping: ReportGrouping = .none) async throws {
        try await run(grouping: grouping, thresholds: session.initialThresholds) { thresholds, receive in
            try await session.run(thresholds: thresholds, receive)
        }
    }

    public static func run(
        grouping: ReportGrouping = .none, thresholds: Thresholds = Thresholds(),
        source: @escaping SnapshotSource
    ) async throws {
        let identity = Identity(components: ["agent-monitor"])
        let state = StateContainer(
            initialState: LiveReportState(grouping: grouping, thresholds: thresholds),
            invalidationIdentities: [identity])
        let outcome = TerminalOutcome()
        // SwiftTUI 0.14.0 defaults to mouse reporting, which captures terminal selection drags.
        let host = TerminalHost(mouseInputResolution: .preResolved(.disabled))
        // SwiftTUI 0.14.0 Running-Apps.md exposes RunLoop for custom hosts.
        // The single-screen monitor needs no scene-discovery IPC or web host.
        let runtime = RunLoop(
            rootIdentity: identity,
            presentationSurface: host,
            terminalInputReader: InputReader(),
            signalReader: SignalReader(),
            stateContainer: state,
            focusTracker: FocusTracker(invalidationIdentities: [identity]),
            keyHandler: { key, _, state in
                guard key.modifiers.isEmpty else { return .ignored }
                switch key.key {
                case .character("q"): return .exit(.userExit(key))
                case .arrowUp: state.mutate { $0.moveSelection(by: -1) }
                case .arrowDown: state.mutate { $0.moveSelection(by: 1) }
                case .return: state.mutate { $0.toggleDisclosure() }
                case .character("c"): state.mutate { $0.sort(by: .cpu) }
                case .character("m"): state.mutate { $0.sort(by: .memory) }
                case .character("p"): state.mutate { $0.sort(by: .pid) }
                case .character("r"): state.mutate { $0.reverseSort() }
                case .character("1"): state.mutate { $0.adjustThreshold(.cpuDown) }
                case .character("2"): state.mutate { $0.adjustThreshold(.cpuUp) }
                case .character("3"): state.mutate { $0.adjustThreshold(.memoryDown) }
                case .character("4"): state.mutate { $0.adjustThreshold(.memoryUp) }
                case .character("g"): state.mutate { $0.toggleGrouping() }
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
                TerminalReportView(state: value, container: state, source: source, outcome: outcome)
            }
        )
        _ = try await runtime.run()
        if let error = outcome.error { throw error }
    }
}

@MainActor
private final class TerminalOutcome {
    var error: (any Error)?
}

private struct TerminalReportView: View {
    let state: LiveReportState
    let container: StateContainer<LiveReportState>
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
                try await source({ await container.state.thresholds }) { snapshot in
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
        case .heading: Text(line.text).bold()
        case .separator: Text(line.text).foregroundStyle(.cyan).bold()
        case .selected: Text(line.text).foregroundStyle(.cyan).bold()
        case .heavy: Text(line.text).foregroundStyle(.yellow)
        case .muted, .normal: Text(line.text)
        }
    }
}

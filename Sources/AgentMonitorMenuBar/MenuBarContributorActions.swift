import AgentMonitorActions
import AgentMonitorCore
import AgentMonitorPresentation
import SwiftUI

struct MenuBarContributorActions: View {
    @Environment(\.backgroundProminence) private var prominence
    let model: MenuBarModel
    let node: ContributorNode

    var body: some View {
        let targets = model.report.contributorProcesses(for: node.id)
        if !targets.isEmpty {
            Menu {
                if targets.count == 1, let process = targets.first {
                    commands(process)
                } else {
                    Button(
                        "Terminate all \(targets.count) processes…"
                            + (model.report.overview.selection == node.id
                                && (model.report.overview.inspectedProcess == nil
                                    || !model.report.overview.detailsVisible)
                                && model.canBeginContributorTermination(node.id)
                                ? " (k)" : ""),
                        systemImage: "stop.circle", role: .destructive
                    ) {
                        model.beginContributorTermination(node.id)
                    }.disabled(!model.canBeginContributorTermination(node.id))
                        .help(
                            "Review all current processes before terminating"
                        )
                    Divider()
                    ForEach(targets, id: \.process) { process in
                        Menu(TextReport.safe(process.name) + " · PID " + String(process.process.pid)) {
                            Text(TextReport.safe(process.cwd ?? "Directory unavailable"))
                            commands(process)
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle").symbolRenderingMode(.palette).foregroundStyle(
                    prominence == .increased ? Color.white : Color.primary
                ).frame(width: 28, height: 28)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .tint(prominence == .increased ? Color.white : Color.primary)
                .accessibilityLabel("Actions for " + node.label.headline)
                .accessibilityIdentifier("contributor-actions")
                .help(
                    "Actions for this contributor"
                )
        }
    }

    func shortcut(_ key: String, process: ProcessIdentity) -> String {
        let kind: ProcessActionKind
        switch key {
        case "k": kind = .terminate
        case "f": kind = .focus
        default: return ""
        }
        guard model.report.overview.selection == node.id,
            model.canBegin(kind, contributor: node.id, process: process)
        else { return "" }
        if model.report.overview.detailsVisible, let inspected = model.report.overview.inspectedProcess {
            return inspected == process ? " (" + key + ")" : ""
        }
        return model.report.contributorProcesses(for: node.id).count == 1 ? " (" + key + ")" : ""
    }

    @ViewBuilder private func commands(_ process: HeavyProcess) -> some View {
        Button("Inspect process…", systemImage: "info.circle") {
            model.report.inspectContributorProcess(process.process, contributor: node.id)
        }.help("Show process details and actions")
        Button("Show terminal" + shortcut("f", process: process.process), systemImage: "terminal") {
            model.begin(.focus, contributor: node.id, process: process.process)
        }.disabled(!model.canBegin(.focus, contributor: node.id, process: process.process))
            .help(
                "Show this process's terminal" + shortcut("f", process: process.process)
            )
        Button("Message unavailable — offline", systemImage: "bubble") {}.disabled(true)
            .help("Messaging is unavailable in local-only mode")
        Divider()
        Button(
            "Terminate PID \(process.process.pid)…" + shortcut("k", process: process.process),
            systemImage: "stop.circle",
            role: .destructive
        ) {
            model.begin(.terminate, contributor: node.id, process: process.process)
        }.disabled(!model.canBegin(.terminate, contributor: node.id, process: process.process))
            .help(
                "Review termination of this process" + shortcut("k", process: process.process)
                    + "; confirmation required"
            )
    }
}

extension MenuBarModel {
    func canBeginContributorTermination(_ contributor: ContributorID) -> Bool {
        isOpen && !isPerformingAction && !diagnosis.state.isVisible && report.actionPanel == nil
            && !report.contributorProcesses(for: contributor).isEmpty
    }

    func beginContributorTermination(_ contributor: ContributorID) {
        guard canBeginContributorTermination(contributor) else { return }
        report.beginContributorTermination(contributor)
    }

    func canBegin(_ kind: ProcessActionKind, contributor: ContributorID, process: ProcessIdentity) -> Bool {
        guard isOpen, !isPerformingAction, !diagnosis.state.isVisible, report.actionPanel == nil,
            let target = report.contributorProcesses(for: contributor).first(where: { $0.process == process })
        else { return false }
        switch kind {
        case .terminate: return true
        case .focus: return SessionActions.canFocusTerminal(target)
        case .message: return false
        }
    }

    func begin(_ kind: ProcessActionKind, contributor: ContributorID, process: ProcessIdentity) {
        guard canBegin(kind, contributor: contributor, process: process) else { return }
        perform(report.beginContributorAction(kind, contributor: contributor, process: process))
    }
}

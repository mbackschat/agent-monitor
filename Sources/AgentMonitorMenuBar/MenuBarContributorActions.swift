import AgentMonitorActions
import AgentMonitorCore
import AgentMonitorPresentation
import SwiftUI

struct MenuBarContributorActions: View {
    @Environment(\.backgroundProminence) private var prominence
    let model: MenuBarModel
    let node: ContributorNode

    var body: some View {
        Menu {
            let targets = model.report.contributorProcesses(for: node.id)
            if targets.isEmpty {
                Text("No current process available")
            } else if targets.count == 1, let process = targets.first {
                commands(process)
            } else {
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
            .help("Inspect or act on a current process")
    }

    @ViewBuilder private func commands(_ process: HeavyProcess) -> some View {
        Button("Inspect process…", systemImage: "info.circle") {
            model.report.inspectContributorProcess(process.process, contributor: node.id)
        }
        Button("Show terminal", systemImage: "terminal") {
            model.begin(.focus, contributor: node.id, process: process.process)
        }.disabled(!model.canBegin(.focus, contributor: node.id, process: process.process))
        Button("Message unavailable — offline", systemImage: "bubble") {}.disabled(true)
            .help(ProviderRuntimeAvailability.messagingUnavailableReason)
        Divider()
        Button("Terminate PID \(process.process.pid)…", systemImage: "stop.circle", role: .destructive) {
            model.begin(.terminate, contributor: node.id, process: process.process)
        }.disabled(!model.canBegin(.terminate, contributor: node.id, process: process.process))
    }
}

extension MenuBarModel {
    func canBegin(_ kind: ProcessActionKind, contributor: ContributorID, process: ProcessIdentity) -> Bool {
        guard isOpen, !isPerformingAction, !diagnosis.state.isVisible, report.actionPanel == nil,
            let target = report.contributorProcesses(for: contributor).first(where: { $0.process == process })
        else { return false }
        switch kind {
        case .terminate: return true
        case .focus: return SessionActions.canFocusTerminal(target)
        case .message: return SessionActions.canMessage(target)
        }
    }

    func begin(_ kind: ProcessActionKind, contributor: ContributorID, process: ProcessIdentity) {
        guard canBegin(kind, contributor: contributor, process: process) else { return }
        perform(report.beginContributorAction(kind, contributor: contributor, process: process))
    }
}

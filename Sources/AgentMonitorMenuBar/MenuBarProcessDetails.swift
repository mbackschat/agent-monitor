import AgentMonitorCore
import AgentMonitorPresentation
import SwiftUI

struct MenuBarProcessDetails: View {
    @State private var showsEvidence = false
    let model: MenuBarModel
    let process: HeavyProcess
    var contributor: ContributorID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(TextReport.safe(process.name)).font(.headline).lineLimit(1).truncationMode(.middle)
                Text("PID \(String(process.process.pid))").foregroundStyle(.secondary)
                Button("Copy PID", systemImage: "doc.on.doc") { copyPID() }
                    .labelStyle(.iconOnly).help("Copy process ID \(process.process.pid)")
                Spacer(minLength: 0)
                Text(
                    "CPU "
                        + (process.cpuPercent.map {
                            $0.formatted(.number.precision(.fractionLength(1))) + "%"
                        }
                            ?? "unavailable")
                        + " · Memory "
                        + (process.footprintBytes.map {
                            ByteCountFormatter.string(
                                fromByteCount: Int64(clamping: $0), countStyle: .decimal)
                        } ?? "unavailable")
                )
                .font(.system(size: 12, weight: .semibold)).monospacedDigit().fixedSize()
            }
            HStack {
                Button("Terminal", systemImage: "terminal") { begin(.focus) }.disabled(!canBegin(.focus))
                    .help("Show terminal (f from the selected row or contributor process inspector)")
                Button("Message…", systemImage: "bubble") { begin(.message) }.disabled(!canBegin(.message))
                    .help(ProviderRuntimeAvailability.messagingUnavailableReason)
                Spacer(minLength: 0)
                Button("Terminate…", role: .destructive) { begin(.terminate) }.disabled(!canBegin(.terminate))
                    .help(
                        "Review this process for termination (k from the selected row or contributor process inspector)"
                    )
            }.controlSize(.small)
            path("Working directory", process.cwd ?? "Unavailable")
            path("Executable", process.executable)
            MenuBarCommandInspection(process: process, controller: model.commands)
            DisclosureGroup("Attribution and measurement", isExpanded: $showsEvidence) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(AccountingContext.process(process), id: \.self) { Text($0) }
                    if let window = model.report.snapshot?.window {
                        Text(AccountingContext.evidence(process, in: window))
                    }
                    if let peak = FootprintContext.kernelPeak(process) { Text(peak) }
                    Text(
                        "Session: \(process.attribution.threadID ?? (process.isSharedRuntime ? "shared runtime" : "unresolved"))"
                    )
                    Text("\(process.attribution.evidence.rawValue) · \(process.attribution.context.rawValue)")
                    Text("Terminal: \(process.attribution.terminal ?? "unavailable")")
                    Text("Runtime: \(process.attribution.runtime.map { String($0.pid) } ?? "unresolved")")
                    Text("Runtime directory: \(process.attribution.runtimeDirectory ?? "unavailable")")
                    Text(
                        "Observed chain: \(process.attribution.ancestry.map { String($0.pid) }.joined(separator: " ← "))"
                    )
                    if let root = process.attribution.rootSessionID { Text("Root session: " + root) }

                    if !process.attribution.candidateThreadIDs.isEmpty {
                        Text("Candidates: " + process.attribution.candidateThreadIDs.joined(separator: ", "))
                    }
                    Text("Launch origin does not prove current use of shared daemons.").foregroundStyle(
                        .secondary)
                }.fixedSize(horizontal: false, vertical: true)
            }
        }.font(.caption).lineLimit(nil).textSelection(.enabled).padding(.vertical, 6)
    }

    private func path(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).foregroundStyle(.secondary)
            Text(TextReport.safe(value)).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func canBegin(_ kind: ProcessActionKind) -> Bool {
        if let contributor { return model.canBegin(kind, contributor: contributor, process: process.process) }
        return model.canBegin(kind, row: .process(process.process))
    }

    private func begin(_ kind: ProcessActionKind) {
        if let contributor {
            model.begin(kind, contributor: contributor, process: process.process)
        } else {
            model.begin(kind, row: .process(process.process))
        }
    }

    private func copyPID() {
        if let contributor {
            guard model.isOpen,
                model.report.contributorProcesses(for: contributor).contains(where: {
                    $0.process == process.process
                })
            else { return }
            _ = MenuBarClipboard.copy(String(process.process.pid))
        } else {
            model.copyPID(row: .process(process.process))
        }
    }
}

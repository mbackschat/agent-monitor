import AgentMonitorCore
import AgentMonitorPresentation
import SwiftUI

struct MenuBarProcessDetails: View {
    @State private var showsEvidence = false
    let model: MenuBarModel
    let process: HeavyProcess
    var contributor: ContributorID?
    var keyboardTarget: LiveReportRowID?

    private var resourceSummary: String {
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
    }

    private var evidenceLines: [String] {
        var lines = AccountingContext.process(process)
        if let window = model.report.snapshot?.window {
            lines.append(AccountingContext.evidence(process, in: window))
        }
        if let peak = FootprintContext.kernelPeak(process) { lines.append(peak) }
        let owner = process.attribution
        lines += [
            "Session: \(owner.threadID ?? (process.isSharedRuntime ? "shared runtime" : "unresolved"))",
            "\(owner.evidence.rawValue) · \(owner.context.rawValue)",
            "Terminal: \(owner.terminal ?? "unavailable")",
            "Runtime: \(owner.runtime.map { String($0.pid) } ?? "unresolved")",
            "Runtime directory: \(owner.runtimeDirectory ?? "unavailable")",
            "Observed chain: \(owner.ancestry.map { String($0.pid) }.joined(separator: " ← "))",
        ]
        if let root = owner.rootSessionID { lines.append("Root session: " + root) }
        if !owner.candidateThreadIDs.isEmpty {
            lines.append("Candidates: " + owner.candidateThreadIDs.joined(separator: ", "))
        }
        lines.append("Launch origin does not prove current use of shared daemons.")
        return lines
    }

    var copyText: String {
        let arguments: [String]
        if let inspection = model.commands.state, inspection.process == process.process {
            arguments = inspection.lines
        } else if let command = process.command {
            arguments = ["Arguments:"] + command.enumerated().map { "[\($0.offset)] \($0.element)" }
        } else {
            arguments = [process.isHistorical ? "Arguments: unavailable" : "Arguments: not loaded"]
        }
        return
            ([
                process.name + " · PID \(process.process.pid)", resourceSummary,
                "Agent: " + (process.attribution.provider?.rawValue ?? "unresolved"),
                "Working directory: " + (process.cwd ?? "Unavailable"), "Executable: " + process.executable,
            ]
            + arguments + evidenceLines).joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(TextReport.safe(process.name)).font(.headline).lineLimit(1).truncationMode(.middle)
                Text("PID \(String(process.process.pid))").foregroundStyle(.secondary)
                Button("Copy PID", systemImage: "doc.on.doc") { copyPID() }
                    .labelStyle(.iconOnly).help(
                        "Copy process ID \(process.process.pid)"
                            + (contributor == nil && keyboardTarget == .process(process.process)
                                && model.pidToCopy(for: .process(process.process)) != nil ? " (y)" : "")
                    )
                Spacer(minLength: 0)
                Text(resourceSummary)
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit().fixedSize()
                MenuBarCopyDetailsButton(text: { copyText })
            }
            HStack {
                Button("Terminal", systemImage: "terminal") { begin(.focus) }.disabled(!canBegin(.focus))
                    .help("Show terminal" + shortcut("f", kind: .focus))
                Button("Message…", systemImage: "bubble") { begin(.message) }.disabled(!canBegin(.message))
                    .help("Messaging is unavailable in local-only mode")
                Spacer(minLength: 0)
                Button("Terminate…", role: .destructive) { begin(.terminate) }.disabled(!canBegin(.terminate))
                    .help(
                        "Review this process for termination" + shortcut("k", kind: .terminate)
                    )
            }.controlSize(.small)
            path("Working directory", process.cwd ?? "Unavailable")
            path("Executable", process.executable)
            MenuBarCommandInspection(process: process, controller: model.commands)
            DisclosureGroup(isExpanded: $showsEvidence) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(evidenceLines.dropLast().enumerated()), id: \.offset) { _, line in
                        Text(line)
                    }
                    Text(evidenceLines.last ?? "").foregroundStyle(.secondary)
                }.fixedSize(horizontal: false, vertical: true)
            } label: {
                Text("Attribution and measurement")
                    .help(
                        showsEvidence
                            ? "Hide attribution and measurements" : "Show attribution and measurements")
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

    private func shortcut(_ key: String, kind: ProcessActionKind) -> String {
        keyboardTarget == .process(process.process) && canBegin(kind) ? " (" + key + ")" : ""
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

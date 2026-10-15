import AgentMonitorActions
import AgentMonitorCore
import AgentMonitorPresentation
import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var model: MenuBarModel
    var maximumHeight: CGFloat = .infinity
    var onSizeChange: (CGSize) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "terminal.fill").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Agent Monitor").font(.headline)
                    if model.report.frozen, let snapshot = model.report.snapshot {
                        Text("Paused at \(snapshot.timestamp.formatted(date: .omitted, time: .standard))")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    } else {
                        Text("Live updates").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(
                    model.report.frozen ? "Resume" : "Pause",
                    systemImage: model.report.frozen ? "play.fill" : "pause.fill"
                ) { model.toggleFreeze() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(model.report.snapshot == nil || model.report.actionPanel != nil)
                .help("Hold the displayed sample and row order. Resume shows the latest sample (⇧⌘P).")
            }
            .padding()
            Divider()
            ScrollView {
                if let panel = model.report.actionPanel {
                    actionPanel(panel)
                } else {
                    report
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            HStack {
                Text("Updates only while open").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("Panel size", selection: $model.panelSize) {
                    ForEach(MenuBarPanelSize.allCases, id: \.self) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                .labelsHidden().frame(width: 100).controlSize(.small)
                Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }
            .padding(12)
        }
        .frame(width: MenuBarLayout.width, height: min(model.panelSize.height, maximumHeight))
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            onSizeChange($0)
        }
    }

    private var report: some View {
        let groups = model.report.groups
        return VStack(alignment: .leading, spacing: 12) {
            if let saved = model.savedMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Unsent message to \(saved.process.name)").font(.subheadline.bold())
                    Text(
                        "PID \(String(saved.process.process.pid)) · \(saved.recipientID ?? "unavailable recipient")"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    Text(saved.text).font(.caption).lineLimit(2).textSelection(.enabled)
                        .help(saved.text)
                    HStack {
                        Button("Resume…") { model.resumeMessage() }
                        Button("Copy text") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(saved.text, forType: .string)
                        }
                        Spacer()
                        Button("Discard", role: .destructive) { model.discardMessage() }
                    }.controlSize(.small)
                }
                Divider()
            }
            HStack {
                Text("Heavy processes").font(.subheadline.bold())
                Spacer()
                Picker(
                    "Sort",
                    selection: Binding(
                        get: { model.report.sortKey }, set: { model.report.sort(by: $0) }
                    )
                ) {
                    ForEach(ReportSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().frame(width: 120)
            }
            Text(
                "CPU > \(resource(model.report.thresholds.cpuPercent, unit: "%")) or footprint > \(resource(Double(model.report.thresholds.memoryBytes) / 1e9, unit: " GB")) · \(resource(model.report.interval, unit: " s"))"
            )
            .font(.caption).foregroundStyle(.secondary)
            if let error = model.error {
                ContentUnavailableView(
                    "Unable to sample", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if model.report.snapshot == nil {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Measuring activity…").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if groups.isEmpty {
                ContentUnavailableView(
                    "No heavy agent processes", systemImage: "checkmark.circle",
                    description: Text("Nothing exceeds the current thresholds."))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(groups, id: \.id) { group in
                        if group.processes.count == 1, let process = group.processes.first {
                            processRow(process, session: group)
                        } else {
                            session(group)
                        }
                    }
                }
                .disclosureGroupStyle(MenuBarDisclosureStyle())
            }
            if let result = model.lastActionResult {
                Text(result.text).font(.caption).textSelection(.enabled)
            }
            if let snapshot = model.report.snapshot {
                Text(
                    "Totals cover displayed heavy processes only. CPU 100% = one core.\n\(snapshot.sampledProcessCount) sampled · \(snapshot.unreadableProcessCount) unreadable"
                )
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    private func session(_ group: SessionGroup) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { model.report.openGroups.contains(group.id) },
                set: { _ in
                    model.report.select(.group(group.id))
                    model.report.toggleDisclosure()
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.sessionID ?? group.label)
                    .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                ForEach(group.processes, id: \.process) { process in
                    processRow(process)
                }
            }.padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(group.project).font(.subheadline.bold()).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(resource(group.cpuTotal, unit: "%", partial: group.cpuPartial)).monospacedDigit()
                }
                HStack {
                    Text(
                        "\(group.provider?.rawValue ?? "unknown") · \(group.sessionID.map { String($0.prefix(8)) } ?? (group.processes.first?.isSharedRuntime == true ? "shared runtime" : "unresolved")) · \(group.processes.count) heavy"
                    )
                    .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(resource(group.memoryGBTotal, unit: " GB", partial: group.memoryPartial))
                        .monospacedDigit()
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func processRow(_ process: HeavyProcess, session: SessionGroup? = nil) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text(process.executable)
                Text(
                    "Session: \(process.attribution.threadID ?? (process.isSharedRuntime ? "shared runtime" : "unresolved"))"
                )
                Text("\(process.attribution.evidence.rawValue) · \(process.attribution.context.rawValue)")
                Text("Directory: \(process.cwd ?? "unavailable")")
                Text("Terminal: \(process.attribution.terminal ?? "unavailable")")
                Text("Runtime: \(process.attribution.runtime.map { String($0.pid) } ?? "unresolved")")
                if !process.attribution.candidateThreadIDs.isEmpty {
                    Text("Candidates: " + process.attribution.candidateThreadIDs.joined(separator: ", "))
                }
                Text("Launch origin does not prove current use of shared daemons.").foregroundStyle(
                    .secondary)
                HStack {
                    Button("Terminal", systemImage: "terminal") {
                        model.begin(.focus, row: .process(process.process))
                    }
                    Button("Message…", systemImage: "bubble") {
                        model.begin(.message, row: .process(process.process))
                    }
                    .disabled(model.savedMessage != nil)
                    Spacer(minLength: 0)
                    Button("Terminate…", role: .destructive) {
                        model.begin(.terminate, row: .process(process.process))
                    }
                }
                .controlSize(.small).padding(.top, 4)
            }
            .font(.caption).textSelection(.enabled).padding(.vertical, 6)
        } label: {
            MenuBarProcessLabel(
                process: process, session: session,
                cpuText: resource(process.cpuPercent, unit: "%"),
                footprintText: resource(process.footprintBytes.map { Double($0) / 1e9 }, unit: " GB"))
        }
    }

    private func actionPanel(_ panel: ActionPanel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(panel.process.name).font(.headline)
            ForEach(ActionWording.target(panel.process), id: \.self) { Text($0).font(.caption) }
            Divider()
            switch panel.phase {
            case .confirmTermination:
                Text("Terminate this process?").font(.headline)
                Text(
                    "Send SIGTERM to PID \(panel.process.process.pid) only. This may stop work or lose unsaved changes."
                )
                HStack {
                    Button("Cancel") { model.input(.escape) }
                    Spacer()
                    Button("Terminate", role: .destructive) { model.input(.confirm) }
                }
            case .loading, .working, .focusing:
                ProgressView(panel.phase == .loading ? "Checking live recipients…" : "Working…")
                    .controlSize(.small)
                Text("Closing this panel cancels pending work.").font(.caption).foregroundStyle(
                    .secondary)
            case .compose, .review:
                messagePanel(panel)
            case .result:
                Text(panel.result?.text ?? "Action finished").textSelection(.enabled)
                Button("Done") { model.input(.escape) }
            }
        }.padding(16)
    }

    @ViewBuilder private func messagePanel(_ panel: ActionPanel) -> some View {
        Text(panel.phase == .compose ? "Message agent" : "Review exact message").font(.headline)
        if let recipient = panel.recipient {
            Text("\(recipient.label): \(recipient.id)").font(.caption).textSelection(.enabled)
            if let reason = recipient.unavailableReason { Text(reason).foregroundStyle(.orange) }
        }
        if panel.phase == .compose {
            if (panel.draft?.recipients.choices.count ?? 0) > 1 {
                Button("Change recipient") { model.input(.recipient) }
            }
            TextEditor(text: Binding(get: { model.report.actionPanel?.text ?? "" }, set: model.setMessage))
                .font(.body).frame(height: 130).border(.quaternary)
                .accessibilityLabel("Message to agent")
            HStack {
                Button("Cancel") { model.input(.escape) }
                Spacer()
                Button("Review…") { model.input(.review) }
                    .disabled(
                        panel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || panel.recipient?.unavailableReason != nil)
            }
        } else {
            Text(panel.draft?.message(panel.text) ?? panel.text).textSelection(.enabled)
            HStack {
                Button("Edit") { model.input(.escape) }
                Spacer()
                Button("Send message") { model.input(.confirm) }.buttonStyle(.borderedProminent)
            }
        }
        Text(MessageWording.note(panel.process.attribution.provider)).font(.caption).foregroundStyle(
            .secondary)
    }

    private func resource(_ value: Double?, unit: String, partial: Bool = false) -> String {
        guard let value else { return "—" }
        return "\(partial ? "~" : "")\(value.formatted(.number.precision(.fractionLength(1))))\(unit)"
    }
}

struct MenuBarDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                        .accessibilityHidden(true)
                    configuration.label
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded {
                configuration.content.padding(.leading, 16)
            }
        }
    }
}

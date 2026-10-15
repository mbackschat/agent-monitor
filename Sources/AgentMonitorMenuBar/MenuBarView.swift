import AgentMonitorActions
import AgentMonitorCore
import AgentMonitorPresentation
import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var model: MenuBarModel
    @FocusState private var focusedRow: LiveReportRowID?
    @State private var pendingPinFocus: LiveReportRowID?
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
            ScrollViewReader { proxy in
                ScrollView {
                    if model.showsKeyboardHelp {
                        MenuBarKeyboardHelp { model.showsKeyboardHelp = false }
                    }
                    if let panel = model.report.actionPanel {
                        actionPanel(panel)
                    } else {
                        report
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: focusedRow) { _, row in
                    if let row { proxy.scrollTo(row, anchor: .center) }
                }
                .onChange(of: model.report.pins.map(\.id)) { previous, current in
                    if current.count > previous.count, let row = current.last {
                        proxy.scrollTo(row, anchor: .top)
                    }
                }
            }
            Divider()
            HStack {
                Text(model.liveIcon ? "Closed: every 15 seconds" : "Updates only while open")
                    .font(.caption).foregroundStyle(.secondary)
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
        .onKeyPress(.downArrow) { moveFocus(by: 1) }
        .onKeyPress(.upArrow) { moveFocus(by: -1) }
        .task(id: pendingPinFocus) {
            guard let row = pendingPinFocus else { return }
            if model.visibleRowIDs.contains(row) { focusedRow = row }
            pendingPinFocus = nil
        }
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            onSizeChange($0)
        }
    }

    private var report: some View {
        let projection = model.report.projection
        let pinned = projection.pinnedRows
        let unpinned = projection.unpinnedRows
        let sessions = Dictionary(
            uniqueKeysWithValues: projection.groups.flatMap { group in
                group.processes.map { ($0.process, group) }
            })
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
                MenuBarViewOptions(model: model)
            }
            Text(
                "\(model.report.sortDescription) · CPU > \(resource(model.report.thresholds.cpuPercent, unit: "%")) or footprint > \(resource(Double(model.report.thresholds.memoryBytes) / 1e9, unit: " GB")) · \(resource(model.report.interval, unit: " s"))"
            )
            .font(.caption).foregroundStyle(.secondary)
            if let snapshot = model.report.snapshot,
                snapshot.cpuThresholdPercent != model.report.thresholds.cpuPercent
                    || snapshot.memoryThresholdBytes != model.report.thresholds.memoryBytes
            {
                Text("Filter changes pending next displayed sample").font(.caption).foregroundStyle(
                    .secondary)
            }
            if let error = model.error {
                ContentUnavailableView(
                    "Unable to sample", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if model.report.snapshot == nil {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Measuring activity…").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if pinned.isEmpty && unpinned.isEmpty {
                ContentUnavailableView(
                    "No heavy agent processes", systemImage: "checkmark.circle",
                    description: Text("Nothing exceeds the current thresholds."))
            } else {
                if !pinned.isEmpty {
                    Label("Pinned", systemImage: "pin.fill").font(.caption.bold()).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(pinned, id: \.id) { nativeRow($0, sessions: sessions) }
                    }
                    if !unpinned.isEmpty { Divider() }
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(unpinned, id: \.id) { nativeRow($0, sessions: sessions) }
                }
            }
            if let notice = model.report.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
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

    @ViewBuilder private func nativeRow(_ row: LiveReportRow, sessions: [ProcessIdentity: SessionGroup])
        -> some View
    {
        switch row {
        case .process(let process):
            processRow(process, session: sessions[process.process])
        case .group(let group):
            if !model.report.isPinned(row.id), group.processes.count == 1, let process = group.processes.first
            {
                processRow(process, session: group)
            } else {
                session(group)
            }
        case .unavailable(let pin):
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pin.label).lineLimit(2)
                    Text("Not in current results").foregroundStyle(.secondary)
                }.font(.caption)
                Spacer()
                MenuBarPinButton(pinned: true) { model.togglePin(pin.id) }
                    .focused($focusedRow, equals: pin.id)
                    .pinShortcut { togglePinFromKeyboard(pin.id) }
            }.padding(6)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .contextMenu { rowCommands(pin.id) }
        }
    }

    private func disclosureStyle(
        for id: LiveReportRowID, disclosure: MenuBarRowDisclosure
    ) -> MenuBarDisclosureStyle {
        MenuBarDisclosureStyle(
            id: id, disclosure: disclosure, pinned: model.report.isPinned(id),
            arrived: model.arrivals.deadlines[id] != nil,
            focus: $focusedRow,
            onPin: { model.togglePin(id) }, onPinShortcut: { togglePinFromKeyboard(id) })
    }

    private func togglePinFromKeyboard(_ row: LiveReportRowID) -> Bool {
        guard model.togglePin(row) else { return false }
        // Pinning moves rows between ForEach containers, replacing their focusable controls.
        // Restore focus after the new row mounts so a second ⌘P can undo the pin.
        focusedRow = nil
        pendingPinFocus = row
        return true
    }

    private func pinCommand(_ id: LiveReportRowID) -> some View {
        Button(model.report.isPinned(id) ? "Unpin" : "Pin", systemImage: "pin") { model.togglePin(id) }
    }

    @ViewBuilder private func rowCommands(_ id: LiveReportRowID) -> some View {
        pinCommand(id)
        Divider()
        Button("Focus terminal", systemImage: "terminal") { model.begin(.focus, row: id) }
            .disabled(!model.canBegin(.focus, row: id))
        Button("Message…", systemImage: "bubble") { model.begin(.message, row: id) }
            .disabled(!model.canBegin(.message, row: id))
        Button("Terminate…", systemImage: "stop", role: .destructive) { model.begin(.terminate, row: id) }
            .disabled(!model.canBegin(.terminate, row: id))
    }

    private func moveFocus(by delta: Int) -> KeyPress.Result {
        guard let focusedRow, model.report.actionPanel == nil else { return .ignored }
        self.focusedRow = model.moveFocus(from: focusedRow, by: delta)
        return .handled
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
                Button("Terminal", systemImage: "terminal") { model.begin(.focus, row: .group(group.id)) }
                    .controlSize(.small)
                    .disabled(!model.canBegin(.focus, row: .group(group.id)))
                ForEach(model.report.children(of: group), id: \.process) { process in
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
                        "\(group.provider?.rawValue ?? "unknown") · \(group.sessionID.map { String($0.prefix(8)) } ?? (group.processes.first?.isSharedRuntime == true ? "shared runtime" : "unresolved"))"
                    )
                    .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(resource(group.memoryGBTotal, unit: " GB", partial: group.memoryPartial))
                        .monospacedDigit()
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
        .id(LiveReportRowID.group(group.id))
        .disclosureGroupStyle(
            disclosureStyle(for: .group(group.id), disclosure: .group(count: group.processes.count))
        )
        .contextMenu { rowCommands(.group(group.id)) }
    }

    private func processRow(_ process: HeavyProcess, session: SessionGroup? = nil) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { model.report.expanded == process.process && model.report.detailsMode != .minimized },
                set: { _ in model.toggleDetails(for: process.process) }
            )
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text(process.executable)
                Text(
                    "Session: \(process.attribution.threadID ?? (process.isSharedRuntime ? "shared runtime" : "unresolved"))"
                )
                Text("\(process.attribution.evidence.rawValue) · \(process.attribution.context.rawValue)")
                Text("Directory: \(process.cwd ?? "unavailable")")
                Text("Terminal: \(process.attribution.terminal ?? "unavailable")")
                Text("Runtime: \(process.attribution.runtime.map { String($0.pid) } ?? "unresolved")")
                Text("Session directory: \(process.attribution.runtimeDirectory ?? "unavailable")")
                Text(
                    "Observed chain: \(process.attribution.ancestry.map { String($0.pid) }.joined(separator: " ← "))"
                )
                if let root = process.attribution.rootSessionID { Text("Root session: " + root) }
                if let command = process.command { Text("Command: " + command.joined(separator: " ")) }
                if !process.attribution.candidateThreadIDs.isEmpty {
                    Text("Candidates: " + process.attribution.candidateThreadIDs.joined(separator: ", "))
                }
                Text("Launch origin does not prove current use of shared daemons.").foregroundStyle(
                    .secondary)
                HStack {
                    Button("Terminal", systemImage: "terminal") {
                        model.begin(.focus, row: .process(process.process))
                    }
                    .disabled(!model.canBegin(.focus, row: .process(process.process)))
                    Button("Message…", systemImage: "bubble") {
                        model.begin(.message, row: .process(process.process))
                    }
                    .disabled(!model.canBegin(.message, row: .process(process.process)))
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
        .id(LiveReportRowID.process(process.process))
        .disclosureGroupStyle(disclosureStyle(for: .process(process.process), disclosure: .process))
        .contextMenu { rowCommands(.process(process.process)) }
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

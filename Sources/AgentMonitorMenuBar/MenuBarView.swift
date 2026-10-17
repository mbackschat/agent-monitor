import AgentMonitorActions
import AgentMonitorCore
import AgentMonitorPresentation
import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var model: MenuBarModel
    @FocusState private var focus: MenuBarFocus?
    @State private var initialFocus = MenuBarInitialFocus()
    @State private var pendingPinFocus: LiveReportRowID?
    var maximumHeight: CGFloat = .infinity
    var onSizeChange: (CGSize) -> Void = { _ in }

    private var focusedRow: LiveReportRowID? {
        get { focus?.rowID }
        nonmutating set { focus = newValue.map(MenuBarFocus.row) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "terminal.fill").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Agent Monitor").font(.headline)
                    if model.diagnosis.state.isVisible {
                        Text("Finite CPU investigation").font(.caption).foregroundStyle(.secondary)
                    } else if model.report.frozen, let snapshot = model.report.snapshot {
                        Text("Paused at \(snapshot.timestamp.formatted(date: .omitted, time: .standard))")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    } else {
                        Text("Live updates").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if model.diagnosis.state.isVisible {
                    Button("Back") { model.diagnosis.dismiss() }
                } else {
                    Button("Diagnose CPU") { model.beginDiagnosis() }
                        .disabled(
                            !model.isOpen || model.report.actionPanel != nil
                                || model.diagnosis.state.isRunning
                        )
                        .help(DiagnosisViewState.startHelp)
                    Button(
                        model.report.frozen ? "Resume" : "Pause",
                        systemImage: model.report.frozen ? "play.fill" : "pause.fill"
                    ) { model.toggleFreeze() }
                    .disabled(model.report.snapshot == nil || model.report.actionPanel != nil)
                    .help("Hold the displayed sample and row order. Resume shows the latest sample (p).")
                }
            }
            .padding()
            if !model.diagnosis.state.isVisible {
                Text(DiagnosisViewState.purpose)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal).padding(.bottom, 6)
                Text(CPUContext.text(model.report.snapshot?.cpuAccounting))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal).padding(.bottom, 12)
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    if model.showsKeyboardHelp && !model.diagnosis.state.isVisible {
                        MenuBarKeyboardHelp { model.showsKeyboardHelp = false }
                    }
                    if model.diagnosis.state.isVisible {
                        MenuBarDiagnosisView(
                            diagnosis: model.diagnosis, copyStatus: model.diagnosisCopyStatus,
                            onCopy: { model.copyDiagnosisReport() })
                    } else if let panel = model.report.actionPanel {
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
        .onChange(of: model.diagnosis.state.isVisible || model.report.actionPanel != nil) { _, inspecting in
            if inspecting { focus = nil }
        }
        .onChange(of: model.visibleRowIDs) { _, rows in
            guard model.isOpen, !model.diagnosis.state.isVisible, model.report.actionPanel == nil,
                let row = initialFocus.rowsChanged(rows, focus: focus)
            else { return }
            model.selectRow(row)
            focus = .row(row)
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { key in
            guard model.isOpen, !model.diagnosis.state.isVisible, model.report.actionPanel == nil,
                focus != nil, MenuBarKeyboard.isBulkDisclosure(modifiers: key.modifiers),
                model.report.setSessionDisclosure(
                    expanded: key.key == .rightArrow, from: focusedRow, flattenSingletons: true)
            else { return .ignored }
            if let row = focusedRow, !model.visibleRowIDs.contains(row) {
                focusedRow = model.report.selection
            }
            return .handled
        }
        .onKeyPress(.downArrow) { moveFocus(by: 1) }
        .onKeyPress(.upArrow) { moveFocus(by: -1) }
        .onKeyPress(keys: MenuBarKeyboard.keys, phases: .down) { key in
            guard !model.diagnosis.state.isVisible, model.report.actionPanel == nil,
                MenuBarKeyboard.accepts(key.characters, modifiers: key.modifiers)
            else { return .ignored }
            if key.characters == "q" {
                NSApplication.shared.terminate(nil)
                return .handled
            }
            return model.handleShortcut(key.characters, row: focusedRow) ? .handled : .ignored
        }
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
                Text(model.displayedProcessCount.map { "Heavy processes · \($0)" } ?? "Heavy processes")
                    .font(.subheadline.bold())
                Spacer()
                MenuBarViewOptions(model: model)
            }
            Text(
                "\(model.report.sortDescription) · CPU > \(resource(model.report.thresholds.cpuPercent, unit: "%")) or footprint > \(resource(Double(model.report.thresholds.memoryBytes) / 1e9, unit: " GB")) · \(resource(model.report.interval, unit: " s"))"
            )
            .font(.caption).foregroundStyle(.secondary)
            MenuBarHistoryStrip(model: model)
            if let snapshot = model.report.snapshot,
                snapshot.cpuThresholdPercent != model.report.thresholds.cpuPercent
                    || snapshot.memoryThresholdBytes != model.report.thresholds.memoryBytes
            {
                Text("Filter changes pending next displayed sample").font(.caption).foregroundStyle(
                    .secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
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
                        Label("Pinned", systemImage: "pin.fill").font(.caption.bold()).foregroundStyle(
                            .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(pinned, id: \.id) { nativeRow($0, sessions: sessions) }
                        }
                        if !unpinned.isEmpty { Divider() }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(unpinned, id: \.id) { nativeRow($0, sessions: sessions) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusable()
            .focused($focus, equals: .table)
            if let notice = model.report.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            if let result = model.lastActionResult {
                Text(result.text).font(.caption).textSelection(.enabled)
            }
            if let snapshot = model.report.snapshot {
                Text(
                    "Row totals cover displayed heavy processes only. CPU 100% = one core.\n\(snapshot.sampledProcessCount) sampled · \(snapshot.unreadableProcessCount) unreadable"
                )
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .task(id: model.isOpen) {
            guard model.isOpen else {
                focus = nil
                return
            }
            // Action review and diagnosis remove these focus targets; restore after the table remounts.
            focus = initialFocus.open(rows: model.visibleRowIDs, preferred: model.report.selection)
            if let focusedRow { model.selectRow(focusedRow) }
        }
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
                    .focused($focus, equals: .row(pin.id))
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
            focus: $focus,
            onPin: { model.togglePin(id) }, onPinShortcut: { togglePinFromKeyboard(id) })
    }

    private func togglePinFromKeyboard(_ row: LiveReportRowID) -> Bool {
        guard model.togglePin(row) else { return false }
        // Pinning moves rows between ForEach containers, replacing their focusable controls.
        // Restore focus after the new row mounts so a second period can undo the pin.
        focusedRow = nil
        pendingPinFocus = row
        return true
    }

    private func pinCommand(_ id: LiveReportRowID) -> some View {
        Button(model.report.isPinned(id) ? "Unpin" : "Pin", systemImage: "pin") { model.togglePin(id) }
    }

    @ViewBuilder private func rowCommands(_ id: LiveReportRowID) -> some View {
        pinCommand(id)
        Button("Copy PID", systemImage: "doc.on.doc") { model.copyPID(row: id) }
            .disabled(model.pidToCopy(for: id) == nil)
        Divider()
        Button("Focus terminal", systemImage: "terminal") { model.begin(.focus, row: id) }
            .disabled(!model.canBegin(.focus, row: id))
        Button("Message…", systemImage: "bubble") { model.begin(.message, row: id) }
            .disabled(!model.canBegin(.message, row: id))
        Button("Terminate…", systemImage: "stop", role: .destructive) { model.begin(.terminate, row: id) }
            .disabled(!model.canBegin(.terminate, row: id))
    }

    private func moveFocus(by delta: Int) -> KeyPress.Result {
        guard focus != nil, !model.diagnosis.state.isVisible, model.report.actionPanel == nil else {
            return .ignored
        }
        focusedRow = model.moveFocus(from: focusedRow, by: delta)
        return .handled
    }

    private func session(_ group: SessionGroup) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { model.report.openGroups.contains(group.id) },
                set: { expanded in
                    model.report.select(.group(group.id))
                    model.report.setDisclosure(expanded: expanded)
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
                set: { model.setDetails(for: process.process, expanded: $0) }
            )
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("PID: \(String(process.process.pid))").textSelection(.enabled)
                    Button("Copy PID", systemImage: "doc.on.doc") {
                        model.copyPID(row: .process(process.process))
                    }.controlSize(.small).help("Copy this process ID (y when its row is focused)")
                }
                Text(process.executable)
                Text(
                    "Session: \(process.attribution.threadID ?? (process.isSharedRuntime ? "shared runtime" : "unresolved"))"
                )
                Text("\(process.attribution.evidence.rawValue) · \(process.attribution.context.rawValue)")
                Text("Directory: \(process.cwd ?? "unavailable")")
                Text("Terminal: \(process.attribution.terminal ?? "unavailable")")
                Text("Runtime: \(process.attribution.runtime.map { String($0.pid) } ?? "unresolved")")
                Text("Runtime directory: \(process.attribution.runtimeDirectory ?? "unavailable")")
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
            if let context = panel.draft?.context {
                Text(context).font(.caption).textSelection(.enabled)
            }
            TextEditor(text: Binding(get: { model.report.actionPanel?.text ?? "" }, set: model.setMessage))
                .font(.body).frame(height: 130).border(.quaternary)
                .accessibilityLabel("Message to agent")
            HStack {
                Button("Cancel") { model.input(.escape) }
                Spacer()
                copyMessageButton
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
                copyMessageButton
                Button("Send message") { model.input(.confirm) }.buttonStyle(.borderedProminent)
            }
        }
        Text(MessageWording.note(panel.process.attribution.provider)).font(.caption).foregroundStyle(
            .secondary)
    }

    private var copyMessageButton: some View {
        Button(model.messageCopyStatus ?? "Copy message", systemImage: "doc.on.doc") { model.copyMessage() }
            .help("Copy the exact message, including the inspected process's resource context.")
    }

    private func resource(_ value: Double?, unit: String, partial: Bool = false) -> String {
        guard let value else { return "—" }
        return "\(partial ? "~" : "")\(value.formatted(.number.precision(.fractionLength(1))))\(unit)"
    }
}

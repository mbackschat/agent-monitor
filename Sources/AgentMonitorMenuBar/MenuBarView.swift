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
    var detached = false
    var onSizeChange: (CGSize) -> Void = { _ in }

    private var focusedRow: LiveReportRowID? {
        get { focus?.rowID }
        nonmutating set { focus = newValue.map(MenuBarFocus.row) }
    }

    private var overviewVisible: Bool {
        model.report.showsOverview && !model.diagnosis.state.isVisible && model.report.actionPanel == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let logo = MenuBarLogo.image {
                    Image(nsImage: logo).resizable().interpolation(.high)
                        .frame(width: 20, height: 20).accessibilityHidden(true)
                        .help("Agent Monitor")
                }
                Text("Agent Monitor").font(.headline)
                Spacer()
                Group {
                    if model.diagnosis.state.isVisible {
                        Text("Finite CPU investigation")
                    } else if model.report.frozen, let snapshot = model.report.snapshot {
                        Text("Paused at \(snapshot.timestamp.formatted(date: .omitted, time: .standard))")
                    } else {
                        Text("Live updates")
                    }
                }.font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                if model.diagnosis.state.isVisible {
                    Button("Back") { model.diagnosis.dismiss() }
                        .focused($focus, equals: .inspection)
                        .help("Return to contributors")
                } else {
                    Button(
                        model.report.frozen ? "Resume" : "Pause",
                        systemImage: model.report.frozen ? "play.fill" : "pause.fill"
                    ) { model.toggleFreeze() }
                    .labelStyle(.iconOnly)
                    .disabled(model.report.snapshot == nil || model.report.actionPanel != nil)
                    .help(
                        model.report.frozen
                            ? "Resume live updates (p)" : "Pause displayed values and row order (p)")
                }
            }
            .padding(.vertical, 10).padding(.trailing, 16).padding(.leading, 32)
            Divider()
            // Retaining the table avoids SwiftUI's nested-expansion initialization failure.
            // See docs/research/native-menu-design.md#hidden-swiftui-restoration-prototype--2026-10-27.
            ZStack {
                report(overview: true)
                    .opacity(overviewVisible ? 1 : 0)
                    .disabled(!overviewVisible)
                    .allowsHitTesting(overviewVisible)
                    .accessibilityHidden(!overviewVisible)
                if !overviewVisible { scrollingContent }
            }
            Divider()
            HStack {
                MenuBarReferenceMenu(model: model)
                Spacer()
                Picker(
                    "Panel size",
                    selection: Binding<MenuBarPanelSize?>(
                        get: { model.customPanelHeight == nil ? model.panelSize : nil },
                        set: { if let size = $0 { model.panelSize = size } }
                    )
                ) {
                    if model.customPanelHeight != nil { Text("Custom").tag(nil as MenuBarPanelSize?) }
                    ForEach(MenuBarPanelSize.allCases, id: \.self) { size in
                        Text(size.rawValue).tag(Optional(size))
                    }
                }
                .labelsHidden().frame(width: 100).controlSize(.small)
                .disabled(model.isSummaryOnly)
                .help(model.isSummaryOnly ? "Expand the table to resize" : "Choose panel height")
                Button("Quit", systemImage: "power") { NSApplication.shared.terminate(nil) }.labelStyle(
                    .iconOnly
                ).help("Quit Agent Monitor (⌘Q)").keyboardShortcut("q")
            }
            .padding(12)
            MenuBarResizeGrip(model: model, maximumHeight: maximumHeight)
                .frame(height: model.isSummaryOnly ? 0 : 16).clipped()
                .allowsHitTesting(!model.isSummaryOnly).accessibilityHidden(model.isSummaryOnly)
        }
        .frame(width: MenuBarLayout.width)
        .frame(
            minHeight: model.isSummaryOnly
                ? nil
                : min(detached ? MenuBarPanelSize.compact.height : model.panelHeight, maximumHeight),
            idealHeight: model.isSummaryOnly ? nil : min(model.panelHeight, maximumHeight),
            maxHeight: model.isSummaryOnly
                ? nil
                : (detached ? maximumHeight : min(model.panelHeight, maximumHeight))
        )
        .fixedSize(horizontal: false, vertical: model.isSummaryOnly)
        .background { MenuBarKeyboardCommands(perform: performShortcut) }
        .onChange(of: model.isSummaryOnly) { _, _ in model.onPanelSizeChange?() }
        .onChange(of: model.diagnosis.state.isVisible || model.report.actionPanel != nil) { _, inspecting in
            if inspecting {
                focus = .inspection
            } else if model.isOpen {
                restoreReportFocus()
            }
        }
        .onChange(of: model.visibleRowIDs) { _, rows in
            guard model.isOpen, !model.report.showsOverview, !model.diagnosis.state.isVisible,
                model.report.actionPanel == nil,
                let row = initialFocus.rowsChanged(rows, focus: focus)
            else { return }
            model.selectRow(row)
            focus = .row(row)
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { key in
            if model.report.showsOverview {
                return .ignored
            }
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
        .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { key in
            guard MenuBarKeyboard.accepts(String(key.key.character), modifiers: key.modifiers) else {
                return .ignored
            }
            if model.report.showsOverview {
                return .ignored
            }
            return moveFocus(by: key.key == .upArrow ? -1 : 1)
        }
        .onChange(of: model.report.showsOverview) { _, overview in
            guard model.isOpen, !model.diagnosis.state.isVisible, model.report.actionPanel == nil else {
                return
            }
            focus =
                overview
                ? (model.report.overview.tableCollapsed ? .overviewControl : .overview)
                : initialFocus.open(rows: model.visibleRowIDs, preferred: model.report.selection)
        }
        .onChange(of: model.report.overview.tableCollapsed) { _, collapsed in
            if overviewVisible { focus = collapsed ? .overviewControl : .overview }
        }
        .onChange(of: model.referencePage) { previous, page in
            if previous != nil, page == nil, model.isOpen { restoreReportFocus() }
        }
        .task(id: pendingPinFocus) {
            guard let row = pendingPinFocus else { return }
            // Finish the old row's focus teardown before focusing its replacement (keyboard regression).
            await Task.yield()
            guard !Task.isCancelled else { return }
            if model.visibleRowIDs.contains(row) { focusedRow = row }
            pendingPinFocus = nil
        }
        .task(id: model.isOpen) {
            if model.isOpen, !model.diagnosis.state.isVisible, model.report.actionPanel == nil {
                restoreReportFocus()
            } else {
                focus = nil
            }
        }
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            onSizeChange($0)
            if model.isSummaryOnly { model.onPanelSizeChange?() }
        }
    }

    private var scrollingContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.diagnosis.state.isVisible {
                    MenuBarDiagnosisView(
                        diagnosis: model.diagnosis, copyStatus: model.diagnosisCopyStatus,
                        onCopy: { model.copyDiagnosisReport() })
                } else if let panel = model.report.actionPanel {
                    actionPanel(panel)
                } else {
                    report(overview: false)
                        .task {
                            await Task.yield()
                            guard !Task.isCancelled, model.isOpen, !model.report.showsOverview,
                                !model.diagnosis.state.isVisible, model.report.actionPanel == nil
                            else { return }
                            if let row = model.report.selection { proxy.scrollTo(row, anchor: .center) }
                            restoreReportFocus()
                        }
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
    }

    private func report(overview: Bool) -> some View {
        return VStack(alignment: .leading, spacing: overview ? 8 : 12) {
            HStack {
                if overview {
                    Button {
                        model.report.overview.toggleTable()
                    } label: {
                        Image(
                            systemName: model.report.overview.tableCollapsed
                                ? "chevron.right" : "chevron.down"
                        )
                        .frame(width: 20, height: 24)
                    }.buttonStyle(.borderless)
                        .focused($focus, equals: .overviewControl)
                        .help(
                            model.report.overview.tableCollapsed ? "Expand table (8)" : "Collapse table (8)"
                        )
                        .accessibilityLabel(
                            model.report.overview.tableCollapsed
                                ? "Expand contributor table" : "Collapse contributor table")
                }
                Text(
                    overview
                        ? model.report.overview.title
                        : (model.observedProcessCount.map { "Observed processes · \($0)" }
                            ?? "Observed processes")
                )
                .font(.subheadline.bold())
                .help(overview ? model.report.overview.populationHelp : "")
                Spacer()
                if overview {
                    Button(
                        model.report.overview.showAll ? "Compact" : "Show all",
                        systemImage: model.report.overview.showAll
                            ? "line.3.horizontal.decrease" : "list.bullet"
                    ) {
                        model.report.overview.showAll.toggle()
                    }.labelStyle(.iconOnly).help(
                        model.report.overview.showAll
                            ? "Compact contributor overview (a)" : "Show all contributors (a)"
                    ).controlSize(.small)
                }
                MenuBarViewOptions(model: model)
            }
            if let error = model.error, model.report.snapshot != nil {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            if !overview { MenuBarHistoryStrip(model: model) }
            if let snapshot = model.report.snapshot,
                snapshot.cpuThresholdPercent != model.report.thresholds.cpuPercent
                    || snapshot.memoryThresholdBytes != model.report.thresholds.memoryBytes
            {
                Text("Filter changes pending next displayed sample").font(.caption).foregroundStyle(
                    .secondary)
            }
            if overview {
                MenuBarContributorOverview(model: model, focus: $focus)
            } else {
                processResults
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focusable()
                    .focused($focus, equals: .table)
            }
            if let notice = model.report.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            if let result = model.lastActionResult {
                Text(result.text).font(.caption).textSelection(.enabled)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: overview && !model.report.overview.tableCollapsed ? .infinity : nil,
            alignment: .topLeading
        )
        .padding(14)
    }

    private func restoreReportFocus() {
        focus =
            model.report.showsOverview
            ? (model.report.overview.tableCollapsed ? .overviewControl : .overview)
            : initialFocus.open(rows: model.visibleRowIDs, preferred: model.report.selection)
        if let focusedRow { model.selectRow(focusedRow) }
    }

    private var processResults: some View {
        let projection = model.rowIndex.projection
        let pinned = projection.pinnedRows
        let unpinned = projection.unpinnedRows
        return VStack(alignment: .leading, spacing: 12) {
            if let error = model.error, model.report.snapshot == nil {
                ContentUnavailableView(
                    "Unable to sample", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if model.report.snapshot == nil {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Measuring activity…").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if pinned.isEmpty && unpinned.isEmpty {
                ContentUnavailableView(
                    "No matching agent processes", systemImage: "checkmark.circle",
                    description: Text("No observed processes match this scope and its display filters."))
            } else {
                if !pinned.isEmpty {
                    Label("Pinned", systemImage: "pin.fill").font(.caption.bold()).foregroundStyle(.secondary)
                        .help("Pinned processes and sessions")
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(pinned, id: \.id) { nativeRow($0) }
                    }
                    if !unpinned.isEmpty { Divider() }
                }
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(unpinned, id: \.id) { nativeRow($0) }
                }
            }
        }
    }

    @ViewBuilder private func nativeRow(_ row: LiveReportRow)
        -> some View
    {
        switch row {
        case .process(let process):
            processRow(process, placement: .standalone)
        case .group(let group):
            if !model.report.isPinned(row.id), group.canFlatten,
                let process = model.rowIndex.projection.childrenByGroup[group.id]?.first
            {
                processRow(process, placement: .standalone)
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
                MenuBarPinButton(pinned: true, shortcutAvailable: focusedRow == pin.id) {
                    model.togglePin(pin.id)
                }
                .focused($focus, equals: .row(pin.id))
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
            onPin: { model.togglePin(id) })
    }

    private func performShortcut(_ key: String) -> Bool {
        guard model.isOpen, model.referencePage == nil, !model.diagnosis.state.isVisible,
            model.report.actionPanel == nil
        else { return false }
        if key == "q" {
            NSApplication.shared.terminate(nil)
            return true
        }
        if key == ReportShortcut.pin.rawValue, !model.report.showsOverview, let row = focusedRow {
            return togglePinFromKeyboard(row)
        }
        return model.handleShortcut(key, row: focusedRow)
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
            .help("Pin or unpin this row" + (focusedRow == id ? " (.)" : ""))
    }

    @ViewBuilder private func rowCommands(_ id: LiveReportRowID) -> some View {
        pinCommand(id)
        Button("Copy PID", systemImage: "doc.on.doc") { model.copyPID(row: id) }
            .disabled(model.pidToCopy(for: id) == nil)
            .help(
                "Copy this process ID" + (focusedRow == id && model.pidToCopy(for: id) != nil ? " (y)" : ""))
        Divider()
        Button("Focus terminal", systemImage: "terminal") { model.begin(.focus, row: id) }
            .disabled(!model.canBegin(.focus, row: id))
            .help("Show this process's terminal" + actionShortcut("f", kind: .focus, row: id))
        Button("Message…", systemImage: "bubble") { model.begin(.message, row: id) }
            .disabled(!model.canBegin(.message, row: id))
            .help("Messaging is unavailable in local-only mode")
        Button("Terminate…", systemImage: "stop", role: .destructive) { model.begin(.terminate, row: id) }
            .disabled(!model.canBegin(.terminate, row: id))
            .help("Review termination of this process" + actionShortcut("k", kind: .terminate, row: id))
    }

    private func actionShortcut(_ key: String, kind: ProcessActionKind, row: LiveReportRowID) -> String {
        focusedRow == row && model.canBegin(kind, row: row) ? " (" + key + ")" : ""
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
                    .help(
                        "Show this session's terminal"
                            + actionShortcut("f", kind: .focus, row: .group(group.id))
                    )
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.rowIndex.projection.childrenByGroup[group.id] ?? [], id: \.process) {
                        process in
                        processRow(process, placement: .sessionChild(group.id))
                    }
                }
            }.padding(.top, 8)
        } label: {
            MenuBarContributorLabel(label: group.headingLabel) {
                Text(resource(group.cpuTotal, unit: "%", partial: group.cpuPartial))
                    .monospacedDigit().frame(width: 48, alignment: .trailing)
                Text(resource(group.memoryGBTotal, unit: " GB", partial: group.memoryPartial))
                    .monospacedDigit().frame(width: 56, alignment: .trailing)
            }.font(.subheadline).help("Expand this session to inspect its processes")
        }
        .id(LiveReportRowID.group(group.id))
        .disclosureGroupStyle(
            disclosureStyle(for: .group(group.id), disclosure: .group(count: group.observedCount))
        )
        .contextMenu { rowCommands(.group(group.id)) }
    }

    private func processRow(_ process: HeavyProcess, placement: MenuBarProcessLabel.Placement) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { model.report.expanded == process.process && model.report.detailsMode != .minimized },
                set: { model.setDetails(for: process.process, expanded: $0) }
            )
        ) {
            MenuBarProcessDetails(model: model, process: process, keyboardTarget: focusedRow)
                .id(process.process)
        } label: {
            MenuBarProcessLabel(
                process: process, placement: placement,
                directory: model.rowIndex.directories.label(for: process),
                cpuText: resource(process.cpuPercent, unit: "%"),
                footprintText: resource(process.footprintBytes.map { Double($0) / 1e9 }, unit: " GB"))
        }
        .id(LiveReportRowID.process(process.process))
        .disclosureGroupStyle(disclosureStyle(for: .process(process.process), disclosure: .process))
        .contextMenu { rowCommands(.process(process.process)) }
    }

    private func actionPanel(_ panel: ActionPanel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                panel.processes.count == 1
                    ? "Selected process" : "\(panel.processes.count) selected processes"
            )
            .font(.headline)
            ForEach(panel.processes, id: \.process) { process in
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(ActionWording.target(process), id: \.self) { Text($0).font(.caption) }
                    Text("Directory: " + (process.cwd ?? "Unavailable")).font(.caption)
                }.textSelection(.enabled)
            }
            Divider()
            switch panel.phase {
            case .confirmTermination:
                Text(
                    panel.processes.count == 1 ? "Terminate this process?" : "Terminate all listed processes?"
                )
                .font(.headline)
                Text(
                    "Send SIGTERM only to the listed processes. This may stop work or lose unsaved changes. Each identity and owner is checked again; stops on failure or uncertain outcome. New arrivals are excluded."
                )
                HStack {
                    Button("Cancel") { model.input(.escape) }
                        .focused($focus, equals: .inspection)
                        .keyboardShortcut(.cancelAction)
                        .help("Cancel termination review (Esc)")
                    Spacer()
                    Button(panel.processes.count == 1 ? "Terminate" : "Terminate all", role: .destructive) {
                        model.input(.confirm)
                    }.keyboardShortcut("y", modifiers: .control).help("Confirm reviewed termination (⌃Y)")
                }
            case .working, .focusing:
                ProgressView("Working…")
                    .controlSize(.small)
                Text("Closing this panel cancels pending work.").font(.caption).foregroundStyle(
                    .secondary)
            case .result:
                Text(panel.result?.text ?? "Action finished").textSelection(.enabled)
                Button("Done") { model.input(.escape) }
                    .focused($focus, equals: .inspection)
                    .help("Close action result")
            }
        }.padding(16)
    }

    private func resource(_ value: Double?, unit: String, partial: Bool = false) -> String {
        guard let value else { return "—" }
        return "\(partial ? "~" : "")\(value.formatted(.number.precision(.fractionLength(1))))\(unit)"
    }
}

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
                }
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
                        .focused($focus, equals: .inspection)
                } else {
                    Button(
                        model.report.frozen ? "Resume" : "Pause",
                        systemImage: model.report.frozen ? "play.fill" : "pause.fill"
                    ) { model.toggleFreeze() }
                    .labelStyle(.iconOnly)
                    .disabled(model.report.snapshot == nil || model.report.actionPanel != nil)
                    .help("Hold the displayed sample and row order. Resume shows the latest sample (p).")
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
                Button("Quit", systemImage: "power") { NSApplication.shared.terminate(nil) }.labelStyle(
                    .iconOnly
                ).help("Quit Agent Monitor").keyboardShortcut("q")
            }
            .padding(12)
        }
        .frame(width: MenuBarLayout.width)
        .frame(
            minHeight: min(detached ? MenuBarPanelSize.compact.height : model.panelHeight, maximumHeight),
            idealHeight: min(model.panelHeight, maximumHeight),
            maxHeight: detached ? maximumHeight : min(model.panelHeight, maximumHeight)
        )
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
                ? .overview : initialFocus.open(rows: model.visibleRowIDs, preferred: model.report.selection)
        }
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
                            ? "Compact contributor overview" : "Show all contributors"
                    ).controlSize(.small)
                }
                MenuBarViewOptions(model: model)
            }
            if !overview, model.report.snapshot != nil {
                MenuBarCoverageStatus(model: model)
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
            maxWidth: .infinity, maxHeight: overview ? .infinity : nil,
            alignment: .topLeading
        )
        .padding(14)
    }

    private func restoreReportFocus() {
        focus =
            model.report.showsOverview
            ? .overview : initialFocus.open(rows: model.visibleRowIDs, preferred: model.report.selection)
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
            .help(ProviderRuntimeAvailability.messagingUnavailableReason)
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
            }.font(.subheadline).help(group.headingHelp)
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
            MenuBarProcessDetails(model: model, process: process)
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
            Text(panel.process.observedName).font(.headline)
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
                        .focused($focus, equals: .inspection)
                    Spacer()
                    Button("Terminate", role: .destructive) { model.input(.confirm) }
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
            }
        }.padding(16)
    }

    private func resource(_ value: Double?, unit: String, partial: Bool = false) -> String {
        guard let value else { return "—" }
        return "\(partial ? "~" : "")\(value.formatted(.number.precision(.fractionLength(1))))\(unit)"
    }
}

import AgentMonitorCore
import Foundation

public struct ReportLine: Equatable, Sendable {
    /// Display roles; the TUI maps them to colors, which NO_COLOR removes.
    public enum Style: Sendable {
        case normal, title, heading, identity, metric, selected, heavy, muted, separator, warning, success,
            failure
    }
    public struct Run: Equatable, Sendable {
        public let text: String
        public let style: Style

        public init(_ text: String, style: Style = .normal) {
            self.text = TextReport.safe(text)
            self.style = style
        }
    }

    public let runs: [Run]
    public let style: Style
    public var text: String { runs.map(\.text).joined() }

    public init(_ text: String, style: Style = .normal) {
        self.init(runs: [Run(text, style: style)], style: style)
    }

    public init(runs: [Run], style: Style = .normal) {
        self.runs = runs
        self.style = style
    }

    public func clipped(to width: Int) -> ReportLine {
        var remaining = max(0, width)
        var result: [Run] = []
        for run in runs {
            let text = TerminalCells.clipped(run.text, to: remaining)
            result.append(Run(text, style: run.style))
            remaining -= TerminalCells.width(text)
            if text != run.text { break }
        }
        return ReportLine(runs: result, style: style)
    }

    func wrapped(to width: Int) -> [ReportLine] {
        guard width > 0 else { return [] }
        var lines: [ReportLine] = []
        var runs: [Run] = []
        var used = 0
        for run in self.runs {
            var text = ""
            for character in run.text {
                let cells = TerminalCells.width(character)
                if used + cells > width && used > 0 {
                    runs.append(Run(text, style: run.style))
                    lines.append(ReportLine(runs: runs, style: style))
                    runs = []
                    text = ""
                    used = 0
                }
                text.append(cells > width ? "�" : character)
                used += min(cells, width)
            }
            runs.append(Run(text, style: run.style))
        }
        if !runs.isEmpty { lines.append(ReportLine(runs: runs, style: style)) }
        return lines
    }

}

public enum LiveReportLayout {
    public static func lines(state: LiveReportState, width: Int, height: Int) -> [ReportLine] {
        guard height > 0, width > 0 else { return [] }
        if state.diagnosis.isVisible {
            return state.diagnosis.terminalLines(width: width, height: height, offset: state.diagnosisOffset)
        }
        if state.referencePage != nil {
            return ReportReferenceLayout.lines(state: state, width: width, height: height)
        }
        if width < 40 || height < 8 {
            return Array(
                [
                    ReportLine("Agent Monitor"), ReportLine("Resize to 40x8 or larger"),
                    ReportLine(state.actionPanel == nil ? "q/Ctrl-C quit" : "Ctrl-C quit"),
                ].prefix(height)
            ).map { $0.clipped(to: width) }
        }
        if let panel = state.actionPanel { return panel.lines(width: width, height: height) }
        if state.showsOverview { return ContributorLayout.lines(state: state, width: width, height: height) }
        let layout = paneLayout(state: state, width: width, height: height)
        var lines = layout.header
        lines += processLines(state: state, width: width, height: layout.processHeight)
        lines += detailsPane(state: state, width: width, height: layout.detailHeight)
        lines += layout.footer.map { ReportLine($0, style: .muted) }
        return lines.map { $0.clipped(to: width) }
    }

    public static func maximumDetailOffset(state: LiveReportState, width: Int, height: Int) -> Int {
        guard width >= 40, height >= 8 else { return 0 }
        let visible = paneLayout(state: state, width: width, height: height).detailHeight - 1
        guard visible > 0 else { return 0 }
        return max(0, detailLines(state: state, width: width).count - visible)
    }

    private static func paneLayout(state: LiveReportState, width: Int, height: Int)
        -> (header: [ReportLine], footer: [String], processHeight: Int, detailHeight: Int)
    {
        var header = headerLines(state: state, width: width) + [historyLine(state: state, width: width)]
        let minimumProcess = state.detailsMode == .maximized ? 0 : (width < 85 ? 3 : 2)
        let minimumBody = max(3, minimumProcess + 1)
        var footer = helpLines(
            width: width, height: height, headerHeight: header.count, frozen: state.frozen,
            diagnosisRunning: state.diagnosis.isRunning)
        if height - header.count - footer.count < minimumBody {
            let coverage = state.displayCoverageStatus
            // UX-01 puts the selected responsibility above optional chrome. Counts keep
            // reduced coverage detail explicit; Diagnostics retains the full notes.
            let coverageText = coverage.terminalSummary(width: width)
            header = [ReportLine(coverageText, style: coverage.lineStyle)]
            if !state.thresholds.isUnfiltered || filtersPending(state) {
                header.append(ReportLine(filterText(state), style: .muted))
            }
            if state.frozen {
                let stamp = state.snapshot.map { " at " + clockTime($0.timestamp) } ?? ""
                let resize = state.notice == nil ? "" : " · resize"
                header.insert(ReportLine("PAUSED\(stamp) | p resume\(resize)", style: .title), at: 0)
                if let notice = state.notice { footer[0] = notice }
            } else if let notice = state.notice {
                header.append(ReportLine(notice, style: .warning))
            }
            let limit = height - footer.count - max(3, minimumProcess)
            if !state.frozen, state.notice == nil, header.count < limit {
                header.insert(ReportLine("Agent Monitor", style: .title), at: 0)
            }
        }
        let available = max(0, height - header.count - footer.count)
        let details = detailHeight(state: state, available: available, minimumProcess: minimumProcess)
        return (header, footer, available - details, details)
    }

    private static func historyLine(state: LiveReportState, width: Int) -> ReportLine {
        ReportLine(
            state.history.line(metric: state.historyMetric, window: state.historyWindow, width: width),
            style: .muted)
    }

    private static func filterText(_ state: LiveReportState) -> String {
        ThresholdContext.text(state.thresholds) + (filtersPending(state) ? " (pending)" : "")
    }

    private static func filtersPending(_ state: LiveReportState) -> Bool {
        state.snapshot.map {
            $0.cpuThresholdPercent != state.thresholds.cpuPercent
                || $0.memoryThresholdBytes != state.thresholds.memoryBytes
        } ?? false
    }

    private static func headerLines(state: LiveReportState, width: Int) -> [ReportLine] {
        let seconds = String(format: "%g", state.interval)
        let frozen =
            state.frozen
            ? "PAUSED" + (state.snapshot.map { " at " + clockTime($0.timestamp) } ?? "")
                + " | p resume | " : ""
        let cadence =
            state.snapshot?.window == nil
            ? (state.samplingSettings.enabled ? "acquire max \(seconds) s" : "every \(seconds) s")
            : "acquire \(state.samplingSettings.enabled ? "max " : "")\(seconds) s / display \(String(format: "%g", LiveReportState.displayIntervalSeconds)) s"
        let activity = "\(state.sortDescription) | \(cadence)"
        let title =
            state.frozen ? frozen + activity : "Agent Monitor | \(activity) | Updates: \(state.updates)"
        let status: String
        if let notice = state.notice {
            status = notice
        } else if state.grouping == .session {
            status = "\(state.rows.count) shown / \(state.groups.count) launch groups"
        } else if let snapshot = state.snapshot {
            status = "\(state.rows.count) shown / \(snapshot.sampledProcessCount) sampled"
        } else {
            status = "Sampling baseline…"
        }
        let filters = filterText(state)
        let coverageStatus = state.displayCoverageStatus
        // The on-demand diagnostics contract (docs/architecture.md) keeps a reserved status row
        // so a coverage warning does not move the selected contributor.
        let coverage = [
            ReportLine(coverageStatus.terminalSummary(width: width), style: coverageStatus.lineStyle)
        ]

        switch width {
        case 120...:
            return [
                ReportLine(
                    title + " | " + abbreviated(status, width: width - title.count - filters.count - 6)
                        + " | " + filters, style: .title)
            ] + coverage
        case 85..<120:
            return [
                ReportLine(
                    title + " | " + abbreviated(status, width: width - title.count - 3), style: .title),
                ReportLine(filters, style: .muted),
            ] + coverage
        default:
            return [
                ReportLine(title, style: .title), ReportLine(status, style: .title),
                ReportLine(filters, style: .muted),
            ] + coverage
        }
    }

    private static func helpLines(
        width: Int, height: Int, headerHeight: Int, frozen: Bool, diagnosisRunning: Bool
    ) -> [String] {
        let diagnosisHint = diagnosisRunning ? DiagnosisViewState.cleanupHint : DiagnosisViewState.keyHint
        let groups = [
            [
                "↑/↓ select", "←/→ fold", "g group", "c/m/n/o sort", "r reverse",
                ". pin", diagnosisHint,
            ],
            [frozen ? "p resume" : "p pause", "k terminate", "f focus"],
            ["1/2 CPU -/+10%", "3/4 GB -/+1", "</> interval"],
            ["Details: i", "Pg↑↓", "-/+ size", "0 hide", "9 max", "= restore"],
            ["? help", "| q/Ctrl-C quit"],
        ]
        var lines: [String] = []
        var line = ""
        func append(_ text: String) {
            let candidate = line.isEmpty ? text : line + " " + text
            if candidate.count > width {
                lines.append(line)
                line = text
            } else {
                line = candidate
            }
        }
        for controls in groups {
            for control in controls { append(control) }
        }
        lines.append(line)
        return lines.count <= height - headerHeight - 3
            ? lines
            : [
                diagnosisRunning ? diagnosisHint : "? help | \(diagnosisHint)",
                diagnosisRunning
                    ? "? help | q/Ctrl-C quit"
                    : (frozen ? "p resume | q/Ctrl-C quit" : "p pause | q/Ctrl-C quit"),
            ]
    }

    private static func abbreviated(_ text: String, width: Int) -> String {
        TerminalCells.abbreviated(TextReport.safe(text), to: width)
    }

    private static func detailHeight(state: LiveReportState, available: Int, minimumProcess: Int) -> Int {
        let height: Int
        switch state.detailsMode {
        case .minimized: height = 1
        case .maximized: height = available
        case .split:
            let requested = Int((Double(available) * Double(state.detailsPercent) / 100).rounded())
            height = min(available - 1, max(2, requested))
        }
        return max(0, min(available - minimumProcess, height))
    }

    private static func processLines(state: LiveReportState, width: Int, height: Int) -> [ReportLine] {
        guard height > 0 else { return [] }
        let projection = state.projection
        let rows = state.visibleRows(in: projection)
        let branches = childBranches(rows: rows, projection: projection, expanded: state.openGroups)
        let identifiers = rows.compactMap { row -> String? in
            switch row {
            case .group(let group): "#\(group.observedCount)"
            case .process(let process): String(process.process.pid)
            case .unavailable: nil
            }
        }
        let groupMetrics = rows.compactMap { row -> (Double?, Double?)? in
            guard case .group(let group) = row else { return nil }
            return (group.cpuTotal, group.memoryGBTotal)
        }
        let metrics =
            state.rows.map { ($0.cpuPercent, $0.footprintBytes.map { Double($0) / 1e9 }) } + groupMetrics
        let table = ReportTable(
            metrics: metrics,
            processNames: state.rows.map { (branches[$0.process] ?? "") + processName($0) },
            identifiers: identifiers)
        let narrow = width < 85
        let hasGroups = rows.contains { if case .group = $0 { true } else { false } }
        let columns = table.columns(for: width, leadingInset: narrow ? 0 : 2)
        let heading =
            narrow
            ? table.directoryHeader(grouped: state.grouping == .session || hasGroups)
            : "  " + table.header(columns: columns, grouped: state.grouping == .session, hasGroups: hasGroups)
        var lines = [ReportLine(heading, style: .muted)]
        let capacity = height - 1
        func rowHeight(_ row: LiveReportRow) -> Int {
            if case .unavailable = row { return 1 }
            return narrow ? 2 : 1
        }
        let selectedIndex = rows.firstIndex { $0.id == state.selection } ?? 0
        var start = selectedIndex
        var occupied = rows.isEmpty ? 0 : rowHeight(rows[selectedIndex])
        while start > 0 && occupied + rowHeight(rows[start - 1]) <= capacity {
            start -= 1
            occupied += rowHeight(rows[start])
        }
        let directories = ProcessDirectoryLabels(state.rows)
        for entry in rows.dropFirst(start) {
            guard lines.count + rowHeight(entry) <= height else {
                if lines.count == 1 && capacity > 0 {
                    lines.append(ReportLine("Resize for identity and resources", style: .muted))
                }
                break
            }
            let selected = entry.id == state.selection
            switch entry {
            case .group(let group):
                if narrow {
                    lines += narrowGroupLines(
                        group, selected: selected, state: state, table: table, width: width)
                } else {
                    lines.append(groupLine(group, selected: selected, state: state, table: table))
                }
            case .process(let row):
                if narrow {
                    lines += narrowProcessLines(
                        row, selected: selected, state: state, table: table, directories: directories,
                        branch: branches[row.process], width: width)
                } else {
                    lines.append(
                        processLine(
                            row, state: state, table: table, columns: columns, directories: directories,
                            branch: branches[row.process], width: width))
                }
            case .unavailable(let pin):
                let marker = TerminalRowMarker.text(selected: selected, pinned: true)
                lines.append(
                    ReportLine(
                        "\(marker) Not in current results · \(pin.label)",
                        style: selected ? .selected : .muted))
            }
        }
        if rows.isEmpty {
            lines.append(
                ReportLine(
                    state.snapshot == nil
                        ? "Waiting for first report…"
                        : "No processes match the display filters in this scope.")
            )
        }
        return padded(lines, to: height)
    }

    private static func childBranches(
        rows: [LiveReportRow], projection: ReportProjection, expanded: Set<SessionGroupID>
    ) -> [ProcessIdentity: String] {
        var branches: [ProcessIdentity: String] = [:]
        for case .group(let group) in rows where expanded.contains(group.id) {
            let children = projection.childrenByGroup[group.id] ?? []
            for (index, child) in children.enumerated() {
                branches[child.process] = index == children.count - 1 ? "└─ " : "├─ "
            }
        }
        return branches
    }

    private static func narrowGroupLines(
        _ group: SessionGroup, selected: Bool, state: LiveReportState, table: ReportTable, width: Int
    ) -> [ReportLine] {
        let marker = TerminalRowMarker.text(selected: selected, pinned: state.isPinned(.group(group.id)))
        let disclosure = state.openGroups.contains(group.id) ? "▾" : "▸"
        let identity = group.sessionID.map { String($0.prefix(8)) } ?? group.sessionDescription
        let title =
            "\(marker)\(disclosure) \(group.provider?.rawValue ?? "unknown")/\(identity)"
            + " · \(group.observedCount) \(group.observedCount == 1 ? "process" : "processes")"
            + (group.isRoot ? " root" : "")
        let style: ReportLine.Style = selected ? .selected : .heading
        let prefix = groupPrefix(group, selected: selected, state: state, table: table)
        return [
            ReportLine(
                runs: [.init(abbreviated(title, width: width), style: selected ? .selected : .identity)],
                style: style),
            ReportLine(
                runs: table.styledPrefix(prefix, sort: state.sortKey, selected: selected)
                    + [.init(abbreviated(group.project, width: width - TerminalCells.width(prefix)))],
                style: style),
        ]
    }

    private static func narrowProcessLines(
        _ row: HeavyProcess, selected: Bool, state: LiveReportState, table: ReportTable,
        directories: ProcessDirectoryLabels, branch: String?, width: Int
    ) -> [ReportLine] {
        let marker = TerminalRowMarker.text(selected: selected, pinned: state.isPinned(.process(row.process)))
        let agent =
            "\(row.attribution.provider?.rawValue ?? "unknown")/\(sessionLabel(row, width: 8))"
        let title =
            marker + (branch ?? "") + "i " + (row.isHistorical ? "[past] " : "")
            + "\(agent) · \(row.observedName)"
        let style: ReportLine.Style =
            selected ? .selected : (state.isPinned(.process(row.process)) ? .heading : .heavy)
        let directory = directories.label(for: row)
        let prefix = processPrefix(row, state: state, table: table)
        return [
            ReportLine(
                runs: [.init(abbreviated(title, width: width), style: selected ? .selected : .identity)],
                style: style),
            ReportLine(
                runs: table.styledPrefix(prefix, sort: state.sortKey, selected: selected)
                    + [.init(abbreviated(directory, width: width - TerminalCells.width(prefix)))],
                style: style),
        ]
    }

    private static func groupPrefix(
        _ group: SessionGroup, selected: Bool, state: LiveReportState, table: ReportTable,
        disclosure: String? = nil
    ) -> String {
        let marker =
            disclosure.map {
                TerminalRowMarker.text(selected: selected, pinned: state.isPinned(.group(group.id))) + $0
            } ?? TerminalRowMarker.selection(selected)
        return table.rowPrefix(
            marker: marker,
            pid: "#\(group.observedCount)", cpu: group.cpuTotal,
            memoryGB: group.memoryGBTotal, partialCPU: group.cpuPartial, partialMemory: group.memoryPartial)
    }

    private static func groupLine(
        _ group: SessionGroup, selected: Bool, state: LiveReportState, table: ReportTable
    ) -> ReportLine {
        let disclosure = state.openGroups.contains(group.id) ? "▾" : "▸"
        let prefix = groupPrefix(
            group, selected: selected, state: state, table: table, disclosure: disclosure)
        return ReportLine(
            runs: table.styledPrefix(prefix, sort: state.sortKey, selected: selected)
                + group.labelRuns.map {
                    .init($0.text, style: selected && $0.style == .identity ? .selected : $0.style)
                },
            style: selected ? .selected : .heading)
    }

    private static func processPrefix(
        _ row: HeavyProcess, state: LiveReportState, table: ReportTable,
        showInspectionMarker: Bool = false
    ) -> String {
        let cpuThreshold = state.snapshot?.cpuThresholdPercent ?? state.thresholds.cpuPercent
        let memoryThreshold = state.snapshot?.memoryThresholdBytes ?? state.thresholds.memoryBytes
        let selected = row.process == state.selected
        let marker =
            showInspectionMarker
            ? TerminalRowMarker.text(selected: selected, pinned: state.isPinned(.process(row.process))) + "i"
            : TerminalRowMarker.selection(selected)
        return table.rowPrefix(
            marker: marker,
            pid: String(row.process.pid),
            cpu: row.cpuPercent, memoryGB: row.footprintBytes.map { Double($0) / 1e9 },
            heavyCPU: row.cpuPercent.map { $0 > cpuThreshold } ?? false,
            heavyMemory: row.footprintBytes.map { $0 > memoryThreshold } ?? false)
    }

    private static func processLine(
        _ row: HeavyProcess, state: LiveReportState, table: ReportTable, columns: ReportTable.Columns,
        directories: ProcessDirectoryLabels, branch: String?, width: Int
    ) -> ReportLine {
        let prefix = processPrefix(row, state: state, table: table, showInspectionMarker: true)
        let provider = row.attribution.provider?.rawValue ?? "unknown"
        let sessionWidth = max(8, columns.agent - provider.count - 1)
        let agent = "\(provider)/\(sessionLabel(row, width: state.grouping == .session ? 8 : sessionWidth))"
        let description: [ReportLine.Run]
        switch state.grouping {
        case .session:
            description = groupedProcessDescription(
                row, agent: agent, directory: directories.label(for: row), branch: branch,
                width: width - TerminalCells.width(prefix))
        case .none:
            description = flatDescription(
                row, agent: agent, directory: directories.label(for: row), branch: branch, columns: columns)
        }
        return ReportLine(
            runs: table.styledPrefix(prefix, sort: state.sortKey, selected: row.process == state.selected)
                + description.map {
                    .init(
                        $0.text,
                        style: row.process == state.selected && $0.style == .identity ? .selected : $0.style)
                },
            style: row.process == state.selected
                ? .selected : (state.isPinned(.process(row.process)) ? .heading : .heavy))
    }

    private static func groupedProcessDescription(
        _ row: HeavyProcess, agent: String, directory: String, branch: String?, width: Int
    ) -> [ReportLine.Run] {
        // A scrolled-away group header cannot supply ownership: reserve all three fields
        // before clipping individual text (product contract: information that belongs together).
        let agentWidth = min(TerminalCells.width(TextReport.safe(agent)), max(16, width / 3))
        let guide = branch ?? ""
        let workloadWidth = max(0, width - agentWidth - TerminalCells.width(guide) - 6)
        let processWidth = min(
            TerminalCells.width(TextReport.safe(processName(row))), max(8, workloadWidth / 2))
        return [
            .init(guide), .init(abbreviated(processName(row), width: processWidth), style: .identity),
            .init(" · " + abbreviated(directory, width: max(0, workloadWidth - processWidth))),
            .init(" · "), .init(abbreviated(agent, width: agentWidth), style: .identity),
        ]
    }

    private static func processName(_ row: HeavyProcess) -> String {
        (row.isHistorical ? "[past] " : "") + row.observedName
    }

    private static func flatDescription(
        _ row: HeavyProcess, agent: String, directory: String, branch: String?, columns: ReportTable.Columns
    ) -> [ReportLine.Run] {
        [
            .init(
                ReportTable.pad(
                    abbreviated((branch ?? "") + processName(row), width: columns.process),
                    to: columns.process) + " ", style: .identity),
            .init(
                ReportTable.pad(abbreviated(agent, width: columns.agent), to: columns.agent) + " ",
                style: .identity),
            .init(abbreviated(directory, width: columns.directory)),
        ]
    }

    private static func sessionLabel(_ row: HeavyProcess, width: Int) -> String {
        if row.isSharedRuntime { return row.sessionDescription }
        return row.attribution.threadID.map { String($0.prefix(width)) }
            ?? (row.attribution.evidence == .ambiguous ? "ambiguous" : "unresolved")
    }

    private static func detailsPane(state: LiveReportState, width: Int, height: Int) -> [ReportLine] {
        let details = detailLines(state: state, width: width)
        let visible = max(0, height - 1)
        let offset = min(state.detailOffset, max(0, details.count - visible))
        let title: String
        switch state.detailsMode {
        case .minimized: title = "Details min | i/= show"
        case .maximized: title = "Details max | launch origin"
        case .split: title = "Details | pane \(state.detailsPercent)% | launch origin"
        }
        let range =
            details.isEmpty || visible == 0
            ? "" : " | \(offset + 1)-\(min(offset + visible, details.count))/\(details.count)"
        let divider = String(("─ " + title + range + " ").prefix(width)).padding(
            toLength: width, withPad: "─", startingAt: 0)
        var lines = [ReportLine(divider, style: .separator)]
        if visible > 0 {
            if details.isEmpty {
                lines.append(
                    ReportLine(
                        state.selected == nil ? "No process selected." : "i to show selected process.",
                        style: .muted))
            } else {
                lines += details.dropFirst(offset).prefix(visible)
            }
        }
        return padded(lines, to: height)
    }

    private static func padded(_ lines: [ReportLine], to height: Int) -> [ReportLine] {
        Array(lines.prefix(height)) + Array(repeating: ReportLine(" "), count: max(0, height - lines.count))
    }

    private static func detailLines(state: LiveReportState, width: Int) -> [ReportLine] {
        if let id = state.selectedGroup, let group = state.groups.first(where: { $0.id == id }) {
            return
                ([
                    field("Launch " + (group.isRoot ? "root" : "session"), group.sessionDescription),
                    ReportLine(runs: group.labelRuns),
                    ReportLine("All observed members; ~ marks partial totals with missing measurements."),
                    ReportLine("Launch origin does not prove current use of shared daemons."),
                    ReportLine("←/→ folds children · ↑/↓ selects · i shows/hides details."),
                ]).flatMap { $0.wrapped(to: width) }
        }
        guard let row = state.rows.first(where: { $0.process == state.expanded }) else { return [] }
        let attribution = row.attribution
        var values = [
            ReportLine(runs: [
                .init("PID \(row.process.pid)", style: .identity), .init(" | \(row.executable)"),
            ]),
            field(
                "Session",
                "\(row.sessionDescription) [\(attribution.evidence.rawValue), \(attribution.context.rawValue)]",
                valueStyle: attribution.evidence == .ambiguous || attribution.threadID == nil
                    ? .warning : .normal),
            field(
                "Runtime",
                "\(attribution.runtime.map { String($0.pid) } ?? "unresolved") | TTY: \(attribution.terminal ?? "unavailable")"
            ),
            field("Work directory", row.cwd ?? "unavailable"),
            field("Runtime directory", attribution.runtimeDirectory ?? "unavailable"),
            field("Observed chain", attribution.ancestry.map { String($0.pid) }.joined(separator: " ← ")),
        ]
        values += AccountingContext.process(row).map { ReportLine($0) }
        if let window = state.snapshot?.window {
            values.append(ReportLine(AccountingContext.evidence(row, in: window), style: .metric))
            values.append(ReportLine(AccountingContext.acquisition(window.acquisitionCoverage)))
            if let range = AccountingContext.publicationRange(
                window.publicationCoverage, endingAt: window.endedAt)
            {
                values.append(ReportLine(range))
            }
        }
        if let peak = FootprintContext.kernelPeak(row) { values.append(ReportLine(peak, style: .metric)) }
        if let root = attribution.rootSessionID { values.append(field("Root session", root)) }
        if !attribution.candidateThreadIDs.isEmpty {
            values.append(field("Candidates", attribution.candidateThreadIDs.joined(separator: ", ")))
        }
        if let inspection = state.commandInspection, inspection.process == row.process {
            values += inspection.lines.map { ReportLine($0) }
            values.append(ReportLine("x hide arguments"))
        } else if let command = row.command {
            values.append(field("Command", command.joined(separator: " ")))
        } else if !row.isHistorical {
            values.append(ReportLine("x read arguments on demand"))
        }
        return values.flatMap { $0.wrapped(to: width) }
    }

    private static func field(_ label: String, _ value: String, valueStyle: ReportLine.Style = .normal)
        -> ReportLine
    {
        ReportLine(runs: [.init(label + ": ", style: .identity), .init(value, style: valueStyle)])
    }

    /// Local wall-clock time of the frozen snapshot, so the user can judge how stale it is.
    private static func clockTime(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return String(
            format: "%02d:%02d:%02d", components.hour ?? 0, components.minute ?? 0, components.second ?? 0)
    }
}

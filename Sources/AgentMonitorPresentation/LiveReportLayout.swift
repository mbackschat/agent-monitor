import AgentMonitorCore
import Foundation

public struct ReportLine: Equatable, Sendable {
    /// Display roles; the TUI maps them to colors, which NO_COLOR removes.
    public enum Style: Sendable {
        case normal, title, heading, selected, heavy, muted, separator, warning, success, failure
    }
    public let text: String
    public let style: Style

    public init(_ text: String, style: Style = .normal) {
        self.text = TextReport.safe(text)
        self.style = style
    }
}

public enum LiveReportLayout {
    public static func lines(state: LiveReportState, width: Int, height: Int) -> [ReportLine] {
        guard height > 0, width > 0 else { return [] }
        if state.diagnosis.isVisible {
            return state.diagnosis.terminalLines(width: width, height: height, offset: state.diagnosisOffset)
        }
        if width < 40 || height < 8 {
            return Array(
                [
                    ReportLine("Agent Monitor"), ReportLine("Resize to 40x8 or larger"),
                    ReportLine(state.actionPanel == nil ? "q/Ctrl-C quit" : "Ctrl-C quit"),
                ].prefix(height)
            ).map { ReportLine(TerminalCells.clipped($0.text, to: width), style: $0.style) }
        }
        if let panel = state.actionPanel { return panel.lines(width: width, height: height) }
        if state.showsOverview { return ContributorLayout.lines(state: state, width: width, height: height) }
        var lines = headerLines(state: state, width: width)
        lines.append(historyLine(state: state, width: width))
        let footer = helpLines(
            width: width, height: height, headerHeight: lines.count, frozen: state.frozen,
            diagnosisRunning: state.diagnosis.isRunning)
        let available = max(0, height - lines.count - footer.count)
        let detailHeight = detailHeight(state: state, available: available)
        lines += processLines(state: state, width: width, height: available - detailHeight)
        lines += detailsPane(state: state, width: width, height: detailHeight)
        lines += footer.map { ReportLine($0, style: .muted) }
        return lines.map { ReportLine(TerminalCells.clipped($0.text, to: width), style: $0.style) }
    }

    public static func maximumDetailOffset(state: LiveReportState, width: Int, height: Int) -> Int {
        guard width >= 40, height >= 8 else { return 0 }
        let headerHeight = headerLines(state: state, width: width).count + 1
        let available =
            height - headerHeight
            - helpLines(
                width: width, height: height, headerHeight: headerHeight, frozen: state.frozen,
                diagnosisRunning: state.diagnosis.isRunning
            ).count
        let visible = detailHeight(state: state, available: available) - 1
        guard visible > 0 else { return 0 }
        return max(0, detailLines(state: state, width: width).count - visible)
    }

    private static func historyLine(state: LiveReportState, width: Int) -> ReportLine {
        ReportLine(
            state.history.line(metric: state.historyMetric, window: state.historyWindow, width: width),
            style: .muted)
    }

    private static func headerLines(state: LiveReportState, width: Int) -> [ReportLine] {
        let seconds = String(format: "%g", state.interval)
        let frozen =
            state.frozen
            ? "PAUSED" + (state.snapshot.map { " at " + clockTime($0.timestamp) } ?? "")
                + " | p resume | " : ""
        let cadence =
            state.snapshot?.window == nil
            ? "every \(seconds) s"
            : "acquire \(seconds) s / display \(String(format: "%g", LiveReportState.displayIntervalSeconds)) s"
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
        let pending =
            state.snapshot.map {
                $0.cpuThresholdPercent != state.thresholds.cpuPercent
                    || $0.memoryThresholdBytes != state.thresholds.memoryBytes
            } ?? false
        let filters =
            ThresholdContext.text(state.thresholds)
            + (pending ? " (pending)" : "")
        let context = ReportLine(
            CPUContext.text(state.snapshot?.cpuAccounting)
                + (state.snapshot?.window.map {
                    " · window " + ReportNumber.text($0.durationSeconds) + " s; point candidates"
                } ?? ""), style: .muted)
        let coverageStatus = state.snapshot.map(CoverageStatus.init(snapshot:)) ?? CoverageStatus(notes: [])
        // One coverage row is always reserved, so a gap appearing or clearing does not move the
        // panes; only an oversized status wraps. Both panes use the resulting height (architecture's TUI contract).
        let coverage = TerminalCells.wrapped(coverageStatus.text, to: width).map {
            ReportLine($0, style: coverageStatus.lineStyle)
        }

        switch width {
        case 120...:
            return [
                ReportLine(
                    title + " | " + abbreviated(status, width: width - title.count - filters.count - 6)
                        + " | " + filters, style: .title),
                context,
            ] + coverage
        case 85..<120:
            return [
                ReportLine(
                    title + " | " + abbreviated(status, width: width - title.count - 3), style: .title),
                ReportLine(filters, style: .muted), context,
            ] + coverage
        default:
            return [
                ReportLine(title, style: .title), ReportLine(status, style: .title),
                ReportLine(filters, style: .muted), context,
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
            [frozen ? "p resume" : "p pause", "k terminate", "s message", "f focus"],
            ["1/2 CPU -/+10%", "3/4 GB -/+1", "</> interval"],
            ["[/] scroll", "-/+ size", "0 min", "9 max", "= restore", "q/Ctrl-C quit"],
        ]
        var lines: [String] = []
        var line = ""
        func append(_ text: String, separator: String) {
            let candidate = line.isEmpty ? text : line + separator + text
            if candidate.count > width {
                lines.append(line)
                line = text
            } else {
                line = candidate
            }
        }
        for controls in groups {
            for (index, control) in controls.enumerated() {
                append(control, separator: index == 0 ? " | " : "  ")
            }
        }
        lines.append(line)
        return lines.count <= height - headerHeight - 3
            ? lines
            : [
                diagnosisRunning ? diagnosisHint : "\(diagnosisHint) | Resize for all keys",
                diagnosisRunning
                    ? "Resize for all keys | q/Ctrl-C quit"
                    : (frozen ? "p resume | q/Ctrl-C quit" : "p pause | q/Ctrl-C quit"),
            ]
    }

    private static func abbreviated(_ text: String, width: Int) -> String {
        TerminalCells.abbreviated(TextReport.safe(text), to: width)
    }

    private static func detailHeight(state: LiveReportState, available: Int) -> Int {
        let height: Int
        switch state.detailsMode {
        case .minimized: height = 1
        case .maximized: height = available
        case .split:
            let requested = Int((Double(available) * Double(state.detailsPercent) / 100).rounded())
            height = min(available - 1, max(2, requested))
        }
        // The smallest supported viewport can leave no pane rows below the fixed chrome.
        return max(0, min(available, height))
    }

    private static func processLines(state: LiveReportState, width: Int, height: Int) -> [ReportLine] {
        guard height > 0 else { return [] }
        let rows = state.visibleRows
        let metrics =
            state.rows.map { ($0.cpuPercent, $0.footprintBytes.map { Double($0) / 1e9 }) }
            + (state.grouping == .session ? state.groups.map { ($0.cpuTotal, $0.memoryGBTotal) } : [])
        let table = ReportTable(metrics: metrics, processNames: state.rows.map(\.observedName))
        let columns = table.columns(for: width)
        let narrow = width < 60
        let heading =
            narrow
            ? table.directoryHeader(grouped: state.grouping == .session)
            : table.header(columns: columns, grouped: state.grouping == .session)
        var lines = [ReportLine(heading, style: .heading)]
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
        let directories =
            narrow
            ? WorkloadDirectory.compactLabels(
                for: Set(state.rows.compactMap { $0.isSharedRuntime ? nil : $0.cwd }))
            : [:]
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
                        width: width)
                } else {
                    lines.append(processLine(row, state: state, table: table, columns: columns))
                }
            case .unavailable(let pin):
                lines.append(
                    ReportLine(
                        "\(selected ? "@" : "+") Not in current results · \(pin.label)",
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

    private static func narrowGroupLines(
        _ group: SessionGroup, selected: Bool, state: LiveReportState, table: ReportTable, width: Int
    ) -> [ReportLine] {
        let marker = rowMarker(selected: selected, pinned: state.isPinned(.group(group.id)))
        let disclosure = state.openGroups.contains(group.id) ? "[-]" : "[+]"
        let identity = group.sessionID.map { String($0.prefix(8)) } ?? group.sessionDescription
        let title =
            "\(marker) \(disclosure) \(group.provider?.rawValue ?? "unknown")/\(identity)"
            + (group.isRoot ? " root" : "")
            + (group.sessionName.map { " · " + $0 } ?? "")
        let style: ReportLine.Style = selected ? .selected : .heading
        let prefix = groupPrefix(group, selected: selected, state: state, table: table)
        return [
            ReportLine(abbreviated(title, width: width), style: style),
            ReportLine(
                prefix + abbreviated(group.project, width: width - TerminalCells.width(prefix)),
                style: style),
        ]
    }

    private static func narrowProcessLines(
        _ row: HeavyProcess, selected: Bool, state: LiveReportState, table: ReportTable,
        directories: [String: String], width: Int
    ) -> [ReportLine] {
        let marker = rowMarker(selected: selected, pinned: state.isPinned(.process(row.process)))
        let agent =
            "\(row.attribution.provider?.rawValue ?? "unknown")/\(sessionLabel(row, width: 8))"
        let title =
            "\(marker) " + (row.isHistorical ? "[past] " : "") + "\(agent) · \(row.observedName)"
        let style: ReportLine.Style =
            selected ? .selected : (state.isPinned(.process(row.process)) ? .heading : .heavy)
        let directory =
            row.isSharedRuntime
            ? "Shared runtime"
            : row.cwd.map { directories[$0] ?? WorkloadDirectory.compact($0) }
                ?? "CWD unavailable"
        let prefix = processPrefix(row, state: state, table: table)
        return [
            ReportLine(abbreviated(title, width: width), style: style),
            ReportLine(
                prefix + abbreviated(directory, width: width - TerminalCells.width(prefix)), style: style),
        ]
    }

    private static func rowMarker(selected: Bool, pinned: Bool) -> String {
        switch (selected, pinned) {
        case (true, true): "@"
        case (false, true): "+"
        case (true, false): ">"
        case (false, false): " "
        }
    }

    private static func groupPrefix(
        _ group: SessionGroup, selected: Bool, state: LiveReportState, table: ReportTable
    ) -> String {
        table.rowPrefix(
            marker: rowMarker(selected: selected, pinned: state.isPinned(.group(group.id))),
            pid: String(group.observedCount), cpu: group.cpuTotal,
            memoryGB: group.memoryGBTotal, partialCPU: group.cpuPartial, partialMemory: group.memoryPartial)
    }

    private static func groupLine(
        _ group: SessionGroup, selected: Bool, state: LiveReportState, table: ReportTable
    ) -> ReportLine {
        let prefix = groupPrefix(group, selected: selected, state: state, table: table)
        let disclosure = state.openGroups.contains(group.id) ? "[-]" : "[+]"
        return ReportLine(prefix + "\(disclosure) \(group.label)", style: selected ? .selected : .heading)
    }

    private static func processPrefix(
        _ row: HeavyProcess, state: LiveReportState, table: ReportTable
    ) -> String {
        let cpuThreshold = state.snapshot?.cpuThresholdPercent ?? state.thresholds.cpuPercent
        let memoryThreshold = state.snapshot?.memoryThresholdBytes ?? state.thresholds.memoryBytes
        return table.rowPrefix(
            marker: rowMarker(
                selected: row.process == state.selected, pinned: state.isPinned(.process(row.process))),
            pid: String(row.process.pid),
            cpu: row.cpuPercent, memoryGB: row.footprintBytes.map { Double($0) / 1e9 },
            heavyCPU: row.cpuPercent.map { $0 > cpuThreshold } ?? false,
            heavyMemory: row.footprintBytes.map { $0 > memoryThreshold } ?? false)
    }

    private static func processLine(
        _ row: HeavyProcess, state: LiveReportState, table: ReportTable, columns: ReportTable.Columns
    ) -> ReportLine {
        let prefix = processPrefix(row, state: state, table: table)
        let provider = row.attribution.provider?.rawValue ?? "unknown"
        let sessionWidth =
            switch columns {
            case .compact: 8
            case .wide(_, let agent): max(8, agent - provider.count - 1)
            }
        let agent = "\(provider)/\(sessionLabel(row, width: sessionWidth))"
        let description =
            state.grouping == .session
            ? "  \(row.observedName) \(agent) [\(row.attribution.evidence.rawValue), \(row.attribution.context.rawValue)]"
            : flatDescription(row, agent: agent, columns: columns)
        return ReportLine(
            prefix + (row.isHistorical ? "[past] " : "") + description,
            style: row.process == state.selected
                ? .selected : (state.isPinned(.process(row.process)) ? .heading : .heavy))
    }

    private static func flatDescription(_ row: HeavyProcess, agent: String, columns: ReportTable.Columns)
        -> String
    {
        switch columns {
        case .wide(let processWidth, let agentWidth):
            let project = row.isSharedRuntime ? nil : row.cwd
            return
                "\(ReportTable.pad(row.observedName, to: processWidth)) \(ReportTable.pad(agent, to: agentWidth)) \(row.attribution.terminal ?? "no tty") / \(project.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "?")"
        case .compact(let processWidth, let agentWidth):
            return ReportTable.pad(abbreviated(row.observedName, width: processWidth), to: processWidth) + " "
                + abbreviated(agent, width: agentWidth)
        }
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
        case .minimized: title = "Details min | →/= restore"
        case .maximized: title = "Details max | launch origin"
        case .split: title = "Details \(state.detailsPercent)% | launch origin"
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
                        state.selected == nil ? "No process selected." : "→ to show selected process.",
                        style: .muted))
            } else {
                lines += details.dropFirst(offset).prefix(visible).map { ReportLine($0) }
            }
        }
        return padded(lines, to: height)
    }

    private static func padded(_ lines: [ReportLine], to height: Int) -> [ReportLine] {
        Array(lines.prefix(height)) + Array(repeating: ReportLine(" "), count: max(0, height - lines.count))
    }

    private static func detailLines(state: LiveReportState, width: Int) -> [String] {
        if let id = state.selectedGroup, let group = state.groups.first(where: { $0.id == id }) {
            return wrapped(
                [
                    "Launch \(group.isRoot ? "root" : "session"): \(group.sessionDescription)",
                    group.label,
                    "All observed members; ~ marks partial totals with missing measurements.",
                    "Launch origin does not prove current use of shared daemons.",
                    "←/→ collapses/expands processes; ↑/↓ selects a process, then → opens its details.",
                ], width: width)
        }
        guard let row = state.rows.first(where: { $0.process == state.expanded }) else { return [] }
        let attribution = row.attribution
        var values = [
            "PID \(row.process.pid) | \(row.executable)",
            "Session: \(row.sessionName.map { $0 + " · " } ?? "")\(row.sessionDescription) [\(attribution.evidence.rawValue), \(attribution.context.rawValue)]",
            "Runtime: \(attribution.runtime.map { String($0.pid) } ?? "unresolved") | TTY: \(attribution.terminal ?? "unavailable")",
            "Work directory: \(row.cwd ?? "unavailable")",
            "Runtime directory: \(attribution.runtimeDirectory ?? "unavailable")",
            "Observed chain: \(attribution.ancestry.map { String($0.pid) }.joined(separator: " ← "))",
        ]
        values += AccountingContext.process(row)
        if let window = state.snapshot?.window {
            values.append(AccountingContext.evidence(row, in: window))
            values.append(AccountingContext.acquisition(window.acquisitionCoverage))
            if let range = AccountingContext.publicationRange(
                window.publicationCoverage, endingAt: window.endedAt)
            {
                values.append(range)
            }
        }
        if let peak = FootprintContext.kernelPeak(row) { values.append(peak) }
        if let root = attribution.rootSessionID { values.append("Root session: \(root)") }
        if !attribution.candidateThreadIDs.isEmpty {
            values.append("Candidates: " + attribution.candidateThreadIDs.joined(separator: ", "))
        }
        if let inspection = state.commandInspection, inspection.process == row.process {
            values += inspection.lines
            values.append("x hide arguments")
        } else if let command = row.command {
            values.append("Command: " + command.joined(separator: " "))
        } else if !row.isHistorical {
            values.append("x read arguments on demand")
        }
        return wrapped(values, width: width)
    }

    private static func wrapped(_ values: [String], width: Int) -> [String] {
        values.flatMap { TerminalCells.wrapped(TextReport.safe($0), to: width) }
    }

    /// Local wall-clock time of the frozen snapshot, so the user can judge how stale it is.
    private static func clockTime(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return String(
            format: "%02d:%02d:%02d", components.hour ?? 0, components.minute ?? 0, components.second ?? 0)
    }
}

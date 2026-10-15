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
        if width < 40 || height < 8 {
            return Array(
                [
                    ReportLine("Agent Monitor"), ReportLine("Resize to 40x8 or larger"),
                    ReportLine(state.actionPanel == nil ? "q/Ctrl-C quit" : "Ctrl-C quit"),
                ].prefix(height)
            ).map { ReportLine(String($0.text.prefix(width)), style: $0.style) }
        }
        if let panel = state.actionPanel { return panel.lines(width: width, height: height) }
        var lines = headerLines(state: state, width: width)
        let footer = helpLines(width: width, height: height, headerHeight: lines.count)
        let available = height - lines.count - footer.count
        let detailHeight = detailHeight(state: state, available: available)
        lines += processLines(state: state, width: width, height: available - detailHeight)
        lines += detailsPane(state: state, width: width, height: detailHeight)
        lines += footer.map { ReportLine($0, style: .muted) }
        return lines.map { ReportLine(String($0.text.prefix(width)), style: $0.style) }
    }

    public static func maximumDetailOffset(state: LiveReportState, width: Int, height: Int) -> Int {
        guard width >= 40, height >= 8 else { return 0 }
        let headerHeight = headerLines(state: state, width: width).count
        let available =
            height - headerHeight - helpLines(width: width, height: height, headerHeight: headerHeight).count
        let visible = detailHeight(state: state, available: available) - 1
        guard visible > 0 else { return 0 }
        return max(0, detailLines(state: state, width: width).count - visible)
    }

    private static func headerLines(state: LiveReportState, width: Int) -> [ReportLine] {
        let seconds = String(format: "%g", state.interval)
        let frozen =
            state.frozen ? " | FROZEN" + (state.snapshot.map { " at " + clockTime($0.timestamp) } ?? "") : ""
        let title =
            "Agent Monitor | \(state.sortKey.rawValue) \(state.ascending ? "ascending" : "descending") | every \(seconds) s\(frozen) | Updates: \(state.updates)"
        let status: String
        if let notice = state.notice {
            status = notice
        } else if state.grouping == .session {
            status = "\(state.rows.count) heavy / \(state.groups.count) launch groups"
        } else if let snapshot = state.snapshot {
            status = "\(state.rows.count) heavy / \(snapshot.sampledProcessCount) sampled"
        } else {
            status = "Sampling baseline…"
        }
        let pending =
            state.snapshot.map {
                $0.cpuThresholdPercent != state.thresholds.cpuPercent
                    || $0.memoryThresholdBytes != state.thresholds.memoryBytes
            } ?? false
        let filters =
            "CPU > \(ReportNumber.text(state.thresholds.cpuPercent))% OR GB > \(ReportNumber.text(Double(state.thresholds.memoryBytes) / 1e9))"
            + (pending ? " (pending)" : "")
        // Width-based row counts preserve pane geometry across changing status text; see docs/architecture.md.
        switch width {
        case 120...:
            return [
                ReportLine(
                    title + " | " + abbreviated(status, width: width - title.count - filters.count - 6)
                        + " | " + filters, style: .title)
            ]
        case 85..<120:
            return [
                ReportLine(
                    title + " | " + abbreviated(status, width: width - title.count - 3), style: .title),
                ReportLine(filters, style: .muted),
            ]
        default:
            return [
                ReportLine(title, style: .title), ReportLine(status, style: .title),
                ReportLine(filters, style: .muted),
            ]
        }
    }

    private static func helpLines(width: Int, height: Int, headerHeight: Int) -> [String] {
        let groups = [
            ["↑/↓ select", "Enter open", "g group", "c/m/p sort", "r reverse", "[/] scroll"],
            ["k terminate", "s message", "f focus"],
            ["1/2 CPU -/+10%", "3/4 GB -/+1", "</> interval", "space freeze"],
            ["-/+ size", "0 min", "9 max", "= restore", "q/Ctrl-C quit"],
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
            let group = controls.joined(separator: "   ")
            if group.count <= width {
                append(group, separator: "  |  ")
            } else {
                for (index, control) in controls.enumerated() {
                    append(control, separator: index == 0 ? "  |  " : "   ")
                }
            }
        }
        lines.append(line)
        return lines.count <= height - headerHeight - 3 ? lines : ["Resize for all keys", "q/Ctrl-C quit"]
    }

    private static func abbreviated(_ text: String, width: Int) -> String {
        guard text.count > width else { return text }
        return String(text.prefix(max(0, width - 1))) + (width > 0 ? "…" : "")
    }

    private static func detailHeight(state: LiveReportState, available: Int) -> Int {
        switch state.detailsMode {
        case .minimized: return 1
        case .maximized: return available
        case .split:
            let requested = Int((Double(available) * Double(state.detailsPercent) / 100).rounded())
            return min(available - 1, max(2, requested))
        }
    }

    private static func processLines(state: LiveReportState, width: Int, height: Int) -> [ReportLine] {
        guard height > 0 else { return [] }
        let rows = state.visibleRows
        let metrics =
            state.rows.map { ($0.cpuPercent, $0.footprintBytes.map { Double($0) / 1e9 }) }
            + (state.grouping == .session ? state.groups.map { ($0.cpuTotal, $0.memoryGBTotal) } : [])
        let table = ReportTable(metrics: metrics, processNames: state.rows.map(\.name))
        let columns = table.columns(for: width)
        var lines = [
            ReportLine(table.header(columns: columns, grouped: state.grouping == .session), style: .heading)
        ]
        let capacity = height - 1
        let selectedIndex = rows.firstIndex { $0.id == state.selection } ?? 0
        let start = max(0, min(selectedIndex - capacity + 1, rows.count - capacity))
        for entry in rows.dropFirst(start).prefix(capacity) {
            let selected = entry.id == state.selection
            switch entry {
            case .group(let group):
                lines.append(groupLine(group, selected: selected, state: state, table: table))
            case .process(let row):
                lines.append(processLine(row, state: state, table: table, columns: columns))
            }
        }
        if rows.isEmpty {
            lines.append(
                ReportLine(
                    state.snapshot == nil ? "Waiting for first report…" : "No heavy processes in this scope.")
            )
        }
        return padded(lines, to: height)
    }

    private static func groupLine(
        _ group: SessionGroup, selected: Bool, state: LiveReportState, table: ReportTable
    ) -> ReportLine {
        let prefix = table.rowPrefix(
            marker: selected ? ">" : " ", pid: String(group.processes.count), cpu: group.cpuTotal,
            memoryGB: group.memoryGBTotal, partialCPU: group.cpuPartial, partialMemory: group.memoryPartial)
        let disclosure = state.openGroups.contains(group.id) ? "[-]" : "[+]"
        return ReportLine(prefix + "\(disclosure) \(group.label)", style: selected ? .selected : .heading)
    }

    private static func processLine(
        _ row: HeavyProcess, state: LiveReportState, table: ReportTable, columns: ReportTable.Columns
    ) -> ReportLine {
        let cpuThreshold = state.snapshot?.cpuThresholdPercent ?? state.thresholds.cpuPercent
        let memoryThreshold = state.snapshot?.memoryThresholdBytes ?? state.thresholds.memoryBytes
        let prefix = table.rowPrefix(
            marker: row.process == state.selected ? ">" : " ", pid: String(row.process.pid),
            cpu: row.cpuPercent, memoryGB: row.footprintBytes.map { Double($0) / 1e9 },
            heavyCPU: row.cpuPercent.map { $0 > cpuThreshold } ?? false,
            heavyMemory: row.footprintBytes.map { $0 > memoryThreshold } ?? false)
        let provider = row.attribution.provider?.rawValue ?? "unknown"
        let sessionWidth =
            switch columns {
            case .compact: 8
            case .wide(_, let agent): max(8, agent - provider.count - 1)
            }
        let agent = "\(provider)/\(sessionLabel(row, width: sessionWidth))"
        let description =
            state.grouping == .session
            ? "  \(row.name) \(agent) [\(row.attribution.evidence.rawValue), \(row.attribution.context.rawValue)]"
            : flatDescription(row, agent: agent, columns: columns)
        return ReportLine(prefix + description, style: row.process == state.selected ? .selected : .heavy)
    }

    private static func flatDescription(_ row: HeavyProcess, agent: String, columns: ReportTable.Columns)
        -> String
    {
        switch columns {
        case .wide(let processWidth, let agentWidth):
            let project = row.attribution.runtimeDirectory ?? row.cwd
            return
                "\(ReportTable.pad(row.name, to: processWidth)) \(ReportTable.pad(agent, to: agentWidth)) \(row.attribution.terminal ?? "no tty") / \(project.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "?")"
        case .compact(let processWidth, let agentWidth):
            return ReportTable.pad(abbreviated(row.name, width: processWidth), to: processWidth) + " "
                + abbreviated(agent, width: agentWidth)
        }
    }

    private static func sessionLabel(_ row: HeavyProcess, width: Int) -> String {
        row.attribution.threadID.map { String($0.prefix(width)) }
            ?? (row.attribution.evidence == .ambiguous ? "ambiguous" : "unresolved")
    }

    private static func detailsPane(state: LiveReportState, width: Int, height: Int) -> [ReportLine] {
        let details = detailLines(state: state, width: width)
        let visible = max(0, height - 1)
        let offset = min(state.detailOffset, max(0, details.count - visible))
        let title: String
        switch state.detailsMode {
        case .minimized: title = "Details min | Enter/= restore"
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
                        state.selected == nil ? "No process selected." : "Enter to show selected process.",
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
                    "Launch \(group.isRoot ? "root" : "session"): \(group.sessionID ?? "unresolved")",
                    group.label,
                    "Heavy-process totals only; ~ marks partial totals with missing measurements.",
                    "Launch origin does not prove current use of shared daemons.",
                    "Enter expands/collapses processes; arrows select a process, then Enter opens its details.",
                ], width: width)
        }
        guard let row = state.rows.first(where: { $0.process == state.expanded }) else { return [] }
        let attribution = row.attribution
        var values = [
            "PID \(row.process.pid) | \(row.executable)",
            "Session: \(attribution.threadID ?? "unresolved") [\(attribution.evidence.rawValue), \(attribution.context.rawValue)]",
            "Runtime: \(attribution.runtime.map { String($0.pid) } ?? "unresolved") | TTY: \(attribution.terminal ?? "unavailable")",
            "Work directory: \(row.cwd ?? "unavailable")",
            "Session directory: \(attribution.runtimeDirectory ?? "unavailable")",
            "Observed chain: \(attribution.ancestry.map { String($0.pid) }.joined(separator: " ← "))",
        ]
        if let root = attribution.rootSessionID { values.append("Root session: \(root)") }
        if !attribution.candidateThreadIDs.isEmpty {
            values.append("Candidates: " + attribution.candidateThreadIDs.joined(separator: ", "))
        }
        if let command = row.command { values.append("Command: " + command.joined(separator: " ")) }
        return wrapped(values, width: width)
    }

    private static func wrapped(_ values: [String], width: Int) -> [String] {
        return values.flatMap { value -> [String] in
            var remaining = TextReport.safe(value)[...]
            var result: [String] = []
            while !remaining.isEmpty {
                let end = remaining.index(remaining.startIndex, offsetBy: min(width, remaining.count))
                result.append(String(remaining[..<end]))
                remaining = remaining[end...]
            }
            return result
        }
    }

    /// Local wall-clock time of the frozen snapshot, so the user can judge how stale it is.
    private static func clockTime(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return String(
            format: "%02d:%02d:%02d", components.hour ?? 0, components.minute ?? 0, components.second ?? 0)
    }
}

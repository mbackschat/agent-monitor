import Foundation

public enum ContributorLayout {
    public static func lines(state: LiveReportState, width: Int, height: Int) -> [ReportLine] {
        let overview = state.overview
        let rows = overview.visibleRows
        let columns = Columns(width: width)
        let prefix = state.frozen ? "PAUSED · p resume" : "Agent Monitor · p pause"
        let title = ReportLine(prefix + " | Main contributors | v processes", style: .title)
        let totals = ReportLine(overview.totals.summary(duration: overview.duration))
        let history = ReportLine(
            "Agents "
                + state.history.line(
                    metric: state.historyMetric, window: state.historyWindow, width: max(1, width - 7)),
            style: .muted)
        let range = ReportLine(
            "Recent " + overview.sourceDurationLabel
                + " · CPU over \(String(format: "%.1f", overview.duration)) s · point candidates",
            style: .muted)
        var header = [
            title, totals, history, range,
        ]
        let status = overview.coverageStatus
        let coverage = TerminalCells.wrapped(status.text, to: width).map {
            ReportLine($0, style: status.lineStyle)
        }
        header.insert(contentsOf: coverage, at: 2)
        var filters =
            state.thresholds.isUnfiltered
            ? [] : [ReportLine(ThresholdContext.text(state.thresholds), style: .muted)]
        if let notice = overview.pinNotice { filters.append(ReportLine(notice, style: .warning)) }
        header += filters
        let heading = ReportLine(
            columns.row(
                "GROUP / EXECUTABLE / PROCESS", cpu: "CPU", memory: "MEMORY", recent: "RECENT CPU",
                now: "NOW"), style: .heading)
        header.append(heading)
        // UX-01 requires identity and resources together even when coverage grows. Optional
        // chrome yields first; coverage can collapse only into an explicit counted summary.
        let minimumBody = rows.isEmpty ? 0 : 2
        let fullFooter = footerLines(state: state, width: width, compact: false)
        let fullHelpFits = coverage.count + filters.count + 2 + minimumBody + fullFooter.count <= height
        let footer = fullHelpFits ? fullFooter : footerLines(state: state, width: width, compact: true)
        let headerLimit = max(0, height - footer.count - minimumBody)
        for optional in [history, range, heading] where header.count > headerLimit {
            if let index = header.firstIndex(of: optional) { header.remove(at: index) }
        }
        if header.count > headerLimit, coverage.count > 2 {
            header = [title, totals] + compactCoverage(status) + filters
        }
        for optional in [totals, title] where header.count > headerLimit {
            if let index = header.firstIndex(of: optional) { header.remove(at: index) }
        }
        if header.count > headerLimit {
            header = Array((compactCoverage(status) + filters).prefix(headerLimit))
        }
        var content: [(ContributorID, ReportLine)] = []
        var continuations: Set<Int> = []
        for row in rows {
            let selected = row.id == overview.selection
            let folded = row.node.children.isEmpty ? "·" : (overview.open.contains(row.id) ? "▾" : "▸")
            let indent = String(repeating: "  ", count: row.depth)
            let pinned = overview.pinned.contains(row.id)
            let marker = TerminalRowMarker.text(selected: selected, pinned: pinned)
            let prefix = "\(marker)\(indent)\(folded) "
            let stats = row.node.stats
            let cpuBar = columns.bar(overview.cpuMeterFraction(stats))
            let memoryBar = columns.bar(overview.memoryMeterFraction(stats))
            let rowLines = columns.rows(
                row.node.label, prefix: prefix,
                cpu: stats.cpuText(duration: overview.duration) + cpuBar,
                memory: stats.memoryText + memoryBar, recent: stats.recentCPUText,
                now: stats.currentAvailable ? String(stats.current.count) : "—")
            for (index, line) in rowLines.enumerated() {
                if index == 1 { continuations.insert(content.count) }
                content.append((row.id, ReportLine(line, style: selected ? .selected : .normal)))
            }
            if selected, overview.detailsVisible {
                let fields =
                    row.node.inspectionFields.filter { $0.kind == .context }
                    + row.node.populationFields + row.node.inspectionFields.filter { $0.kind == .evidence }
                let details =
                    InspectionField.terminalLines(fields, width: max(10, width - indent.count - 2))
                    + (row.id == .section(.uncertain)
                        ? (overview.samplingCoverage?.terminalLines(width: max(10, width - indent.count - 2))
                            ?? []) : [])
                for line in details {
                    content.append((row.id, ReportLine(indent + "  " + line, style: .muted)))
                }
            }
        }
        let available = max(0, height - header.count - footer.count)
        let selected = content.firstIndex { $0.0 == overview.selection } ?? 0
        var offset = min(
            max(0, selected + overview.detailOffset - available / 2), max(0, content.count - available))
        if overview.detailOffset == 0, available >= 2, continuations.contains(selected + 1),
            selected + 2 > offset + available
        {
            offset = selected + 2 - available
        }
        if continuations.contains(offset) { offset += 1 }
        var end = min(content.count, offset + available)
        let clippedBlock = end > offset && continuations.contains(end)
        if clippedBlock { end -= 1 }
        var body = content[offset..<end].map(\.1)
        if clippedBlock {
            body.append(ReportLine(body.isEmpty ? "Resize for complete contributor rows" : "", style: .muted))
        }
        let result = header + body + footer
        return Array(result.prefix(height)).map {
            ReportLine(TerminalCells.clipped($0.text, to: width), style: $0.style)
        }
    }

    private static func compactCoverage(_ status: CoverageStatus) -> [ReportLine] {
        let warnings = status.notes.filter { $0.severity == .warning }.count
        let notices = status.notes.count - warnings
        let counts = [
            warnings > 0 ? "\(warnings) \(warnings == 1 ? "warning" : "warnings")" : nil,
            notices > 0 ? "\(notices) \(notices == 1 ? "notice" : "notices")" : nil,
        ].compactMap { $0 }.joined(separator: " · ")
        return [
            ReportLine("Coverage: " + counts, style: status.lineStyle),
            ReportLine("Resize for coverage details", style: status.lineStyle),
        ]
    }

    private static func footerLines(
        state: LiveReportState, width: Int, compact: Bool
    ) -> [ReportLine] {
        let diagnosis =
            state.diagnosis.isRunning ? DiagnosisViewState.cleanupHint : DiagnosisViewState.keyHint
        let pause = state.frozen ? "p resume" : "p pause"
        let controls = [
            "↑/↓ select", "←/→ fold", "a show all", ". pin session", "u unpin all", "Enter inspect",
            "c/m CPU/memory order", "i details", "PgUp/PgDn scroll", "v processes",
            diagnosis, pause, "q quit",
        ]
        var lines: [String] = []
        var line = ""
        for control in controls {
            let candidate = line.isEmpty ? control : line + "  " + control
            if TerminalCells.width(candidate) > width {
                if !line.isEmpty { lines.append(line) }
                line = control
            } else {
                line = candidate
            }
        }
        if !line.isEmpty { lines.append(line) }
        if compact {
            lines =
                state.diagnosis.isRunning
                ? [diagnosis, "Resize for all keys | \(pause) | q quit"]
                : ["\(diagnosis) | Resize for all keys", "\(pause) | q quit"]
        }
        return lines.map { ReportLine($0, style: .muted) }
    }

    private struct Columns {
        let width: Int
        let name: Int
        let cpu: Int
        let memory: Int
        let recent: Int
        let now: Int
        let graphical: Bool

        init(width: Int) {
            self.width = width
            graphical = width >= 100
            cpu = graphical ? 13 : (width < 60 ? 6 : 7)
            memory = graphical ? 15 : (width < 60 ? 8 : 9)
            recent = width >= 80 ? 10 : 7
            now = width >= 80 ? 5 : (width < 60 ? 0 : 3)
            name = max(1, width - cpu - memory - recent - now - (now == 0 ? 3 : 4))
        }

        func rows(
            _ label: ContributorLabel, prefix: String, cpu: String, memory: String, recent: String,
            now: String
        ) -> [String] {
            let title = TextReport.safe(label.title)
            let single = row(prefix + title, cpu: cpu, memory: memory, recent: recent, now: now)
            guard TerminalCells.width(prefix + title) > name else { return [single] }
            let heading: String
            let directory: String?
            switch label {
            case .text: return [single]
            case .workload(let executable, let cwd):
                guard cwd != nil else { return [single] }
                heading = TerminalCells.abbreviated(prefix + TextReport.safe(executable), to: width)
                directory = cwd
            case .session(let identity, let listedName, let cwd):
                var text = prefix + TextReport.safe(identity)
                if let listedName, !listedName.isEmpty {
                    let available = width - TerminalCells.width(text) - 3
                    if available > 0 {
                        text += " · " + TerminalCells.abbreviated(TextReport.safe(listedName), to: available)
                    }
                }
                heading = text
                directory = cwd
            }
            let continuation =
                String(repeating: " ", count: TerminalCells.width(prefix))
                + (directory.map(TextReport.safe) ?? "")
            return [heading, row(continuation, cpu: cpu, memory: memory, recent: recent, now: now)]
        }

        func row(_ label: String, cpu: String, memory: String, recent: String, now: String) -> String {
            func numeric(_ value: String, width: Int) -> String {
                let clipped = TerminalCells.abbreviated(TextReport.safe(value), to: width)
                return String(repeating: " ", count: max(0, width - TerminalCells.width(clipped))) + clipped
            }
            return TerminalCells.padded(TerminalCells.abbreviated(TextReport.safe(label), to: name), to: name)
                + " " + numeric(cpu, width: self.cpu) + " " + numeric(memory, width: self.memory)
                + " " + numeric(recent, width: self.recent)
                + (self.now == 0 ? "" : " " + numeric(now, width: self.now))
        }

        func bar(_ fraction: Double) -> String {
            guard graphical else { return "" }
            let filled = min(4, max(0, Int((fraction * 4).rounded())))
            return " " + String(repeating: "▰", count: filled) + String(repeating: "▱", count: 4 - filled)
        }
    }
}

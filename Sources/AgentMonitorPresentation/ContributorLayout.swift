import Foundation

public enum ContributorLayout {
    public static func lines(state: LiveReportState, width: Int, height: Int) -> [ReportLine] {
        let overview = state.overview
        let columns = Columns(width: width)
        let prefix = state.frozen ? "PAUSED · p resume" : "Agent Monitor · p pause"
        var header = [
            ReportLine(prefix + " | Main contributors | v processes", style: .title),
            ReportLine(overview.totals.summary(duration: overview.duration)),
            ReportLine(
                "Agents "
                    + state.history.line(
                        metric: state.historyMetric, window: state.historyWindow, width: max(1, width - 7)),
                style: .muted),
            ReportLine(
                "Recent " + overview.sourceDurationLabel
                    + " · CPU over \(String(format: "%.1f", overview.duration)) s · point candidates",
                style: .muted),
        ]
        let status = overview.coverageStatus
        header.insert(
            contentsOf: TerminalCells.wrapped(status.text, to: width).map {
                ReportLine($0, style: status.lineStyle)
            },
            at: 2)
        if !state.thresholds.isUnfiltered {
            header.append(ReportLine(ThresholdContext.text(state.thresholds), style: .muted))
        }
        header.append(
            ReportLine(
                columns.row(
                    "GROUP / EXECUTABLE / PROCESS", cpu: "CPU", memory: "MEMORY", recent: "RECENT CPU",
                    now: "NOW"), style: .heading))
        let footer = [
            ReportLine("↑/↓ select  ←/→ fold  a show all  . pin session  Enter inspect", style: .muted),
            ReportLine(
                "c/m CPU/memory order  i details  PgUp/PgDn scroll  v processes  p pause  q quit",
                style: .muted),
        ]
        var content: [(ContributorID, ReportLine)] = []
        for row in overview.visibleRows {
            let selected = row.id == overview.selection
            let folded = row.node.children.isEmpty ? "·" : (overview.open.contains(row.id) ? "▾" : "▸")
            let indent = String(repeating: "  ", count: row.depth)
            let pinned = overview.pinned.contains(row.id)
            let marker = pinned ? (selected ? "@" : "+") : (selected ? ">" : " ")
            let label = "\(marker)\(indent)\(folded) \(row.node.title)"
            let stats = row.node.stats
            let cpuBar = columns.bar(overview.cpuMeterFraction(stats))
            let memoryBar = columns.bar(overview.memoryMeterFraction(stats))
            content.append(
                (
                    row.id,
                    ReportLine(
                        columns.row(
                            label, cpu: stats.cpuText(duration: overview.duration) + cpuBar,
                            memory: stats.memoryText + memoryBar, recent: stats.recentCPUText,
                            now: stats.currentAvailable ? String(stats.current.count) : "—"),
                        style: selected ? .selected : .normal)
                ))
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
        let available = max(1, height - header.count - footer.count)
        let selected = content.firstIndex { $0.0 == overview.selection } ?? 0
        let offset = min(
            max(0, selected + overview.detailOffset - available / 2), max(0, content.count - available))
        let result = header + content.dropFirst(offset).prefix(available).map(\.1) + footer
        return Array(result.prefix(height)).map {
            ReportLine(TerminalCells.clipped($0.text, to: width), style: $0.style)
        }
    }

    private struct Columns {
        let name: Int
        let cpu: Int
        let memory: Int
        let recent: Int
        let now: Int
        let graphical: Bool

        init(width: Int) {
            graphical = width >= 100
            cpu = graphical ? 13 : (width < 60 ? 6 : 7)
            memory = graphical ? 15 : (width < 60 ? 8 : 9)
            recent = width >= 80 ? 10 : 7
            now = width >= 80 ? 5 : (width < 60 ? 0 : 3)
            name = max(1, width - cpu - memory - recent - now - (now == 0 ? 3 : 4))
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

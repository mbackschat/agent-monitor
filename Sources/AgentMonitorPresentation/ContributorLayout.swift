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
            ReportLine("PgUp/PgDn details  v processes  p pause/resume  q quit", style: .muted),
        ]
        var content: [(ContributorID, ReportLine)] = []
        for row in overview.visibleRows {
            let selected = row.id == overview.selection
            let folded = overview.open.contains(row.id) ? "▾" : "▸"
            let indent = String(repeating: "  ", count: row.depth)
            let pinned = overview.pinned.contains(row.id)
            let marker = pinned ? (selected ? "@" : "+") : (selected ? ">" : " ")
            let label = "\(marker)\(indent)\(folded) \(row.node.title)"
            let stats = row.node.stats
            let cpuBar = columns.bar(
                overview.totals.currentCPU > 0 ? stats.currentCPU / overview.totals.currentCPU : 0)
            let memoryBar = columns.bar(
                overview.totals.memoryBytes > 0
                    ? Double(stats.memoryBytes) / Double(overview.totals.memoryBytes) : 0)
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
            if overview.open.contains(row.id) {
                let details =
                    [stats.census + " · \(stats.filtered.count) filtered"] + row.node.details
                    + (row.id == .section(.uncertain)
                        ? [
                            overview.coverage,
                            "Bars compare shares of measured CPU/current memory. Session CPU is point evidence. Sampling can miss workers and final exit CPU.",
                        ] : [])
                for detail in details {
                    for line in TerminalCells.wrapped(
                        TextReport.safe(detail), to: max(10, width - indent.count - 2))
                    {
                        content.append((row.id, ReportLine(indent + "  " + line, style: .muted)))
                    }
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

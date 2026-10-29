import Foundation

public enum ContributorLayout {
    public static func lines(state: LiveReportState, width: Int, height: Int) -> [ReportLine] {
        let overview = state.overview
        let columns = Columns(
            width: width, graphs: width >= 90 && height >= 20,
            cpu: max(
                7,
                overview.nodes.values.map {
                    TerminalCells.width($0.stats.cpuText(duration: overview.duration))
                }.max() ?? 0),
            memory: max(
                10, overview.nodes.values.map { TerminalCells.width($0.stats.currentMemoryText) }.max() ?? 0))
        var footer = footerLines(state: state, width: width)
        let status = state.displayCoverageStatus
        let coverage = ReportLine(status.terminalSummary(width: width), style: status.lineStyle)
        let heading = overview.title + (overview.order == .stable ? " · Stable" : "")
        let title = (state.frozen ? "PAUSED · p resume" : "Agent Monitor") + " | " + heading
        var header = [
            ReportLine(
                TerminalCells.width(title) <= width
                    ? title : (state.frozen ? "PAUSED | " : "") + heading,
                style: .title),
            ReportLine(overview.totals.summary(duration: overview.duration)),
            coverage,
            ReportLine(
                "Recent " + overview.activity.intervalLabel + " · CPU " + overview.activity.scaleLabel
                    + " · 100% = one core", style: .muted),
            ReportLine(
                columns.row("CONTRIBUTOR", chart: "CPU HISTORY", cpu: "CPU", memory: "MEMORY"),
                style: .heading),
        ]
        if !state.thresholds.isUnfiltered {
            header.insert(ReportLine(ThresholdContext.text(state.thresholds), style: .muted), at: 3)
        }
        if let notice = overview.pinNotice { header.insert(ReportLine(notice, style: .warning), at: 3) }
        let blocks = overview.visibleRows.map { row -> [ReportLine] in
            let selected = row.id == overview.selection
            let marker = TerminalRowMarker.text(selected: selected, pinned: overview.pinned.contains(row.id))
            let branch = row.node.children.isEmpty ? "·" : (overview.isExpanded(row.id) ? "▾" : "▸")
            let indent = String(repeating: "│  ", count: min(row.depth, max(0, (width - 30) / 3)))
            let prefix = marker + indent + branch + " "
            let headline = TextReport.safe(row.node.label.headline)
            let style: ReportLine.Style = selected ? .selected : .normal
            let cap =
                columns.graphs
                ? "┌"
                    + overview.activity.terminalLane(for: row.id, width: columns.chart - 2, level: 0, rows: 2)
                    + "┐" : ""
            var lines = [
                ReportLine(
                    columns.row(
                        prefix + headline, chart: cap,
                        cpu: row.node.stats.cpuText(duration: overview.duration),
                        memory: row.node.stats.currentMemoryText), style: style)
            ]
            if columns.graphs {
                let lane =
                    "└"
                    + overview.activity.terminalLane(for: row.id, width: columns.chart - 2, level: 1, rows: 2)
                    + "┘"
                let count =
                    row.node.stats.currentAvailable
                    ? "\(row.node.stats.current.count) processes" : "Presence unavailable"
                lines.append(
                    ReportLine(
                        columns.row(
                            String(repeating: " ", count: TerminalCells.width(prefix))
                                + (row.node.label.sessionName ?? count),
                            chart: lane,
                            cpu: overview.activity.samples[row.id]?.contains { $0?.qualified == true } == true
                                ? "~ spans" : "", memory: ""), style: style))
            }
            let count =
                row.node.stats.currentAvailable ? "\(row.node.stats.current.count) procs · " : "Procs — · "
            let populationPrefix: String
            switch row.id {
            case .section, .collapsed, .more: populationPrefix = ""
            default: populationPrefix = columns.graphs ? "" : count
            }
            let context = populationPrefix + overview.workloadContext(for: row.node)
            let inset = String(repeating: " ", count: TerminalCells.width(prefix))
            let contextWidth = max(1, width - TerminalCells.width(inset))
            if !columns.graphs, let name = row.node.label.sessionName {
                lines.append(
                    ReportLine(
                        inset + TerminalCells.abbreviated(TextReport.safe(name), to: contextWidth),
                        style: selected ? .selected : .muted))
            }
            let headingContinuation =
                TerminalCells.width(prefix + headline) > columns.name
                ? [TerminalCells.abbreviated(headline, to: contextWidth)] : []
            let wrapped =
                headingContinuation + TerminalCells.wrapped(TextReport.safe(context), to: contextWidth)
            for (index, text) in wrapped.prefix(2).enumerated() {
                let suffix = index == 1 && wrapped.count > 2 ? "…" : ""
                lines.append(
                    ReportLine(
                        inset
                            + TerminalCells.clipped(
                                text, to: max(1, width - TerminalCells.width(inset) - suffix.count)) + suffix,
                        style: selected ? .selected : .muted))
            }
            return lines
        }
        let selected = overview.visibleRows.firstIndex { $0.id == overview.selection } ?? 0
        let minimumBody = blocks.indices.contains(selected) ? blocks[selected].count : 1
        let essential =
            [coverage]
            + (state.thresholds.isUnfiltered
                ? [] : [ReportLine(ThresholdContext.text(state.thresholds), style: .muted)])
        while header.count + footer.count + minimumBody > height {
            guard let index = header.lastIndex(where: { !essential.contains($0) }) else { break }
            header.remove(at: index)
        }
        let available = max(0, height - header.count - footer.count)
        let proposedDetails =
            overview.detailsVisible ? min(max(0, available - minimumBody), max(3, available / 2)) : 0
        let detailsHeight = proposedDetails >= 2 ? proposedDetails : 0
        if overview.detailsVisible, detailsHeight == 0 {
            footer[0] = ReportLine("Resize for details · Esc close", style: .muted)
        }
        let bodyHeight = available - detailsHeight
        var start = min(selected, max(0, blocks.count - 1))
        var used = blocks.indices.contains(start) ? blocks[start].count : 0
        while start > 0, used + blocks[start - 1].count <= min(bodyHeight, bodyHeight / 2 + minimumBody) {
            start -= 1
            used += blocks[start].count
        }
        var body: [ReportLine] = []
        for block in blocks.dropFirst(start) {
            guard body.count + block.count <= bodyHeight else { break }
            body += block
        }
        while body.count < bodyHeight { body.append(ReportLine("")) }
        let details = detailLines(state: state, width: width, height: detailsHeight)
        return Array((header + body + details + footer).prefix(height)).map {
            ReportLine(TerminalCells.clipped($0.text, to: width), style: $0.style)
        }
    }

    public static func hasDetailPane(state: LiveReportState, width: Int, height: Int) -> Bool {
        lines(state: state, width: width, height: height).contains { $0.text.hasPrefix("DETAILS") }
    }

    public static func maximumDetailOffset(state: LiveReportState, width: Int, height: Int) -> Int {
        // Use the rendered pane allocation so Page Down cannot scroll beyond its last page.
        let rendered = lines(state: state, width: width, height: height)
        guard let start = rendered.firstIndex(where: { $0.text.hasPrefix("DETAILS") }) else { return 0 }
        let bodyHeight = max(1, rendered.count - start - footerLines(state: state, width: width).count - 1)
        return max(0, fields(state: state, width: width).count - bodyHeight)
    }

    private static func fields(state: LiveReportState, width: Int) -> [String] {
        guard let id = state.overview.selection, let node = state.overview.nodes[id] else { return [] }
        return InspectionField.terminalLines(
            node.inspectionFields.filter { $0.kind == .context } + node.populationFields
                + node.inspectionFields.filter { $0.kind == .evidence }, width: width)
    }

    private static func detailLines(state: LiveReportState, width: Int, height: Int) -> [ReportLine] {
        guard height > 0 else { return [] }
        let overview = state.overview
        let title = overview.selection.flatMap { overview.nodes[$0]?.label.headline } ?? ""
        let lines = fields(state: state, width: width)
        let offset = min(overview.detailOffset, max(0, lines.count - height + 1))
        return [
            ReportLine(
                "DETAILS " + (overview.focus == .details ? "● " : "○ ") + title + " · Tab switch · Esc close",
                style: .heading)
        ]
            + lines.dropFirst(offset).prefix(max(0, height - 1)).map { ReportLine($0, style: .muted) }
    }

    private static func footerLines(state: LiveReportState, width: Int) -> [ReportLine] {
        let pause = state.frozen ? "p resume" : "p pause"
        let diagnosis =
            state.diagnosis.isRunning ? DiagnosisViewState.cleanupHint : DiagnosisViewState.keyHint
        if width < 80, state.overview.detailsVisible {
            return [
                ReportLine("Tab focus · Esc close · i details", style: .muted),
                ReportLine("? help | " + pause + " | q quit", style: .muted),
            ]
        }
        if width < 80 {
            return [
                ReportLine("? help | " + diagnosis, style: .muted),
                ReportLine("i details | " + pause + " | q quit", style: .muted),
            ]
        }
        return [
            ReportLine(
                state.overview.detailsVisible
                    ? "Tab rows/details · ↑/↓ scroll · PgUp/PgDn page · Esc close · Enter inspect process"
                    : "↑/↓ select · ←/→ fold · i details · c/m/o sort · . pin · a main/all · v processes",
                style: .muted),
            ReportLine("? help | " + diagnosis + " | " + pause + " | q quit", style: .muted),
        ]
    }

    private struct Columns {
        let graphs: Bool
        let name: Int
        let chart: Int
        let cpu: Int
        let memory: Int
        init(width: Int, graphs: Bool, cpu: Int, memory: Int) {
            self.cpu = cpu
            self.memory = memory
            self.graphs = graphs
            chart = graphs ? min(24, width / 5) : 0
            name = max(1, width - cpu - memory - chart - (graphs ? 3 : 2))
        }
        func row(_ title: String, chart: String, cpu: String, memory: String) -> String {
            func numeric(_ text: String, width: Int) -> String {
                let value = TerminalCells.abbreviated(text, to: width)
                return String(repeating: " ", count: max(0, width - TerminalCells.width(value))) + value
            }
            return TerminalCells.padded(TerminalCells.abbreviated(title, to: name), to: name)
                + (graphs ? " " + TerminalCells.padded(chart, to: self.chart) : "")
                + " " + numeric(cpu, width: self.cpu) + " " + numeric(memory, width: self.memory)
        }
    }
}

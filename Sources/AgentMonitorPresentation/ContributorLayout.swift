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
        let heading =
            (overview.tableCollapsed ? "▸ " : "▾ ") + overview.title
            + (overview.order == .stable ? " · Stable" : "")
        let title = (state.frozen ? "PAUSED · p resume" : "Agent Monitor") + " | " + heading
        var header = [
            ReportLine(
                TerminalCells.width(title) <= width
                    ? title : (state.frozen ? "PAUSED | " : "") + heading,
                style: .title),
            ReportLine(overview.totals.summary(duration: overview.duration)),
            coverage,
            columns.styledRow(
                "Overall CPU · " + overview.activity.scaleLabel,
                chart: overview.activity.terminalLane(width: columns.chart), cpu: "", memory: "",
                style: .normal),
        ]
        if !overview.tableCollapsed {
            let sections = overview.tableSections.map {
                $0.shortcut + (overview.collapsedSections.contains($0) ? "▸ " : "▾ ")
                    + ($0 == .other ? "Other work" : $0.rawValue)
            }.joined(separator: " · ")
            header += [
                ReportLine(sections, style: .heading),
                ReportLine(
                    columns.row("CONTRIBUTOR", chart: "CPU HISTORY", cpu: "CPU", memory: "MEMORY"),
                    style: .heading),
            ]
        }
        if !state.thresholds.isUnfiltered {
            header.insert(ReportLine(ThresholdContext.text(state.thresholds), style: .muted), at: 3)
        }
        if let notice = overview.pinNotice { header.insert(ReportLine(notice, style: .warning), at: 3) }
        let rows = overview.visibleRows
        var ancestorLast: [Bool] = []
        let blocks = rows.enumerated().map { index, row -> [ReportLine] in
            let selected = row.id == overview.selection
            let marker = TerminalRowMarker.text(selected: selected, pinned: overview.pinned.contains(row.id))
            let branch = row.node.children.isEmpty ? "·" : (overview.isExpanded(row.id) ? "▾" : "▸")
            ancestorLast = Array(ancestorLast.prefix(row.depth))
            let depth = min(row.depth, max(0, (width - 30) / 3))
            let ancestors = (1..<max(1, depth)).map { ancestorLast[$0] ? "   " : "│  " }.joined()
            let indent = ancestors + (depth > 0 ? (row.isLastSibling ? "└─ " : "├─ ") : "")
            let prefix = marker + indent + branch + " "
            let hasVisibleChildren = rows.indices.contains(index + 1) && rows[index + 1].depth > row.depth
            let inset =
                "  " + ancestors
                + (depth > 0 ? (row.isLastSibling ? "   " : "│  ") : "")
                + (hasVisibleChildren ? "│ " : "  ")
            ancestorLast.append(row.isLastSibling)
            let headline = TextReport.safe(row.node.label.headline)
            let style: ReportLine.Style = selected ? .selected : .heading
            let cap =
                columns.graphs
                ? "┌"
                    + overview.activity.terminalLane(for: row.id, width: columns.chart - 2, level: 0, rows: 2)
                    + "┐" : ""
            var lines = [
                columns.styledRow(
                    prefix + headline, chart: cap,
                    cpu: row.node.stats.cpuText(duration: overview.duration),
                    memory: row.node.stats.currentMemoryText, style: style)
            ]
            let includesPopulation: Bool
            switch row.id {
            case .session, .executable, .process: includesPopulation = false
            case .section, .provider, .collapsed, .more: includesPopulation = true
            }
            let population =
                row.node.stats.currentAvailable
                ? "\(row.node.stats.current.count) "
                    + (row.node.stats.current.count == 1 ? "process" : "processes")
                : "Presence unavailable"
            if columns.graphs {
                let lane =
                    "└"
                    + overview.activity.terminalLane(for: row.id, width: columns.chart - 2, level: 1, rows: 2)
                    + "┘"
                lines.append(
                    columns.styledRow(
                        inset + (includesPopulation ? "" : population), chart: lane,
                        cpu: overview.activity.samples[row.id]?.contains { $0?.qualified == true } == true
                            ? "~ spans" : "", memory: "", style: .muted, metricStyle: .warning))
            }
            var context: [ReportLine.Run] = []
            if !columns.graphs && !includesPopulation {
                context.append(.init(population + " · ", style: .muted))
            }
            for part in overview.workloadParts(for: row.node) {
                switch part {
                case .executable(let text): context.append(.init(text, style: .heading))
                case .context(let text): context.append(.init(text))
                case .status(let text):
                    if let status = row.node.retainedStatus, !includesPopulation {
                        let compact =
                            row.node.stats.isNoLongerObserved
                            ? "No longer observed"
                            : (row.node.stats.currentAvailable ? "No current members" : status)
                        context.append(.init(" · " + compact, style: .muted))
                    } else {
                        context.append(.init(text, style: .muted))
                    }
                }
            }
            let contextWidth = max(1, width - TerminalCells.width(inset))
            let headingContinuation =
                TerminalCells.width(prefix + headline) > columns.name
                ? [ReportLine(TerminalCells.abbreviated(headline, to: contextWidth), style: .heading)] : []
            let wrapped = headingContinuation + ReportLine(runs: context).wrapped(to: contextWidth)
            for (index, line) in wrapped.prefix(2).enumerated() {
                let suffix = index == 1 && wrapped.count > 2 ? "…" : ""
                lines.append(
                    ReportLine(
                        runs: [.init(inset)]
                            + line.clipped(to: contextWidth - suffix.count).runs + [.init(suffix)]))
            }
            if width >= 80, row.depth == 0,
                index == 0
                    || overview.tableSection(for: rows[index - 1].id) != overview.tableSection(for: row.id)
            {
                let heading = "── " + overview.tableSection(for: row.id).rawValue + " "
                lines.insert(
                    ReportLine(
                        heading
                            + String(
                                repeating: "─",
                                count: max(0, width - TerminalCells.width(heading))), style: .heading), at: 0)
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
            $0.clipped(to: width)
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
            node.inspectionFields.filter { $0.kind == .context }
                + node.populationFields
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
        if state.overview.tableCollapsed {
            return [ReportLine("8 expand · ? help · " + pause + " · q quit", style: .muted)]
        }
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
                    : "↑/↓ select · ←/→ rows · 5/6/7 sections · 8 table · i details",
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
        func styledRow(
            _ title: String, chart: String, cpu: String, memory: String,
            style: ReportLine.Style, metricStyle: ReportLine.Style = .heading
        ) -> ReportLine {
            func numeric(_ text: String, width: Int) -> String {
                let value = TerminalCells.abbreviated(text, to: width)
                return String(repeating: " ", count: max(0, width - TerminalCells.width(value))) + value
            }
            return ReportLine(
                runs: [
                    .init(
                        TerminalCells.padded(TerminalCells.abbreviated(title, to: name), to: name),
                        style: style),
                    .init(graphs ? " " + TerminalCells.padded(chart, to: self.chart) : "", style: .separator),
                    .init(
                        " " + numeric(cpu, width: self.cpu) + " " + numeric(memory, width: self.memory),
                        style: metricStyle),
                ], style: style)
        }

        func row(_ title: String, chart: String, cpu: String, memory: String) -> String {
            styledRow(title, chart: chart, cpu: cpu, memory: memory, style: .normal).text
        }
    }
}

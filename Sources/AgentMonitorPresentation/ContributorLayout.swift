import Foundation

public enum ContributorLayout {
    public static func lines(state: LiveReportState, width: Int, height: Int) -> [ReportLine] {
        layout(state: state, width: width, height: height).lines
    }

    private struct Layout {
        let lines: [ReportLine]
        let blockHeights: [Int]
        let bodyHeight: Int
        let detailsHeight: Int
        /// Index of the DETAILS heading in `lines`; nil when the pane is not rendered.
        let detailsStart: Int?
    }

    private static func layout(state: LiveReportState, width: Int, height: Int) -> Layout {
        let overview = state.overview
        func lane(for id: ContributorID? = nil, level: Int, overall: Bool = false) -> String {
            switch state.chartStyle {
            case .stacked:
                return overview.activity.terminalLane(for: id, width: columns.chart, level: level, rows: 3)
            case .compact:
                guard level == (overall ? 2 : 0) else { return "" }
                return overview.activity.terminalLane(for: id, width: columns.chart)
            }
        }
        let columns = Columns(
            width: width, graphs: width >= 90 && height >= 20, order: overview.order,
            chartStyle: state.chartStyle,
            cpu: max(
                7,
                overview.nodes.values.map {
                    TerminalCells.width($0.stats.cpuText(duration: overview.duration))
                }.max() ?? 0),
            memory: max(
                10, overview.nodes.values.map { TerminalCells.width($0.stats.currentMemoryText) }.max() ?? 0))
        var footer = footerLines(state: state, width: width)
        let totals = overview.totals.summary(duration: overview.duration)
        let chartCaption =
            " · Overall CPU · " + overview.activity.scaleLabel
            + (state.chartStyle == .compact ? " · compact" : "")
        let cadence = TerminalChrome.cadence(state: state).text
        let showsOverallChart =
            columns.graphs
            && TerminalCells.width(totals) <= columns.name
            && TerminalCells.width(cadence + chartCaption) <= columns.name
        let summaryWidth = showsOverallChart ? columns.name : width
        var header = [
            TerminalChrome.title(state: state, width: summaryWidth),
            ReportLine(cadence + (columns.graphs ? chartCaption : "")),
            ReportLine(totals),
        ]
        if !(overview.detailsVisible && state.detailsMode == .maximized) {
            header += [
                columns.styledRow(
                    "CONTRIBUTOR"
                        + (overview.order == .contributor ? (overview.ascending ? " ↑" : " ↓") : ""),
                    chart: "CPU HISTORY",
                    cpu: "CPU" + (overview.order == .cpu ? (overview.ascending ? " ↑" : " ↓") : ""),
                    memory: "MEMORY" + (overview.order == .memory ? (overview.ascending ? " ↑" : " ↓") : ""),
                    style: .heading, accentMetrics: true)
            ]
        }
        if !state.thresholds.isUnfiltered {
            header.insert(ReportLine(ThresholdContext.text(state.thresholds), style: .muted), at: 3)
        }
        if let notice = overview.pinNotice { header.insert(ReportLine(notice, style: .warning), at: 3) }
        let rows = overview.visibleRows
        var ancestorLast: [Bool] = []
        var pendingSections = overview.tableSections
        func sectionHeading(_ section: ContributorTableSection) -> ReportLine {
            let heading =
                "── " + TerminalChrome.sectionKey(section)
                + (overview.collapsedSections.contains(section) ? "▸ " : "▾ ") + section.rawValue + " "
            return ReportLine(
                heading + String(repeating: "─", count: max(0, width - TerminalCells.width(heading))),
                style: .heading)
        }
        var blocks = rows.enumerated().map { index, row -> [ReportLine] in
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
            let style: ReportLine.Style =
                selected
                ? .selected
                : (row.id == .section(.uncertain) ? .warning : .identity)
            let cap =
                columns.graphs
                ? lane(for: row.id, level: 0) : ""
            var lines = [
                columns.styledRow(
                    prefix + headline, chart: cap,
                    cpu: row.node.stats.cpuText(duration: overview.duration),
                    memory: row.node.stats.currentMemoryText, style: style, accentMetrics: true)
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
                lines.append(
                    columns.styledRow(
                        inset + (includesPopulation ? "" : population),
                        chart: lane(for: row.id, level: 1),
                        cpu: overview.activity.samples[row.id]?.contains { $0?.qualified == true } == true
                            ? "~ spans" : "", memory: "", style: .normal, metricStyle: .warning))
            }
            var context: [ReportLine.Run] = []
            if !columns.graphs && !includesPopulation {
                context.append(.init(population + " · "))
            }
            for part in overview.workloadParts(for: row.node) {
                switch part {
                case .executable(let text): context.append(.init(text, style: .identity))
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
            let contextWidth = max(1, (width >= 100 ? columns.name : width) - TerminalCells.width(inset))
            let headingContinuation =
                TerminalCells.width(prefix + headline) > columns.name
                ? [ReportLine(TerminalCells.abbreviated(headline, to: contextWidth), style: .identity)] : []
            let wrapped = headingContinuation + ReportLine(runs: context).wrapped(to: contextWidth)
            let bottom =
                columns.graphs
                ? lane(for: row.id, level: 2) : ""
            if columns.graphs && width < 100 {
                lines.append(columns.styledRow(inset, chart: bottom, cpu: "", memory: "", style: .normal))
            }
            for (index, line) in wrapped.prefix(2).enumerated() {
                let suffix = index == 1 && wrapped.count > 2 ? "…" : ""
                let contextLine = ReportLine(
                    runs: [.init(inset)] + line.clipped(to: contextWidth - suffix.count).runs + [
                        .init(suffix)
                    ])
                if columns.graphs && width >= 100 && index == 0 {
                    lines.append(columns.contextRow(contextLine, chart: bottom))
                } else {
                    lines.append(contextLine)
                }
            }
            if columns.graphs && lines.count < 3 {
                lines.append(columns.styledRow(inset, chart: bottom, cpu: "", memory: "", style: .normal))
            }
            // Only top-level rows open sections; deeper rows would pay a whole-forest search per frame.
            if row.depth == 0,
                let sectionIndex = pendingSections.firstIndex(of: overview.tableSection(for: row.id))
            {
                lines.insert(contentsOf: pendingSections.prefix(sectionIndex + 1).map(sectionHeading), at: 0)
                pendingSections.removeFirst(sectionIndex + 1)
            } else if height >= 20, index > 0, rows[index - 1].depth >= row.depth {
                lines.insert(ReportLine(depth > 0 ? "  " + ancestors + "│" : ""), at: 0)
            }
            return lines
        }
        if !pendingSections.isEmpty {
            let headings = pendingSections.map(sectionHeading)
            if blocks.isEmpty { blocks = [headings] } else { blocks[blocks.count - 1] += headings }
        }
        let selected = overview.visibleRows.firstIndex { $0.id == overview.selection } ?? 0
        let minimumBody = blocks.indices.contains(selected) ? blocks[selected].count : 1
        let essential =
            state.thresholds.isUnfiltered
            ? [] : [ReportLine(ThresholdContext.text(state.thresholds), style: .muted)]
        while header.count + footer.count + minimumBody > height {
            guard let index = header.lastIndex(where: { !essential.contains($0) }) else { break }
            header.remove(at: index)
        }
        let available = max(0, height - header.count - footer.count)
        let proposedDetails =
            overview.detailsVisible
            ? (state.detailsMode == .maximized
                ? available
                : min(max(0, available - minimumBody), max(3, available * state.detailsPercent / 100))) : 0
        let detailsHeight = proposedDetails >= 2 ? proposedDetails : 0
        if overview.detailsVisible, detailsHeight == 0 {
            footer[0] = ReportLine("Resize for details · Esc close", style: .muted)
        }
        let bodyHeight = available - detailsHeight
        var start = min(selected, max(0, blocks.count - 1))
        var used = blocks.indices.contains(start) ? blocks[start].count : 0
        while start > 0, used + blocks[start - 1].count <= bodyHeight {
            start -= 1
            used += blocks[start].count
        }
        var body: [ReportLine] = []
        var visibleCount = 0
        var partialLastRow = false
        for block in blocks.dropFirst(start) {
            let remaining = bodyHeight - body.count
            guard remaining > 0 else { break }
            let visible = block.prefix(remaining)
            if visible.count < block.count {
                guard
                    visible.contains(where: {
                        $0.style == .selected || $0.style == .identity || $0.style == .warning
                    })
                else { break }
                partialLastRow = true
            }
            body += visible
            visibleCount += 1
            if partialLastRow { break }
        }
        while body.count < bodyHeight { body.append(ReportLine("")) }
        let details = detailLines(state: state, width: width, height: detailsHeight)
        var position =
            bodyHeight > 0
            ? TerminalChrome.position(start: start, count: min(visibleCount, rows.count), total: rows.count)
            : ""
        if partialLastRow {
            position =
                (start > 0 ? "↑ " : "")
                + "\(start + 1)–\(min(start + visibleCount, rows.count))/\(rows.count) ↓"
        }
        if !position.isEmpty, !header.isEmpty {
            let index = 0
            let suffix = "  " + position
            header[index] = ReportLine(
                runs: header[index].clipped(to: max(0, summaryWidth - suffix.count)).runs + [
                    .init(suffix, style: .heading)
                ])
        }
        if !position.isEmpty, header.isEmpty, !footer.isEmpty {
            footer[0] = ReportLine(
                TerminalCells.abbreviated(footer[0].text, to: max(1, width - position.count - 2)) + "  "
                    + position)
        }
        let rendersOverallChart = showsOverallChart && header.count >= 3
        if rendersOverallChart {
            for level in 0..<3 {
                header[level] = columns.contextRow(
                    header[level],
                    chart: lane(level: level, overall: true))
            }
        }
        if columns.graphs, visibleCount > 0 || rendersOverallChart {
            footer = TerminalChrome.withChartLegend(footer, width: width)
        }
        let detailsIndex = header.count + body.count
        return Layout(
            lines: Array((header + body + details + footer).prefix(height)).map { $0.clipped(to: width) },
            blockHeights: blocks.map(\.count), bodyHeight: bodyHeight, detailsHeight: detailsHeight,
            detailsStart: details.isEmpty || detailsIndex >= height ? nil : detailsIndex)
    }

    public static func page(state: inout LiveReportState, width: Int, height: Int, direction: Int, half: Bool)
    {
        let layout = layout(state: state, width: width, height: height)
        if state.overview.detailsVisible && state.overview.focus == .details && layout.detailsHeight > 1 {
            let step = max(1, (layout.detailsHeight - 1) / (half ? 2 : 1))
            state.overview.scroll(
                by: direction * step, maximum: maximumDetailOffset(state: state, width: width, height: height)
            )
            return
        }
        let rows = state.overview.visibleRows
        guard let selected = rows.firstIndex(where: { $0.id == state.overview.selection }) else { return }
        let target = max(1, layout.bodyHeight / (half ? 2 : 1))
        var index = selected
        var traversed = 0
        while rows.indices.contains(index + direction) {
            index += direction
            traversed += layout.blockHeights[index]
            if traversed >= target { break }
        }
        state.overview.move(by: index - selected)
    }

    public static func hasDetailPane(state: LiveReportState, width: Int, height: Int) -> Bool {
        layout(state: state, width: width, height: height).detailsStart != nil
    }

    public static func maximumDetailOffset(state: LiveReportState, width: Int, height: Int) -> Int {
        // Use the rendered pane allocation so Page Down cannot scroll beyond its last page.
        let rendered = layout(state: state, width: width, height: height)
        guard let start = rendered.detailsStart else { return 0 }
        let bodyHeight = max(
            1, rendered.lines.count - start - footerLines(state: state, width: width).count - 1)
        return max(0, fields(state: state, width: width).count - bodyHeight)
    }

    private static func fields(state: LiveReportState, width: Int) -> [ReportLine] {
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
        let count = min(lines.count - offset, max(0, height - 1))
        let position = TerminalChrome.position(start: offset, count: count, total: lines.count)
        let heading =
            "DETAILS " + (overview.focus == .details ? "● " : "○ ") + title
            + (state.detailsMode == .maximized ? " · max" : " · \(state.detailsPercent)%")
        let suffix = position.isEmpty ? "" : " · " + position
        var result =
            [
                ReportLine(
                    TerminalCells.abbreviated(heading, to: max(1, width - suffix.count)) + suffix,
                    style: .heading)
            ]
            + lines.dropFirst(offset).prefix(max(0, height - 1))
        result += Array(repeating: ReportLine(""), count: max(0, height - result.count))
        return result
    }

    private static func footerLines(state: LiveReportState, width: Int) -> [ReportLine] {
        TerminalChrome.footer(state: state, width: width)
    }

    private struct Columns {
        let graphs: Bool
        let order: ContributorOrder
        let chartStyle: ContributorChartStyle
        let name: Int
        let chart: Int
        let cpu: Int
        let memory: Int
        init(
            width: Int, graphs: Bool, order: ContributorOrder, chartStyle: ContributorChartStyle, cpu: Int,
            memory: Int
        ) {
            self.order = order
            self.chartStyle = chartStyle
            self.cpu = cpu
            self.memory = memory
            self.graphs = graphs
            chart = graphs ? min(24, width / 5) : 0
            name = max(1, width - cpu - memory - chart - (graphs ? 3 : 2))
        }
        func chartRuns(_ chart: String) -> [ReportLine.Run] {
            guard graphs else { return [] }
            var runs = [ReportLine.Run(" ", style: .separator)]
            var text = ""
            var style: ReportLine.Style = .separator
            for glyph in TerminalCells.padded(chart, to: self.chart) {
                let next: ReportLine.Style = glyph == "█" && chartStyle == .stacked ? .chartFill : .separator
                if next != style && !text.isEmpty {
                    runs.append(.init(text, style: style))
                    text = ""
                }
                style = next
                text.append(glyph)
            }
            if !text.isEmpty { runs.append(.init(text, style: style)) }
            return runs
        }

        func contextRow(_ line: ReportLine, chart: String) -> ReportLine {
            let content = line.clipped(to: name)
            return ReportLine(
                runs: content.runs + [
                    .init(String(repeating: " ", count: max(0, name - TerminalCells.width(content.text))))
                ] + chartRuns(chart))
        }

        func styledRow(
            _ title: String, chart: String, cpu: String, memory: String,
            style: ReportLine.Style, metricStyle: ReportLine.Style = .heading, accentMetrics: Bool = false
        ) -> ReportLine {
            func numeric(_ text: String, width: Int) -> String {
                let value = TerminalCells.abbreviated(text, to: width)
                return String(repeating: " ", count: max(0, width - TerminalCells.width(value))) + value
            }
            return ReportLine(
                runs: [
                    .init(
                        TerminalCells.padded(TerminalCells.abbreviated(title, to: name), to: name),
                        style: style)
                ] + chartRuns(chart) + [
                    .init(
                        " " + numeric(cpu, width: self.cpu),
                        style: style == .selected
                            ? .selected
                            : (accentMetrics && order == .cpu && cpu != "—" ? .metric : metricStyle)),
                    .init(
                        " " + numeric(memory, width: self.memory),
                        style: style == .selected
                            ? .selected
                            : (accentMetrics && order == .memory && memory != "—" ? .metric : metricStyle)),
                ], style: style)
        }

    }
}

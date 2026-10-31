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
    }

    private static func layout(state: LiveReportState, width: Int, height: Int) -> Layout {
        let overview = state.overview
        let columns = Columns(
            width: width, graphs: width >= 90 && height >= 20, order: overview.order,
            cpu: max(
                7,
                overview.nodes.values.map {
                    TerminalCells.width($0.stats.cpuText(duration: overview.duration))
                }.max() ?? 0),
            memory: max(
                10, overview.nodes.values.map { TerminalCells.width($0.stats.currentMemoryText) }.max() ?? 0))
        var footer = footerLines(state: state, width: width)
        var header = [
            TerminalChrome.title(state: state, width: width),
            TerminalChrome.cadence(state: state),
            ReportLine(overview.totals.summary(duration: overview.duration)),
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
                columns.styledRow(
                    "CONTRIBUTOR"
                        + (overview.order == .contributor ? (overview.ascending ? " ↑" : " ↓") : ""),
                    chart: "CPU HISTORY",
                    cpu: "CPU" + (overview.order == .cpu ? (overview.ascending ? " ↑" : " ↓") : ""),
                    memory: "MEMORY" + (overview.order == .memory ? (overview.ascending ? " ↑" : " ↓") : ""),
                    style: .heading, accentMetrics: true),
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
            let style: ReportLine.Style =
                selected
                ? .selected
                : (row.id == .section(.uncertain) ? .warning : .identity)
            let cap =
                columns.graphs
                ? overview.activity.terminalLane(for: row.id, width: columns.chart) : ""
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
                        inset + (includesPopulation ? "" : population), chart: "",
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
            } else if height >= 20, index > 0, rows[index - 1].depth >= row.depth {
                lines.insert(ReportLine(depth > 0 ? "  " + ancestors + "│" : ""), at: 0)
            }
            return lines
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
        var visibleCount = 0
        for block in blocks.dropFirst(start) {
            guard body.count + block.count <= bodyHeight else { break }
            body += block
            visibleCount += 1
        }
        while body.count < bodyHeight { body.append(ReportLine("")) }
        let details = detailLines(state: state, width: width, height: detailsHeight)
        let position = TerminalChrome.position(start: start, count: visibleCount, total: blocks.count)
        if !position.isEmpty, !header.isEmpty {
            let index = 0
            let suffix = "  " + position
            header[index] = ReportLine(
                runs: header[index].clipped(to: max(0, width - suffix.count)).runs + [
                    .init(suffix, style: .heading)
                ])
        }
        if !position.isEmpty, header.isEmpty, !footer.isEmpty {
            footer[0] = ReportLine(
                TerminalCells.abbreviated(footer[0].text, to: max(1, width - position.count - 2)) + "  "
                    + position)
        }
        return Layout(
            lines: Array((header + body + details + footer).prefix(height)).map { $0.clipped(to: width) },
            blockHeights: blocks.map(\.count), bodyHeight: bodyHeight, detailsHeight: detailsHeight)
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
        lines(state: state, width: width, height: height).contains { $0.text.hasPrefix("DETAILS") }
    }

    public static func maximumDetailOffset(state: LiveReportState, width: Int, height: Int) -> Int {
        // Use the rendered pane allocation so Page Down cannot scroll beyond its last page.
        let rendered = lines(state: state, width: width, height: height)
        guard let start = rendered.firstIndex(where: { $0.text.hasPrefix("DETAILS") }) else { return 0 }
        let bodyHeight = max(1, rendered.count - start - footerLines(state: state, width: width).count - 1)
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
        let heading = "DETAILS " + (overview.focus == .details ? "● " : "○ ") + title
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
        let name: Int
        let chart: Int
        let cpu: Int
        let memory: Int
        init(width: Int, graphs: Bool, order: ContributorOrder, cpu: Int, memory: Int) {
            self.order = order
            self.cpu = cpu
            self.memory = memory
            self.graphs = graphs
            chart = graphs ? min(24, width / 5) : 0
            name = max(1, width - cpu - memory - chart - (graphs ? 3 : 2))
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
                        style: style),
                    .init(graphs ? " " + TerminalCells.padded(chart, to: self.chart) : "", style: .separator),
                    .init(
                        " " + numeric(cpu, width: self.cpu),
                        style: accentMetrics && order == .cpu && cpu != "—" ? .metric : metricStyle),
                    .init(
                        " " + numeric(memory, width: self.memory),
                        style: accentMetrics && order == .memory && memory != "—" ? .metric : metricStyle),
                ], style: style)
        }

    }
}

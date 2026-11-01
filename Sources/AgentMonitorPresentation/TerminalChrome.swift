import Foundation

/// Shared report orientation and controls keep view changes recognizable.
public enum TerminalChrome {
    public static func title(state: LiveReportState, width: Int) -> ReportLine {
        let order: String
        if state.showsOverview {
            switch state.overview.order {
            case .cpu: order = "CPU"
            case .memory: order = "Memory"
            case .contributor: order = "Contributor"
            case .stable: order = "Stable"
            }
        } else {
            order = state.sortKey == .memory ? "Memory" : state.sortKey.rawValue
        }
        let stable = state.showsOverview ? state.overview.order == .stable : state.sortKey == .stable
        let ascending = state.showsOverview ? state.overview.ascending : state.ascending
        let sort = order + (stable ? "" : ascending ? " ↑" : " ↓")
        let view = state.title(for: state.view)
        let prefix = state.frozen ? "PAUSED" : "Agent Monitor"
        let full = prefix + " | " + sort + " | " + view
        let compact = (state.frozen ? "PAUSED | " : "") + sort + " | " + view
        return ReportLine(
            TerminalCells.abbreviated(TerminalCells.width(full) <= width ? full : compact, to: width),
            style: .title)
    }

    public static func cadence(state: LiveReportState) -> ReportLine {
        let seconds = String(format: "%g", state.interval)
        let acquisition =
            state.samplingSettings.enabled
            ? "acquire max \(seconds) s"
            : state.snapshot?.window == nil ? "every \(seconds) s" : "acquire \(seconds) s"
        return ReportLine(
            acquisition
                + " · display \(String(format: "%g", LiveReportState.displayIntervalSeconds)) s · Updates: \(state.updates)",
            style: .muted
        )
    }

    public static func shortcut(for key: String) -> ReportShortcut? {
        switch key {
        case "U": .unpinAll
        case "u", "d": nil
        case "P": .foldPinned
        case "S": .foldSessions
        case "O": .foldOther
        case "5", "6", "7", "8": nil
        default: ReportShortcut(rawValue: key)
        }
    }

    public static func sectionKey(_ section: ContributorTableSection) -> String {
        switch section {
        case .pinned: "P"
        case .sessions: "S"
        case .other: "O"
        }
    }

    public static func controls(
        _ items: [(String, String)], keyStyle: ReportLine.Style = .normal
    ) -> ReportLine {
        var runs: [ReportLine.Run] = []
        for (index, item) in items.enumerated() {
            if index > 0 { runs.append(.init(" · ")) }
            runs += [.init(item.0, style: keyStyle), .init(" " + item.1)]
        }
        return ReportLine(runs: runs)
    }

    public static func footer(state: LiveReportState, width: Int) -> [ReportLine] {
        let details = state.showsOverview ? state.overview.detailsVisible : state.detailsMode != .minimized
        func fitting(_ required: [(String, String)], _ optional: [(String, String)]) -> ReportLine {
            var items = required
            for item in optional where TerminalCells.width(controls(items + [item]).text) <= width {
                items.append(item)
            }
            return footerHint(controls(items))
        }
        let views =
            details
            ? [("v", "view"), ("g", "group"), ("-/+", "size"), (state.showsOverview ? "Esc" : "i", "close")]
            : [("v", "view"), ("g", "group"), ("i", "details")]
        let navigation =
            details
            ? [("u/d", "½ page"), ("M", "max"), ("=", "restore")]
                + (state.showsOverview ? [("Tab", "focus")] : [])
            : [("↑/↓", "select"), ("←/→", "fold"), ("u/d", "½ page"), ("Space", "down")]
        let status = state.displayCoverageStatus
        let diagnostics =
            width < 60 && status.severity != nil
            ? (status.severity == .warning ? "!" : "•")
            : (width < 80 ? "diag" : "diagnostics")
                + (status.severity == .warning ? " !" : status.severity == .notice ? " •" : "")
        return [
            rule(width: width),
            fitting(views, navigation + [("c/m/o", "sort"), ("r", "reverse")]),
            fitting(
                [("?", "help"), ("p", state.frozen ? "resume" : "pause"), ("q/Ctrl-C", "quit")],
                [("D", diagnostics)]
                    + (state.diagnosis.isRunning ? [("", "CPU cleanup")] : [("I", "investigate")])
                    + [("G", "glossary")]),
        ]
    }

    static func withChartLegend(_ footer: [ReportLine], width: Int) -> [ReportLine] {
        let legend = [
            ReportLine(runs: [.init("█", style: .chartOverflow), .init("  above chart range", style: .muted)]
            ),
            ReportLine("·  no measurement", style: .muted),
            ReportLine("_  measured zero", style: .muted),
        ]
        let legendWidth = legend.map { TerminalCells.width($0.text) }.max() ?? 0
        let column = width - legendWidth
        let startsWithRule = footer.first?.text.allSatisfy { $0 == "─" } == true
        guard footer.count == legend.count,
            footer.enumerated().allSatisfy({ index, line in
                (index == 0 && startsWithRule) || TerminalCells.width(line.text) + 3 <= column
            })
        else { return footer }
        return zip(footer, legend).enumerated().map { index, pair in
            let (line, label) = pair
            let content = index == 0 && startsWithRule ? rule(width: column - 3) : line
            return ReportLine(
                runs: content.runs + [
                    .init(String(repeating: " ", count: column - TerminalCells.width(content.text)))
                ] + label.runs + [
                    .init(String(repeating: " ", count: legendWidth - TerminalCells.width(label.text)))
                ])
        }
    }

    public static func footerHint(_ line: ReportLine) -> ReportLine {
        ReportLine(runs: line.runs.map { .init($0.text, style: $0.style == .normal ? .muted : $0.style) })
    }

    public static func rule(width: Int) -> ReportLine {
        ReportLine(String(repeating: "─", count: max(0, width)), style: .muted)
    }

    public static func position(start: Int, count: Int, total: Int) -> String {
        guard total > count else { return "" }
        return (start > 0 ? "↑ " : "") + "\(start + 1)–\(min(total, start + count))/\(total)"
            + (start + count < total ? " ↓" : "")
    }
}

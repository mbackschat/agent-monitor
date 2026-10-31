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
                + " · display \(String(format: "%g", LiveReportState.displayIntervalSeconds)) s · Updates: \(state.updates)"
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
        var lines: [ReportLine] = []
        if width >= 80 {
            var navigation =
                details
                ? [("u/d", "½ page"), ("-", "smaller"), ("+", "larger")]
                : [("↑/↓", "select"), ("←/→", "fold"), ("u/d", "½ page"), ("Space", "down")]
            if details {
                if state.showsOverview { navigation += [("Tab", "focus"), ("Esc", "close")] }
                if !state.showsOverview || width >= 120 {
                    navigation += [("M", "maximize"), ("=", "restore")]
                }
            }
            lines.append(controls(navigation))
        }
        var views = [("v", "view"), ("g", "group"), ("i", "details")]
        if width >= 80 { views += [("c/m/o", "sort"), ("r", "reverse")] }
        if state.showsOverview && width >= 120 { views.append(("P/S/O", "fold sections")) }
        if width < 80 && details {
            views = [
                ("v", "view"), ("g", "group"), ("-/+", "size"), (state.showsOverview ? "Esc" : "i", "close"),
            ]
        }
        lines.append(controls(views))
        let status = state.displayCoverageStatus
        var reference = controls([("?", "help"), ("D", "diagnostics")]).runs
        if let severity = status.severity {
            reference.append(
                .init(severity == .warning ? " !" : " •", style: severity == .warning ? .warning : .identity))
        }
        if width >= 120 { reference += [.init(" · ")] + controls([("G", "glossary")]).runs }
        if width >= 80 {
            reference +=
                [.init(" · ")]
                + controls([("p", state.frozen ? "resume" : "pause"), ("q/Ctrl-C", "quit")]).runs
            lines.append(ReportLine(runs: reference))
        } else {
            reference +=
                [.init(" · ")]
                + (state.diagnosis.isRunning ? [.init("CPU cleanup")] : controls([("I", "investigate")]).runs)
            lines.append(ReportLine(runs: reference))
            lines.append(controls([("p", state.frozen ? "resume" : "pause"), ("q/Ctrl-C", "quit")]))
        }
        if width >= 80 && width < 120 {
            lines[1] = ReportLine(
                runs: lines[1].runs + [.init(" · ")]
                    + (state.diagnosis.isRunning
                        ? [.init("CPU cleanup")] : controls([("I", "investigate")]).runs))
        } else if width >= 120 {
            let last = lines.count - 1
            let hint =
                state.diagnosis.isRunning ? ReportLine("CPU cleanup") : controls([("I", "investigate")])
            lines[last] = ReportLine(runs: hint.runs + [.init(" · ")] + lines[last].runs)
        }
        return lines
    }

    public static func position(start: Int, count: Int, total: Int) -> String {
        guard total > count else { return "" }
        return (start > 0 ? "↑ " : "") + "\(start + 1)–\(min(total, start + count))/\(total)"
            + (start + count < total ? " ↓" : "")
    }

    public static let chartLegend = "↑ above range; · no measurement; _ measured zero"
}

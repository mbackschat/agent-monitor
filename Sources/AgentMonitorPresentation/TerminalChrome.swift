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
        let view =
            (state.showsOverview ? (state.overview.tableCollapsed ? "▸ " : "▾ ") : "")
            + state.title(for: state.view)
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

    public static func footer(state: LiveReportState, width: Int) -> [ReportLine] {
        let pause = state.frozen ? "p resume" : "p pause"
        let status = state.displayCoverageStatus
        let diagnostics =
            "D diagnostics" + (status.severity == .warning ? " !" : status.severity == .notice ? " •" : "")
        let navigation: String
        if state.showsOverview && state.overview.detailsVisible {
            navigation = "Tab rows/details · Esc close · Space/Shift-Space ½ page · PgUp/Dn page"
        } else {
            navigation = "↑/↓ select · ←/→ fold · Space/Shift-Space ½ page · PgUp/Dn page"
        }
        var lines: [ReportLine] = []
        if width >= 80 { lines.append(ReportLine(navigation)) }
        var views = "v view · g group · i details"
        if width >= 80 { views += " · c/m/o sort · r reverse" }
        if state.showsOverview && width >= 120 {
            views += state.overview.tableCollapsed ? " · 8 expand" : " · 5/6/7 sections · 8 table"
        } else if state.showsOverview && state.overview.tableCollapsed {
            views = "8 expand · v view · g group"
        }
        if width < 80 && state.showsOverview && state.overview.detailsVisible {
            views = "Tab focus · Esc close · v view · g group"
        }
        if width >= 80 && width < 120 {
            views += " · " + (state.diagnosis.isRunning ? "CPU cleanup" : DiagnosisViewState.keyHint)
        }
        lines.append(ReportLine(views))
        let help = "? help · " + diagnostics
        if width >= 120 {
            lines.append(
                ReportLine(runs: [
                    .init(help, style: status.severity == .warning ? .warning : .normal),
                    .init(
                        " · G glossary · "
                            + (state.diagnosis.isRunning
                                ? DiagnosisViewState.cleanupHint : DiagnosisViewState.keyHint)),
                    .init(" · " + pause + " · q/Ctrl-C quit"),
                ]))
        } else if width >= 80 {
            lines.append(
                ReportLine(runs: [
                    .init(help, style: status.severity == .warning ? .warning : .normal),
                    .init(" · " + pause + " · q/Ctrl-C quit"),
                ]))
        } else {
            lines.append(
                ReportLine(
                    help + " · " + (state.diagnosis.isRunning ? "CPU cleanup" : "d diagnosis"),
                    style: status.severity == .warning ? .warning : .normal))
            lines.append(ReportLine(pause + " · q/Ctrl-C quit"))
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

import AgentMonitorCore

public enum ReportReferencePage: Equatable, Sendable {
    case glossary, diagnostics, keyboard

    public var title: String {
        switch self {
        case .glossary: "Help & glossary"
        case .diagnostics: "Diagnostics"
        case .keyboard: "Keyboard shortcuts"
        }
    }
}

public enum ReportReferenceLayout {
    public static func content(state: LiveReportState, page: ReportReferencePage) -> [ReportLine] {
        switch page {
        case .glossary:
            return ReportGlossary.entries.flatMap {
                [ReportLine($0.title, style: .title), ReportLine($0.definition), ReportLine("")]
            } + chartHelp()
        case .keyboard:
            return keyboardHelp(state: state)
        case .diagnostics:
            let status = state.displayCoverageStatus
            var lines = [
                ReportLine(
                    state.frozen ? "Paused report diagnostics" : "Displayed report diagnostics",
                    style: .heading),
                ReportLine(CPUContext.text(state.snapshot?.cpuAccounting)),
                ReportLine(ProviderRuntimeAvailability.sessionListingUnavailableReason, style: .muted),
                ReportLine(ProviderRuntimeAvailability.messagingUnavailableReason, style: .muted),
            ]
            if state.showsOverview {
                lines += [
                    ReportLine(state.overview.census), ReportLine(state.overview.coverage),
                ]
            }
            lines += [ReportLine(""), ReportLine("Coverage", style: .heading)]
            if status.notes.isEmpty {
                lines.append(ReportLine(CoverageStatus.clearText, style: .muted))
            } else {
                for note in status.notes {
                    lines += [
                        ReportLine(note.text, style: note.severity == .warning ? .warning : .heading),
                        ReportLine(note.help), ReportLine(""),
                    ]
                }
            }
            if let summary = state.displaySamplingCoverage {
                lines += [ReportLine(summary.scanLabel, style: .heading)]
                for metric in summary.metrics + summary.events {
                    lines += [
                        ReportLine(runs: [
                            .init(metric.title + ": ", style: .identity),
                            .init(metric.value, style: metric.warning ? .warning : .metric),
                        ]),
                        ReportLine(metric.help),
                    ]
                }
                if summary.inspection.mode != .disabled {
                    let inspection = summary.inspection
                    lines += [
                        ReportLine("Between-scan reads · " + inspection.mode.rawValue, style: .heading),
                        ReportLine(
                            "Opportunities: \(inspection.opportunitiesTaken) taken · \(inspection.opportunitiesSkipped) skipped"
                        ),
                        ReportLine("Enumeration failures: \(inspection.enumerationFailures)"),
                        ReportLine(
                            "Candidates: \(inspection.candidatesRead) read · \(inspection.candidatesFailed) failed · \(inspection.candidatesLeftUnread) left unread"
                        ),
                        ReportLine(
                            "Held readings: \(inspection.carriedObservations) carried · \(inspection.supersededReadings) superseded · \(inspection.droppedReadings) dropped · \(inspection.discardedReadings) discarded"
                        ),
                        ReportLine(
                            "Maximum complete-scan lateness: \(ReportNumber.text(inspection.maximumCompleteScanLateness * 1_000)) ms"
                        ),
                    ]
                }
            }
            return lines + [ReportLine(""), ReportLine(SamplingCoverageSummary.interpretation)]
        }
    }

    private static func keyboardHelp(state: LiveReportState) -> [ReportLine] {
        func key(_ key: String, _ action: String) -> ReportLine {
            TerminalChrome.controls([(key, action)], keyStyle: .shortcut)
        }
        var lines = [
            ReportLine("Navigation", style: .title),
            key("u / d", "half-page up / down"),
            key("Space", "half-page down"),
            key("Ctrl-U / Ctrl-D", "half-page up / down"),
            key("PgUp / PgDn", "full-page up / down"),
            key(
                "↑/↓",
                state.showsOverview && state.overview.focus == .details ? "scroll Details" : "select row"),
            key("←/→", "collapse / expand row"),
        ]
        if state.showsOverview {
            lines += [ReportLine(""), ReportLine("Sections", style: .title)]
            for section in state.overview.tableSections {
                lines.append(key(TerminalChrome.sectionKey(section), "fold " + section.rawValue))
            }
        } else if state.grouping == .session {
            lines.append(key("Shift+←/→", "collapse / expand session groups"))
        }
        let details = state.showsOverview ? state.overview.detailsVisible : state.detailsMode != .minimized
        lines += [
            ReportLine(""), ReportLine("Details", style: .title),
            key("i", "show/hide " + (state.showsOverview ? "contributor details" : "details")),
            key("Enter", "show details"),
            key("- / +", "smaller / larger"),
            key("M", "maximize"), key("=", "restore split"),
        ]
        if details {
            if state.showsOverview { lines.append(key("Tab", "switch rows / Details")) }
            lines += [key("[/]", "scroll one line")]
            if state.showsOverview { lines.append(key("Esc", "close Details")) }
        }
        if state.commandInspectionTarget != nil { lines.append(key("x", "read/hide full arguments")) }
        lines += [ReportLine(""), ReportLine("View & sorting", style: .title)]
        if state.canSelectOverview { lines.append(key("v", "switch contributors / processes")) }
        lines += [key("g", "toggle process grouping"), key("c / m / o", "sort CPU / memory / stable")]
        if !state.showsOverview { lines.append(key("n", "sort by PID")) }
        if state.showsOverview ? state.overview.order != .stable : state.sortKey != .stable {
            lines.append(key("r", "reverse sort direction"))
        }
        if state.showsOverview {
            lines += [key("a", "main / all contributors"), key("b", "CPU chart range")]
        } else {
            lines += [key("h", "history metric"), key("t", "history time range")]
        }
        lines += [
            ReportLine(""), ReportLine("Filters & updates", style: .title),
            key("1 / 2", "lower/raise CPU filter"), key("3 / 4", "lower/raise memory filter"),
            key("< / >", "slower/faster sampling"),
        ]
        if state.snapshot != nil { lines.append(key("p", state.frozen ? "resume updates" : "pause updates")) }
        if state.showsOverview {
            if let id = state.overview.selection, state.overview.pinTarget(for: id) != nil {
                lines.append(key(".", "pin/unpin session"))
            }
        } else if state.selection != nil {
            lines.append(key(".", "pin/unpin row"))
        }
        if state.hasPins { lines.append(key("U", "unpin all")) }
        if !state.showsOverview {
            if let row = state.rows.first(where: { $0.process == state.selected }), !row.isHistorical {
                lines.append(key("k", "review termination"))
            }
            var preview = state
            if case .focus(let target) = preview.beginAction(.focus),
                !target.isHistorical, target.attribution.runtime != nil,
                case .terminal = target.attribution.context
            {
                lines.append(key("f", "show session terminal"))
            }
        }
        lines += [
            ReportLine(""), ReportLine("Help & investigation", style: .title),
            key("?", "keyboard shortcuts"), key("G", "glossary"), key("D", "diagnostics"),
            ReportLine(runs: [
                .init("!", style: .warning), .init(" measurement warnings · "), .init("•", style: .identity),
                .init(" notices"),
            ]),
            key("q / Ctrl-C", "quit"),
        ]
        if !state.diagnosis.isRunning { lines.append(key("I", "start CPU investigation")) }
        return lines + chartHelp(keyStyle: .shortcut)
    }

    private static func chartHelp(keyStyle: ReportLine.Style = .normal) -> [ReportLine] {
        [
            ReportLine(""), ReportLine("Contributor CPU charts", style: .title),
            ReportLine(runs: [
                .init("↑", style: .warning), .init(" above range; "), .init("·", style: .identity),
                .init(" no measurement; "), .init("_", style: .identity), .init(" measured zero"),
            ]),
            ReportLine("↑ is above the ceiling, not a rising trend."),
            TerminalChrome.controls([("b", "change chart range")], keyStyle: keyStyle),
            ReportLine("Oldest left, newest right. Dots are gaps, never zero CPU."),
            ReportLine("Bars show retained interval averages; equal widths can cover unequal durations."),
            ReportLine("~ spans marks measurements crossing gaps in sampling."),
        ]
    }

    private static func wrapped(state: LiveReportState, page: ReportReferencePage, width: Int) -> [ReportLine]
    {
        content(state: state, page: page).flatMap { line in
            line.wrapped(to: max(1, width))
        }
    }

    public static func maximumOffset(state: LiveReportState, width: Int, height: Int) -> Int {
        guard let page = state.referencePage else { return 0 }
        return max(0, wrapped(state: state, page: page, width: width).count - max(1, height - 4))
    }

    public static func lines(state: LiveReportState, width: Int, height: Int) -> [ReportLine] {
        guard let page = state.referencePage, width > 0, height > 0 else { return [] }
        if width < 40 || height < 8 {
            return [
                ReportLine(page.title, style: .title), ReportLine("Resize to 40x8 or larger"),
                TerminalChrome.controls([("Esc", "back"), ("q/Ctrl-C", "quit")]),
            ]
            .prefix(height).map { $0.clipped(to: width) }
        }
        let content = wrapped(state: state, page: page, width: width)
        let capacity = height - 4
        let offset = min(max(0, state.referenceOffset), max(0, content.count - capacity))
        let position = TerminalChrome.position(
            start: offset, count: min(capacity, content.count), total: content.count)
        var lines =
            [ReportLine(page.title + (position.isEmpty ? "" : " · " + position), style: .title)]
            + content.dropFirst(offset).prefix(capacity)
        lines += Array(repeating: ReportLine(""), count: max(0, height - 3 - lines.count))
        let navigation = TerminalChrome.controls([("u/d", "½ page"), ("PgUp/Dn", "page")])
        let destinations = TerminalChrome.controls(
            page == .keyboard
                ? [("G", "glossary"), ("D", "diagnostics")] : [("?", "keys"), ("D", "diagnostics")])
        let exit = TerminalChrome.controls([("Esc", "back"), ("q/Ctrl-C", "quit")])
        let combined = ReportLine(runs: navigation.runs + [.init(" · ")] + destinations.runs)
        if TerminalCells.width(combined.text) <= width {
            lines += [TerminalChrome.rule(width: width), combined, exit].map(TerminalChrome.footerHint)
        } else {
            lines += [navigation, destinations, exit].map(TerminalChrome.footerHint)
        }
        return lines.map { $0.clipped(to: width) }
    }
}

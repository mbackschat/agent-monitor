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
                [ReportLine($0.title, style: .heading), ReportLine($0.definition), ReportLine("")]
            }
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
                        ReportLine(
                            metric.title + ": " + metric.value, style: metric.warning ? .warning : .heading),
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
        var lines = [
            ReportLine("Esc returns to your selection. These keys apply in the report.", style: .muted),
            ReportLine("Navigation", style: .heading),
        ]
        if !state.showsOverview || !state.overview.visibleRows.isEmpty {
            lines.append(
                ReportLine(
                    state.showsOverview && state.overview.detailsVisible && state.overview.focus == .details
                        ? "↑/↓ scroll details" : "↑/↓ select row"))
        }
        if state.showsOverview {
            lines.append(ReportLine("8 collapse/expand table"))
            for section in state.overview.tableSections {
                lines.append(ReportLine(section.shortcut + " fold " + section.rawValue))
            }
            if state.overview.selectionIsVisible, let id = state.overview.selection,
                let node = state.overview.nodes[id]
            {
                if !node.children.isEmpty { lines.append(ReportLine("←/→ collapse/expand row")) }
                lines.append(ReportLine("i show/hide contributor details"))
                if state.overview.pinTarget(for: id) != nil {
                    lines.append(ReportLine(". pin/unpin session"))
                }
                if let identity = node.process,
                    state.snapshot?.findings.contains(where: { $0.process == identity && !$0.isHistorical })
                        == true
                {
                    lines.append(ReportLine("Enter inspect current process"))
                }
            }
            if state.overview.detailsVisible {
                lines += [
                    ReportLine("Tab switch rows/details · Esc close details"),
                    ReportLine("PgUp/PgDn scroll details · [/] scroll one line"),
                ]
            }
            lines += [ReportLine("a main/all contributors"), ReportLine("b change fixed CPU chart range")]
        } else {
            if state.selectedGroup != nil { lines.append(ReportLine("←/→ collapse/expand group")) }
            if state.grouping == .session {
                lines.append(ReportLine("Shift+←/→ collapse/expand session groups"))
            }
            if state.selection != nil {
                lines += [ReportLine("i show/hide details"), ReportLine(". pin/unpin row")]
            }
            if state.detailsMode != .minimized {
                lines += [
                    ReportLine("PgUp/PgDn scroll details · [/] scroll one line"),
                    ReportLine("-/+ resize details · 0 minimize · 9 maximize · = restore"),
                ]
            } else {
                lines.append(ReportLine("9 maximize details · = restore details"))
            }
            if state.commandInspectionTarget != nil { lines.append(ReportLine("x read/hide full arguments")) }
            if let row = state.rows.first(where: { $0.process == state.selected }), !row.isHistorical {
                lines.append(ReportLine("k review process termination"))
            }
            // Reuse beginAction's group/runtime resolution without performing its effect;
            // the guide must not advertise a different target from the TUI action handler.
            var preview = state
            if case .focus(let target) = preview.beginAction(.focus),
                !target.isHistorical, target.attribution.runtime != nil,
                case .terminal = target.attribution.context
            {
                lines.append(ReportLine("f show session terminal"))
            }
            lines += [ReportLine("n sort by PID"), ReportLine("h history metric · t history time range")]
        }
        if state.hasPins { lines.append(ReportLine("u unpin all")) }
        lines += [ReportLine(""), ReportLine("View & display", style: .heading)]
        if state.canSelectOverview { lines.append(ReportLine("v switch overview/processes")) }
        lines += [ReportLine("g toggle process grouping"), ReportLine("c/m/o sort CPU/memory/stable order")]
        if state.showsOverview ? state.overview.order != .stable : state.sortKey != .stable {
            lines.append(ReportLine("r reverse sort direction"))
        }
        if state.snapshot != nil {
            lines.append(ReportLine(state.frozen ? "p resume updates" : "p pause updates"))
        }
        lines += [
            ReportLine("1/2 lower/raise CPU filter · 3/4 lower/raise memory filter"),
            ReportLine("</> slower/faster sampling"), ReportLine(""),
            ReportLine("Help & investigation", style: .heading),
            ReportLine("? keyboard shortcuts · G glossary · D diagnostics"),
            ReportLine("q/Ctrl-C quit"),
        ]
        if !state.diagnosis.isRunning { lines.append(ReportLine("d start CPU investigation")) }
        return lines
    }

    private static func wrapped(state: LiveReportState, page: ReportReferencePage, width: Int) -> [ReportLine]
    {
        content(state: state, page: page).flatMap { line in
            TerminalCells.wrapped(line.text, to: max(1, width)).map { ReportLine($0, style: line.style) }
        }
    }

    public static func maximumOffset(state: LiveReportState, width: Int, height: Int) -> Int {
        guard let page = state.referencePage else { return 0 }
        return max(0, wrapped(state: state, page: page, width: width).count - max(1, height - 4))
    }

    public static func lines(state: LiveReportState, width: Int, height: Int) -> [ReportLine] {
        guard let page = state.referencePage, width > 0, height > 0 else { return [] }
        let controls = "Esc back | q/Ctrl-C quit"
        if width < 40 || height < 8 {
            return [
                ReportLine(page.title, style: .title), ReportLine("Resize to 40x8 or larger"),
                ReportLine(controls),
            ]
            .prefix(height).map { ReportLine(TerminalCells.clipped($0.text, to: width), style: $0.style) }
        }
        let content = wrapped(state: state, page: page, width: width)
        let capacity = height - 4
        let offset = min(max(0, state.referenceOffset), max(0, content.count - capacity))
        var lines = [ReportLine(page.title, style: .title)] + content.dropFirst(offset).prefix(capacity)
        lines += Array(repeating: ReportLine(""), count: max(0, height - 3 - lines.count))
        let destination = page == .keyboard ? "G glossary | D diagnostics" : "? keys | D diagnostics"
        lines += [
            ReportLine("↑/↓ [/] PgUp/Dn scroll", style: .muted),
            ReportLine(destination, style: .muted),
            ReportLine(controls, style: .muted),
        ]
        return lines.map { ReportLine(TerminalCells.clipped($0.text, to: width), style: $0.style) }
    }
}

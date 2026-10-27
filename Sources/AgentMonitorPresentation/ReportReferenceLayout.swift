import AgentMonitorCore

public enum ReportReferencePage: Equatable, Sendable {
    case glossary, diagnostics

    public var title: String {
        switch self {
        case .glossary: "Help & glossary"
        case .diagnostics: "Diagnostics"
        }
    }
}

public enum ReportReferenceLayout {
    public static func content(state: LiveReportState, page: ReportReferencePage) -> [ReportLine] {
        switch page {
        case .glossary:
            return ReportGlossary.entries.flatMap {
                [ReportLine($0.title, style: .heading), ReportLine($0.definition), ReportLine("")]
            } + keyboardHelp
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

    private static let keyboardHelp: [ReportLine] = [
        ReportLine("Keyboard controls", style: .heading),
        ReportLine("? help & glossary · D passive diagnostics · Esc back · q/Ctrl-C quit"),
        ReportLine("v overview/processes · a recent/remainder · ↑/↓ select · ←/→ collapse/expand"),
        ReportLine(
            "Process view: Shift+←/→ collapse/expand session groups · Enter inspect current overview process"),
        ReportLine("i show/hide details · PgUp/PgDn scroll 5 lines · [/] scroll 1 line"),
        ReportLine(
            "c/m CPU/memory order · n/o enter process PID/Stable order · r reverse process numeric order · g process groups"
        ),
        ReportLine(". pin/unpin owning overview session or selected process/session · u unpin all"),
        ReportLine("p pause/resume · h history metric · t history range"),
        ReportLine("1/2 CPU threshold −/+10% · 3/4 memory threshold −/+1 GB · </> slower/faster acquisition"),
        ReportLine("Details: -/+ resize · 0 minimize · 9 maximize · = restore · x read/hide arguments"),
        ReportLine("k review termination · s messaging unavailable · f focus session terminal"),
        ReportLine("d starts a finite CPU diagnosis; D only displays existing diagnostics."),
        ReportLine(DiagnosisViewState.help),
        ReportLine("CPU diagnosis: x cancel · Esc back · d run again · ↑/↓ or PgUp/PgDn scroll"),
        ReportLine("q/Ctrl-C quit"),
    ]

    private static func wrapped(state: LiveReportState, page: ReportReferencePage, width: Int) -> [ReportLine]
    {
        content(state: state, page: page).flatMap { line in
            TerminalCells.wrapped(line.text, to: max(1, width)).map { ReportLine($0, style: line.style) }
        }
    }

    public static func maximumOffset(state: LiveReportState, width: Int, height: Int) -> Int {
        guard let page = state.referencePage else { return 0 }
        return max(0, wrapped(state: state, page: page, width: width).count - max(1, height - 3))
    }

    public static func lines(state: LiveReportState, width: Int, height: Int) -> [ReportLine] {
        guard let page = state.referencePage, width > 0, height > 0 else { return [] }
        let controls = "Esc back | q quit"
        if width < 40 || height < 8 {
            return [
                ReportLine(page.title, style: .title), ReportLine("Resize to 40x8 or larger"),
                ReportLine(controls),
            ]
            .prefix(height).map { ReportLine(TerminalCells.clipped($0.text, to: width), style: $0.style) }
        }
        let content = wrapped(state: state, page: page, width: width)
        let capacity = height - 3
        let offset = min(max(0, state.referenceOffset), max(0, content.count - capacity))
        var lines = [ReportLine(page.title, style: .title)] + content.dropFirst(offset).prefix(capacity)
        lines += Array(repeating: ReportLine(""), count: max(0, height - 2 - lines.count))
        let destination = page == .glossary ? "D diagnostics" : "? help"
        lines += [
            ReportLine("↑/↓ [/] PgUp/Dn scroll | " + destination, style: .muted),
            ReportLine(controls, style: .muted),
        ]
        return lines.map { ReportLine(TerminalCells.clipped($0.text, to: width), style: $0.style) }
    }
}

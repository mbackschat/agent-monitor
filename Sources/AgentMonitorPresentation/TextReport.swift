import AgentMonitorCore
import Foundation

public enum TextReport {
    /// The plain report, or the same text with ANSI colors for a terminal.
    public static func render(
        _ report: MonitoringSnapshot, grouping: ReportGrouping = .none, color: Bool = false
    )
        -> String
    {
        lines(report, grouping: grouping).map { color ? ANSIText.styled($0) : $0.text }.joined(
            separator: "\n")
    }

    public static func lines(_ report: MonitoringSnapshot, grouping: ReportGrouping = .none) -> [ReportLine] {
        let filter = ThresholdContext.text(
            Thresholds(cpuPercent: report.cpuThresholdPercent, memoryBytes: report.memoryThresholdBytes))
        var lines = [
            ReportLine(""),
            ReportLine(String(repeating: "=", count: 72), style: .muted),
            ReportLine(
                "Agent Monitor | \(report.timestamp.ISO8601Format()) | \(filter)",
                style: .title),
            ReportLine(
                "\(report.findings.count) processes shown; \(report.sampledProcessCount) same-user processes sampled. CPU: 100% = one core.",
                style: .muted),
        ]
        lines.append(ReportLine(CPUContext.text(report.cpuAccounting), style: .muted))
        if let window = report.window {
            lines.append(ReportLine(AccountingContext.window(window), style: .muted))
            lines += window.collapsedContributions.map {
                ReportLine(AccountingContext.collapsed($0), style: .warning)
            }
        }
        if report.findings.isEmpty {
            lines.append(ReportLine("No processes match the display filters in this scope."))
        }
        switch grouping {
        case .none:
            for row in report.findings { lines += processLines(row, window: report.window) }
        case .session:
            lines.append(
                ReportLine(
                    "Grouped by launch session; totals include all observed members, independent of filters. Sampling may miss short-lived work.",
                    style: .muted))
            let displayed = Set(report.findings.map(\.process))
            for group in SessionGrouping.groups(report.observedFindings)
            where group.containsDisplayedProcess(in: displayed) {
                let cpu = group.cpuTotal.map { ReportNumber.text($0) + "%" } ?? "unavailable"
                let memory = group.memoryGBTotal.map { ReportNumber.text($0) + " GB" } ?? "unavailable"
                lines.append(ReportLine(""))
                lines.append(
                    ReportLine(
                        "Session: \(group.sessionDescription) | \(group.label)",
                        style: .heading))
                lines.append(
                    ReportLine(
                        "  Observed totals: CPU \(cpu)\(group.cpuPartial ? " (partial)" : "")  footprint \(memory)\(group.memoryPartial ? " (partial)" : "")"
                    ))
                for row in group.processes where displayed.contains(row.process) {
                    lines += processLines(row, window: report.window)
                }
            }
        }
        return lines
    }

    private static func processLines(_ row: HeavyProcess, window: ReportWindowSummary?) -> [ReportLine] {
        var lines: [ReportLine] = []
        let owner = row.attribution
        let provider =
            switch owner.provider {
            case .codex: "Codex"
            case .claude: "Claude Code"
            case nil: "Agent"
            }
        let cpu = row.cpuPercent.map { "\(ReportNumber.text($0))%" } ?? "unavailable"
        let memory = row.footprintBytes.map { "\(ReportNumber.text(Double($0) / 1e9)) GB" } ?? "unavailable"
        lines.append(ReportLine(""))
        lines.append(
            ReportLine(
                "PID \(row.process.pid)  CPU \(cpu)  footprint \(memory)  \(row.executable.isEmpty ? row.name : row.executable)",
                style: .heavy))
        if let window {
            lines.append(ReportLine("  " + AccountingContext.evidence(row, in: window), style: .muted))
        }
        lines += AccountingContext.process(row).map { ReportLine("  " + $0, style: .muted) }
        if let peak = FootprintContext.kernelPeak(row) { lines.append(ReportLine("  " + peak)) }
        if let thread = owner.threadID {
            let relation = owner.evidence == .sessionRegistry ? "current" : "launch"
            lines.append(
                ReportLine(
                    "  \(provider) \(relation) session: \(thread) [\(owner.evidence.rawValue), \(owner.context.rawValue)]"
                ))
        } else {
            let label = owner.runtime == nil ? "Session" : "\(provider) logical thread"
            lines.append(
                ReportLine(
                    "  \(label): \(row.sessionDescription) [\(owner.evidence.rawValue), \(owner.context.rawValue)]",
                    style: row.isSharedRuntime ? .normal : .warning))
        }
        if let root = owner.rootSessionID, root != owner.threadID {
            lines.append(ReportLine("  Root session: \(root)"))
        }
        if let runtime = owner.runtime {
            lines.append(
                ReportLine(
                    "  \(provider) runtime PID: \(runtime.pid)  terminal: \(owner.terminal ?? "unavailable")")
            )
        }
        if !owner.candidateThreadIDs.isEmpty, owner.threadID == nil {
            lines.append(
                ReportLine(
                    "  Candidate threads: \(owner.candidateThreadIDs.count) (use --json for IDs)",
                    style: .muted))
        }
        if let cwd = row.cwd { lines.append(ReportLine("  Work directory: \(cwd)", style: .muted)) }
        if let cwd = owner.runtimeDirectory {
            lines.append(ReportLine("  Runtime directory: \(cwd)", style: .muted))
        }
        if let command = row.command {
            lines.append(
                ReportLine(
                    "  Arguments: \(command.map { safe($0.debugDescription) }.joined(separator: " "))",
                    style: .muted))
        }
        if owner.ancestry.count > 1 {
            lines.append(
                ReportLine(
                    "  Observed chain: \(owner.ancestry.map { String($0.pid) }.joined(separator: " ← "))",
                    style: .muted))
        }
        return lines
    }

    public static func safe(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            switch scalar.value {
            // Joiners shape emoji and scripts; other format controls remain neutralized.
            // The production-path regressions are in TerminalCellLayoutTests.
            case 0x200C, 0x200D: String(scalar)
            default: CharacterSet.controlCharacters.contains(scalar) ? "�" : String(scalar)
            }
        }.joined()
    }
}

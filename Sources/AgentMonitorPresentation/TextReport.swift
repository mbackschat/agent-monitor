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
        var lines = [
            ReportLine(""),
            ReportLine(String(repeating: "=", count: 72), style: .muted),
            ReportLine(
                "Agent Monitor | \(report.timestamp.ISO8601Format()) | CPU > \(number(report.cpuThresholdPercent))% OR footprint > \(number(Double(report.memoryThresholdBytes) / 1e9)) GB",
                style: .title),
            ReportLine(
                "\(report.findings.count) heavy processes; \(report.sampledProcessCount) same-user processes sampled. CPU: 100% = one core.",
                style: .muted),
        ]
        if report.findings.isEmpty {
            lines.append(ReportLine("No processes exceeded either threshold in this interval."))
        }
        switch grouping {
        case .none:
            for row in report.findings { lines += processLines(row) }
        case .session:
            lines.append(
                ReportLine(
                    "Grouped by launch session; heavy-process totals only, not complete session usage.",
                    style: .muted))
            for group in SessionGrouping.groups(report.findings) {
                let cpu = group.cpuTotal.map { number($0) + "%" } ?? "unavailable"
                let memory = group.memoryGBTotal.map { number($0) + " GB" } ?? "unavailable"
                lines.append(ReportLine(""))
                lines.append(
                    ReportLine(
                        "Session: \(group.sessionID ?? "unresolved PID \(group.minimumPID)") | \(group.label)",
                        style: .heading))
                lines.append(
                    ReportLine(
                        "  Heavy-process totals: CPU \(cpu)\(group.cpuPartial ? " (partial)" : "")  footprint \(memory)\(group.memoryPartial ? " (partial)" : "")"
                    ))
                for row in group.processes { lines += processLines(row) }
            }
        }
        return lines
    }

    private static func processLines(_ row: HeavyProcess) -> [ReportLine] {
        var lines: [ReportLine] = []
        let owner = row.attribution
        let provider =
            switch owner.provider {
            case .codex: "Codex"
            case .claude: "Claude Code"
            case nil: "Agent"
            }
        let cpu = row.cpuPercent.map { "\(number($0))%" } ?? "unavailable"
        let memory = row.footprintBytes.map { "\(number(Double($0) / 1e9)) GB" } ?? "unavailable"
        lines.append(ReportLine(""))
        lines.append(
            ReportLine(
                "PID \(row.process.pid)  CPU \(cpu)  footprint \(memory)  \(row.executable.isEmpty ? row.name : row.executable)",
                style: .heavy))
        if let thread = owner.threadID {
            lines.append(
                ReportLine(
                    "  \(provider) launch session: \(thread) [\(owner.evidence.rawValue), \(owner.context.rawValue)]"
                ))
        } else {
            let label = owner.runtime == nil ? "Session" : "\(provider) logical thread"
            lines.append(
                ReportLine(
                    "  \(label): unresolved [\(owner.evidence.rawValue), \(owner.context.rawValue)]",
                    style: .warning))
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
            lines.append(ReportLine("  Session directory: \(cwd)", style: .muted))
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
        String(
            value.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? "�" : String($0) }
                .joined())
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

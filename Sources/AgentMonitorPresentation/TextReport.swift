import AgentMonitorCore
import Foundation

public enum TextReport {
    public static func render(_ report: MonitoringSnapshot, grouping: ReportGrouping = .none) -> String {
        var lines = [
            "",
            String(repeating: "=", count: 72),
            "Agent Monitor | \(report.timestamp.ISO8601Format()) | CPU > \(number(report.cpuThresholdPercent))% OR footprint > \(number(Double(report.memoryThresholdBytes) / 1e9)) GB",
            "\(report.findings.count) heavy processes; \(report.sampledProcessCount) same-user processes sampled. CPU: 100% = one core.",
        ]
        if report.findings.isEmpty {
            lines.append("No processes exceeded either threshold in this interval.")
        }
        switch grouping {
        case .none:
            for row in report.findings { lines += processLines(row) }
        case .session:
            lines.append("Grouped by launch session; heavy-process totals only, not complete session usage.")
            for group in SessionGrouping.groups(report.findings) {
                let cpu = group.cpuTotal.map { number($0) + "%" } ?? "unavailable"
                let memory = group.memoryGBTotal.map { number($0) + " GB" } ?? "unavailable"
                lines.append(
                    "\nSession: \(safe(group.sessionID ?? "unresolved PID \(group.minimumPID)")) | \(safe(group.label))"
                )
                lines.append(
                    "  Heavy-process totals: CPU \(cpu)\(group.cpuPartial ? " (partial)" : "")  footprint \(memory)\(group.memoryPartial ? " (partial)" : "")"
                )
                for row in group.processes { lines += processLines(row) }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func processLines(_ row: HeavyProcess) -> [String] {
        var lines: [String] = []
        let owner = row.attribution
        let provider = owner.provider.map { $0 == .codex ? "Codex" : "Claude Code" } ?? "Agent"
        let cpu = row.cpuPercent.map { "\(number($0))%" } ?? "unavailable"
        let memory = row.footprintBytes.map { "\(number(Double($0) / 1e9)) GB" } ?? "unavailable"
        lines.append("")
        lines.append(
            "PID \(row.process.pid)  CPU \(cpu)  footprint \(memory)  \(safe(row.executable.isEmpty ? row.name : row.executable))"
        )
        if let thread = owner.threadID {
            lines.append(
                "  \(provider) launch session: \(safe(thread)) [\(owner.evidence.rawValue), \(owner.context.rawValue)]"
            )
        } else {
            let label = owner.runtime == nil ? "Session" : "\(provider) logical thread"
            lines.append("  \(label): unresolved [\(owner.evidence.rawValue), \(owner.context.rawValue)]")
        }
        if let root = owner.rootSessionID, root != owner.threadID {
            lines.append("  Root session: \(safe(root))")
        }
        if let runtime = owner.runtime {
            lines.append(
                "  \(provider) runtime PID: \(runtime.pid)  terminal: \(safe(owner.terminal ?? "unavailable"))"
            )
        }
        if !owner.candidateThreadIDs.isEmpty, owner.threadID == nil {
            lines.append(
                "  Candidate threads: \(owner.candidateThreadIDs.count) (use --json for IDs)")
        }
        if let cwd = row.cwd { lines.append("  Work directory: \(safe(cwd))") }
        if let cwd = owner.runtimeDirectory { lines.append("  Session directory: \(safe(cwd))") }
        if let command = row.command {
            lines.append(
                "  Arguments: \(command.map { safe($0.debugDescription) }.joined(separator: " "))")
        }
        if owner.ancestry.count > 1 {
            lines.append(
                "  Observed chain: \(owner.ancestry.map { String($0.pid) }.joined(separator: " ← "))")
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

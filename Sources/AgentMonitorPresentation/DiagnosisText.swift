import AgentMonitorCore
import Foundation

public enum DiagnosisText {
    public static let collectionFailure =
        "collectionFailed: Could not acquire the baseline or a required process scan. No diagnosis was produced."

    public static func render(_ value: CPUDiagnosis) -> String {
        lines(value, includingHelperFlags: false).joined(separator: "\n")
    }

    static func lines(_ value: CPUDiagnosis, includingHelperFlags: Bool) -> [String] {
        DiagnosisReportSection.displayLines(sections(value, includingHelperFlags: includingHelperFlags)).map(
            \.text)
    }

    static func sections(_ value: CPUDiagnosis, includingHelperFlags: Bool) -> [DiagnosisReportSection] {
        let report = JSONDiagnosis(value)
        let capacity = report.host.logicalCPUCount.map { " of \($0 * 100)%" } ?? ""
        let host = report.host.meanBusyPercent.map { number($0) + "%" } ?? "No data"
        let measured = report.measured.cpuSeconds.map { number($0) + " CPU-s" } ?? "No data"
        let percent = report.measured.windowCPUPercent.map { " (\(number($0))% of the window)" } ?? ""
        let summary = [
            "CPU diagnosis: \(JSONDiagnosis.timestamp(value.startedAt)) – \(JSONDiagnosis.timestamp(value.endedAt))",
            "Window \(number(value.elapsedSeconds))s; 3 one-second waits; largest scan \(number(value.maximumScanSeconds))s.",
            "CPU: host \(host)\(capacity) · your measured processes \(measured)\(percent)",
            "Host coverage: \(number(report.host.observedSeconds))s, \(report.host.validIntervals)/3 intervals.",
            "Lifetimes: \(value.observedLifetimeCount) observed, \(value.measuredLifetimeCount) measured; \(value.unmeasuredObservationCount) unmeasured observations, \(value.unreadableObservationCount) unreadable reads.",
            "Contributors: \(report.contributors.count) returned, \(value.omittedContributorCount) omitted; totals include both. 100% = one logical CPU.",
        ]
        var sections = [
            DiagnosisReportSection(kind: .summary, title: "Summary", lines: summary.map { ReportLine($0) })
        ]
        for (index, pair) in zip(report.contributors, value.contributors).enumerated() {
            let (row, measured) = pair
            let helper = includingHelperFlags && measured.isMonitorHelper ? " [Monitor helper]" : ""
            let title =
                "\(index + 1). \(quoted(row.label))\(row.labelTruncated ? " [label truncated]" : "") · \(number(row.cpuSeconds)) CPU-s"
            var lines = [
                "Process: \(row.process.pid)/\(row.process.startMicroseconds)\(helper)",
                "CPU: mean \(number(row.meanCPUPercent))%, peak \(number(row.peakCPUPercent))%; \(number(row.observedSeconds))s across \(row.validIntervals) intervals.",
            ]
            if let footprint = row.footprint {
                lines.append(
                    "  Footprint: \(footprint.bytes) bytes at \(JSONDiagnosis.timestamp(footprint.sampledAt))."
                )
            }
            switch row.attribution.value {
            case .unavailable(let reason):
                lines.append("  Attribution unavailable: \(reason.rawValue).")
                if includingHelperFlags, reason == .notObservedAtEnrichment {
                    lines.append("  Not observed at enrichment; this is not proof of exit.")
                }
            case .available(let at, let owner):
                lines.append(
                    "  Attribution at \(JSONDiagnosis.timestamp(at)): \(owner.provider?.rawValue ?? "unknown") / \(owner.threadID ?? "unresolved") [\(owner.evidence.rawValue), \(owner.context.rawValue)]."
                )
                if let root = owner.rootSessionID { lines.append("  Root session: \(root).") }
                if let runtime = owner.runtime {
                    lines.append("  Runtime: \(runtime.pid)/\(runtime.startMicroseconds).")
                }
                if let terminal = owner.terminal {
                    lines.append("  Terminal: \(quoted(terminal)).")
                }
                if let directory = owner.runtimeDirectory {
                    lines.append("  Runtime directory: \(quoted(directory)).")
                }
                if !owner.candidateThreadIDs.isEmpty {
                    lines.append(
                        "  Candidate alternatives: \(owner.candidateThreadIDs.joined(separator: ", ")).")
                }
                lines.append(
                    "  Observed ancestry: \(owner.ancestry.map { "\($0.pid)/\($0.startMicroseconds)" }.joined(separator: " ← "))."
                )
            }
            sections.append(
                DiagnosisReportSection(
                    kind: .contributor, title: title,
                    lines: lines.enumerated().map { index, line in
                        ReportLine(line, style: index < 2 ? .normal : .muted)
                    }))
        }
        var lines = [
            "Provider lookups: "
                + (report.providerLookups.isEmpty
                    ? "none."
                    : report.providerLookups.map { "\($0.provider.rawValue) \($0.status)" }.joined(
                        separator: ", "))
        ]
        lines += value.diagnostics.map { "\($0.rawValue): \($0.explanation)" }
        sections.append(
            DiagnosisReportSection(
                kind: .notes, title: "Coverage and interpretation",
                lines: lines.map { ReportLine($0, style: .muted) }))
        return sections
    }

    private static func quoted(_ value: String) -> String {
        String(reflecting: TextReport.safe(value))
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

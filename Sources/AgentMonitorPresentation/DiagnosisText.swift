import AgentMonitorCore
import Foundation

public enum DiagnosisText {
    public static let collectionFailure =
        "collectionFailed: Could not acquire the baseline or a required process scan. No diagnosis was produced."

    public static func render(_ value: CPUDiagnosis) -> String {
        let report = JSONDiagnosis(value)
        let capacity = report.host.logicalCPUCount.map { " of \($0 * 100)%" } ?? ""
        let host = report.host.meanBusyPercent.map { number($0) + "%" } ?? "No data"
        let measured = report.measured.cpuSeconds.map { number($0) + " CPU-s" } ?? "No data"
        let percent = report.measured.windowCPUPercent.map { " (\(number($0))% of the window)" } ?? ""
        var lines = [
            "CPU diagnosis: \(JSONDiagnosis.timestamp(value.startedAt)) – \(JSONDiagnosis.timestamp(value.endedAt))",
            "Window \(number(value.elapsedSeconds))s; 3 one-second waits; largest scan \(number(value.maximumScanSeconds))s.",
            "CPU: host \(host)\(capacity) · your measured processes \(measured)\(percent)",
            "Host coverage: \(number(report.host.observedSeconds))s, \(report.host.validIntervals)/3 intervals.",
            "Lifetimes: \(value.observedLifetimeCount) observed, \(value.measuredLifetimeCount) measured; \(value.unmeasuredObservationCount) unmeasured observations, \(value.unreadableObservationCount) unreadable reads.",
            "Contributors: \(report.contributors.count) returned, \(value.omittedContributorCount) omitted; totals include both. 100% = one logical CPU.",
        ]
        for row in report.contributors {
            lines.append(
                "\(row.process.pid)/\(row.process.startMicroseconds) \(String(reflecting: row.label))\(row.labelTruncated ? " [label truncated]" : ""): \(number(row.cpuSeconds)) CPU-s, mean \(number(row.meanCPUPercent))%, peak \(number(row.peakCPUPercent))%; \(number(row.observedSeconds))s across \(row.validIntervals) intervals."
            )
            if let footprint = row.footprint {
                lines.append(
                    "  Footprint: \(footprint.bytes) bytes at \(JSONDiagnosis.timestamp(footprint.sampledAt))."
                )
            }
            switch row.attribution.value {
            case .unavailable(let reason): lines.append("  Attribution unavailable: \(reason.rawValue).")
            case .available(let at, let owner):
                lines.append(
                    "  Attribution at \(JSONDiagnosis.timestamp(at)): \(owner.provider?.rawValue ?? "unknown") / \(owner.threadID ?? "unresolved") [\(owner.evidence.rawValue), \(owner.context.rawValue)]."
                )
                if let root = owner.rootSessionID { lines.append("  Root session: \(root).") }
                if let runtime = owner.runtime {
                    lines.append("  Runtime: \(runtime.pid)/\(runtime.startMicroseconds).")
                }
                if let terminal = owner.terminal {
                    lines.append("  Terminal: \(String(reflecting: terminal)).")
                }
                if let directory = owner.runtimeDirectory {
                    lines.append("  Runtime directory: \(String(reflecting: directory)).")
                }
                if !owner.candidateThreadIDs.isEmpty {
                    lines.append(
                        "  Candidate alternatives: \(owner.candidateThreadIDs.joined(separator: ", ")).")
                }
                lines.append(
                    "  Observed ancestry: \(owner.ancestry.map { "\($0.pid)/\($0.startMicroseconds)" }.joined(separator: " ← "))."
                )
            }
        }
        lines.append(
            "Provider lookups: "
                + (report.providerLookups.isEmpty
                    ? "none."
                    : report.providerLookups.map { "\($0.provider.rawValue) \($0.status)" }.joined(
                        separator: ", ")))
        lines += value.diagnostics.map { "\($0.rawValue): \($0.explanation)" }
        return lines.joined(separator: "\n")
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

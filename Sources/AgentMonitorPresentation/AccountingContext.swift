import AgentMonitorCore

public enum AccountingContext {
    public static func window(_ window: ReportWindowSummary) -> String {
        "CPU over \(ReportNumber.text(window.durationSeconds)) s · point-evidence candidates; interval ownership unverified. Polling can miss workers and final exit CPU."
    }

    public static func process(_ process: HeavyProcess) -> [String] {
        guard let usage = process.accounting else { return [] }
        var lines = [
            usage.isHistorical
                ? "No longer observed · historical contributor · actions unavailable"
                : "Observed in the final scan",
            "Measured CPU: \(usage.cpuSeconds.map { ReportNumber.text($0) + " s" } ?? "unavailable") · point candidate \(ReportNumber.text(usage.pointCandidateCPUSeconds)) s · uncertain/unresolved \(ReportNumber.text(usage.uncertainCPUSeconds)) s",
        ]
        if usage.recoveredCPUSeconds > 0 {
            lines.append(
                "Recovered CPU: \(ReportNumber.text(usage.recoveredCPUSeconds)) s across an earlier boundary; excluded from this window's rate"
            )
        }
        if usage.isHistorical, let memory = usage.lastObservedFootprintBytes {
            lines.append(
                "Last observed footprint: \(ReportNumber.text(Double(memory) / 1e9)) GB · excluded from current totals"
            )
        }
        return lines
    }
    public static func evidence(_ process: HeavyProcess, in window: ReportWindowSummary) -> String {
        let records = window.contributions.filter { $0.process == process.process }
        let times = records.compactMap(\.pointEvidenceObservedAt)
        guard let earliest = times.min(), let latest = times.max() else {
            return "Point-label observation time unavailable; interval ownership unverified"
        }
        let first = window.endedAt - earliest
        let last = window.endedAt - latest
        let age =
            first < 0 || last < 0
            ? "includes evidence collected after the CPU window"
            : "observed \(ReportNumber.text(last))–\(ReportNumber.text(first)) s before window end"
        return "Point labels: " + age
            + (times.count < records.count ? "; some observation times unavailable" : "")
            + "; interval ownership unverified"
    }

}

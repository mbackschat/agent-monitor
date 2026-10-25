import AgentMonitorCore

public enum AccountingContext {
    public static func window(_ window: ReportWindowSummary) -> String {
        "CPU over \(ReportNumber.text(window.durationSeconds)) s · point-evidence candidates; interval ownership unverified. Polling can miss workers and final exit CPU. "
            + acquisition(window.acquisitionCoverage)
    }

    public enum PublicationRange { case window, recent }

    public static func publication(
        _ coverage: PublicationCoverage, range: PublicationRange = .window
    ) -> String? {
        guard coverage.coalescedUnitCount > 0 else { return nil }
        let label: String
        switch range {
        case .window: label = "Window"
        case .recent: label = "Recent"
        }
        return
            "\(label): \(coverage.coalescedUnitCount) units coalesced · max unit \(ReportNumber.text(coverage.maximumUnitSpanSeconds)) s"
    }

    public static func publicationRange(_ coverage: PublicationCoverage, endingAt end: Double) -> String? {
        guard let first = coverage.coalescedStartedAt, let last = coverage.coalescedEndedAt else {
            return nil
        }
        return
            "coalesced range \(ReportNumber.text(max(0, end - last)))–\(ReportNumber.text(max(0, end - first))) s before range end"
    }

    public static func pressure(_ window: ReportWindowSummary) -> String? {
        let values = window.collapsedContributions
        guard let first = values.map(\.startedAt).min(), let last = values.map(\.endedAt).max() else {
            return nil
        }
        return "Collapsed detail · "
            + ReportNumber.text(max(0, window.endedAt - last)) + "–"
            + ReportNumber.text(max(0, window.endedAt - first))
            + " s before window end · group rows show retained detail"
    }

    public static func acquisition(_ coverage: AcquisitionCoverage) -> String {
        let gap = coverage.maximumGapSeconds.map { ReportNumber.text($0 * 1_000) + " ms" } ?? "unavailable"
        return
            "Acquisition: \(coverage.scanCount) scans · max gap \(gap) · \(coverage.overrunCount) periods >1.5× requested"
    }

    public static func collapsed(_ value: CollapsedContribution) -> String {
        let counts = value.workerCount
        let workers =
            counts.minimum == counts.maximum ? "\(counts.minimum)" : "\(counts.minimum)–\(counts.maximum)"
        let owner =
            value.category.sessionID.map { "\(value.category.provider?.rawValue ?? "agent")/\($0.prefix(8))" }
            ?? (value.category.agentAssociated ? "Agent-associated work" : "Other observed work")
        let executable =
            value.category.invocationName
            ?? value.category.executable?.split(separator: "/").last.map(String.init)
        let label = [owner, executable].compactMap { $0 }.joined(separator: " · ")
        let peak =
            value.maximumFootprint.map { " · sampled max \(ReportNumber.text(Double($0.bytes) / 1e6)) MB" }
            ?? ""
        return
            "Collapsed · \(label) · \(ReportNumber.text(value.cpuSeconds)) CPU s · \(value.intervalCount) intervals · \(workers) workers · monotonic \(ReportNumber.text(value.startedAt))–\(ReportNumber.text(value.endedAt)) s"
            + peak
            + (value.category.categoryDetailsRetained
                ? " · identity and directory detail released"
                : " · category, identity and directory detail released")
    }

    public static func process(_ process: HeavyProcess) -> [String] {
        guard let usage = process.accounting else { return [] }
        var lines = [
            usage.isHistorical
                ? "No longer observed · historical contributor · actions unavailable"
                : "Observed in the final scan",
            "Measured CPU: \(usage.cpuSeconds.map { ReportNumber.text($0) + " s" } ?? "unavailable") · point candidate \(ReportNumber.text(usage.pointCandidateCPUSeconds)) s · uncertain/unresolved \(ReportNumber.text(usage.uncertainCPUSeconds)) s",
        ]
        if usage.labelChangedInWindow {
            lines.append(
                "Label changed in window · process CPU spans labels; group CPU follows frozen labels")
        }
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
        let earliestTimes = records.compactMap(\.earliestEvidenceObservedAt)
        let latestTimes = records.compactMap(\.latestEvidenceObservedAt)
        guard let earliest = earliestTimes.min(), let latest = latestTimes.max() else {
            return "Point-label observation time unavailable; interval ownership unverified"
        }
        let first = window.endedAt - earliest
        let last = window.endedAt - latest
        let age =
            first < 0 || last < 0
            ? "includes evidence collected after the CPU window"
            : "observed \(ReportNumber.text(last))–\(ReportNumber.text(first)) s before window end"
        return "Point labels: " + age
            + (records.contains { $0.missingEvidenceTimeCount > 0 }
                ? "; some observation times unavailable" : "")
            + "; interval ownership unverified"
    }

}

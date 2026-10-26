import AgentMonitorCore

public struct SamplingCoverageSummary: Equatable, Sendable {
    public struct Metric: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let value: String
        public let help: String
        public let warning: Bool
    }
    public let inspection: InspectionCoverage
    public let metrics: [Metric]
    public let events: [Metric]
    public let duration: Double?
    public let retentionLimited: Bool
    public let scanLabel: String
    public let rangeLabel: String
    public static let interpretation =
        "Observed totals include filtered processes. CPU 100% means one core. Session ownership uses point evidence; polling can miss short-lived workers and final exit CPU. No longer observed does not confirm exit."

    public init(
        snapshot: MonitoringSnapshot, reads: ReadCoverage? = nil,
        observed: LifetimeCountRange? = nil, recentDuration: Double? = nil,
        retentionLimited: Bool = false, inspection: InspectionCoverage? = nil
    ) {
        self.inspection = inspection ?? snapshot.window?.inspectionCoverage ?? InspectionCoverage()
        let coverage = reads ?? snapshot.window?.readCoverage ?? ReadCoverage()
        let timing = snapshot.window?.acquisitionCoverage
        let count =
            observed
            ?? LifetimeCountRange(
                minimum: snapshot.observedFindings.count, maximum: snapshot.observedFindings.count)
        duration = recentDuration
        self.retentionLimited = retentionLimited
        rangeLabel = recentDuration == nil ? "Window" : "Recent"
        let scope = recentDuration == nil ? "display window" : "retained recent range"
        let failedTitle: String
        let failed: String
        let failedHelp: String
        let hasFailures: Bool
        if coverage.failedPIDCount.maximum > 0 {
            failedTitle = "Read failures"
            failed = coverage.readFailurePIDCount.text
            hasFailures = coverage.readFailurePIDCount.maximum > 0
            failedHelp =
                "Distinct same-user PID values that could not be read in the \(scope), excluding processes that exited before their read. Collection-wide, not agent-owned worker counts; PID reuse is unresolved. Failed PIDs per scan, including exits: mean \(ReportNumber.text(coverage.meanFailedPIDsPerScan)), maximum \(coverage.maximumFailedPIDsPerScan)."
        } else if coverage.unidentifiedFailureObservations > 0 {
            failedTitle = "Read gaps"
            failed = "\(coverage.unidentifiedFailureObservations) reads"
            hasFailures = true
            failedHelp =
                "Failed observations without PID detail in the \(scope); repeated observations are not distinct processes."
        } else {
            failedTitle = "Read gaps"
            failed = String(snapshot.unreadableProcessCount)
            hasFailures = snapshot.unreadableProcessCount > 0
            failedHelp = "Failed same-user PID reads in the latest scan; the cause and ownership are unknown."
        }
        metrics = [
            Metric(
                id: "observed", title: "Observed", value: count.text,
                help:
                    "Process lifetimes represented in the display window, including retained contributors. Count ranges disclose collapsed detail.",
                warning: false),
            Metric(
                id: "departed", title: "No longer seen",
                value: String(snapshot.observedFindings.filter(\.isHistorical).count),
                help: "Retained contributors absent from the final scan. Exit is unconfirmed.", warning: false
            ),
            Metric(id: "failed", title: failedTitle, value: failed, help: failedHelp, warning: hasFailures),
            Metric(
                id: "sampled", title: "Sampled", value: String(snapshot.sampledProcessCount),
                help:
                    "Readable same-user processes in the latest collection scan, before agent scope and display filters.",
                warning: false),
            Metric(
                id: "gap", title: "Max scan gap",
                value: timing?.maximumGapSeconds.map { ReportNumber.text($0 * 1_000) + " ms" } ?? "—",
                help:
                    "Longest start-to-start acquisition period in the display window. A gap can miss short-lived workers.",
                warning: (timing?.overrunCount ?? 0) > 0),
            Metric(
                id: "overruns", title: "Overruns", value: timing.map { String($0.overrunCount) } ?? "—",
                help:
                    "Periods exceeding 1.5 times the requested acquisition interval, in the display window.",
                warning: (timing?.overrunCount ?? 0) > 0),
        ]
        let kinds: [(String, String, LifetimeCountRange, String, Bool)] = [
            ("denied", "Denied", coverage.deniedPIDCount, "Permission denied", true),
            (
                "vanished", "Exited before read", coverage.vanishedPIDCount,
                "Listed but no longer existing when read (ESRCH), so CPU after the last reading is unmeasured",
                false
            ),
            (
                "changed", "Identity changed", coverage.mismatchedPIDCount, "Identity verification failed",
                true
            ),
            ("other", "Other", coverage.otherPIDCount, "Short reads or other native failures", true),
        ]
        events = kinds.filter { $0.2.maximum > 0 }.map {
            Metric(
                id: $0.0, title: $0.1, value: $0.2.text,
                help: "\($0.3). Same-user PID values in the \(scope); categories can overlap.", warning: $0.4)
        }
        scanLabel =
            timing.map {
                "\($0.scanCount) \($0.scanCount == 1 ? "scan" : "scans") · \(ReportNumber.text(snapshot.window?.durationSeconds ?? 0)) s window"
            }
            ?? "Latest scan"
    }

    public func terminalLines(width: Int) -> [String] {
        let columns = width >= 75 ? 3 : 2
        let cell = max(1, width / columns)
        let values = metrics + events
        let grid = stride(from: 0, to: values.count, by: columns).map { start in
            values.dropFirst(start).prefix(columns).map { metric in
                TerminalCells.padded(
                    TerminalCells.abbreviated(metric.title + ": " + metric.value, to: cell - 1), to: cell)
            }.joined()
        }
        guard inspection.mode != .disabled else { return grid }
        let row =
            "Between-scan reads | \(inspection.candidatesRead) read | \(inspection.carriedObservations) carried | \(inspection.opportunitiesSkipped)/\(inspection.opportunitiesTaken + inspection.opportunitiesSkipped) skipped"
        let losses =
            "Held | \(inspection.supersededReadings) superseded | \(inspection.droppedReadings) dropped | \(inspection.discardedReadings) discarded"
        return grid + TerminalCells.wrapped(row, to: width) + TerminalCells.wrapped(losses, to: width)
    }
}

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
        retentionLimited: Bool = false, inspection: InspectionCoverage? = nil,
        acquisition: AcquisitionCoverage? = nil
    ) {
        self.inspection = inspection ?? snapshot.window?.inspectionCoverage ?? InspectionCoverage()
        let coverage = reads ?? snapshot.window?.readCoverage ?? ReadCoverage()
        let timing = acquisition ?? snapshot.window?.acquisitionCoverage
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
        var metrics = [
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
                id: "gap",
                title: timing?.maximumRequestedPeriodSeconds == nil ? "Max scan gap" : "Max gap / request",
                value: Self.gap(timing),
                help:
                    "Longest achieved start-to-start period beside the largest requested interval in the \(scope). A gap can miss short-lived workers.",
                warning: (timing?.overrunCount ?? 0) > 0),
            Metric(
                id: "overruns", title: "Overruns", value: timing.map { String($0.overrunCount) } ?? "—",
                help:
                    "Periods exceeding 1.5 times their effective requested acquisition interval in the \(scope).",
                warning: (timing?.overrunCount ?? 0) > 0),
        ]
        if let minimum = timing?.minimumRequestedPeriodSeconds,
            let maximum = timing?.maximumRequestedPeriodSeconds
        {
            metrics.append(
                Metric(
                    id: "sampling-range", title: "Requested range",
                    value: Self.intervalRange(minimum, maximum),
                    help:
                        "Smallest and largest requested acquisition intervals in the \(scope); achieved gaps and effective deadlines are measured separately.",
                    warning: false))
        }
        metrics += Self.samplingMetrics(
            timing?.sampling ?? snapshot.cpuAccounting.acquisition?.sampling ?? SamplingCoverage(),
            scope: scope)
        self.metrics = metrics
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
                "\($0.scanCount) \($0.scanCount == 1 ? "scan" : "scans") · \(ReportNumber.text(recentDuration ?? snapshot.window?.durationSeconds ?? 0)) s \(recentDuration == nil ? "window" : "recent")"
            }
            ?? "Latest scan"
    }

    private static func gap(_ timing: AcquisitionCoverage?) -> String {
        let achieved = timing?.maximumGapSeconds.map { ReportNumber.text($0 * 1_000) } ?? "—"
        if let requested = timing?.maximumRequestedPeriodSeconds {
            return achieved + " / " + ReportNumber.text(requested * 1_000) + " ms"
        }
        return timing?.maximumGapSeconds == nil ? "—" : achieved + " ms"
    }

    private static func intervalRange(_ minimum: Double, _ maximum: Double) -> String {
        ReportNumber.text(minimum * 1_000) + "–" + ReportNumber.text(maximum * 1_000) + " ms"
    }

    private static func samplingMetrics(_ sampling: SamplingCoverage, scope: String) -> [Metric] {
        guard let latest = sampling.latest else { return [] }
        let mode: String
        switch latest.mode {
        case .fixed: mode = "Maximum interval"
        case .adaptive: mode = "Adaptive"
        }
        var values = [
            Metric(
                id: "sampling-mode", title: "Sampling",
                value: mode + (sampling.modes.count > 1 ? " · mixed" : ""),
                help:
                    "Current sampling mode. Mixed means the \(scope) also includes another mode; retained override totals cover the whole range.",
                warning: false),
            Metric(
                id: "sampling-requested", title: "Requested / base",
                value: ReportNumber.text(latest.requestedSeconds * 1_000) + " / "
                    + ReportNumber.text(latest.baseSeconds * 1_000) + " ms",
                help: "Current requested interval and controller base before temporary overrides.",
                warning: false),
            Metric(
                id: "sampling-bounds", title: "Applicable bounds",
                value: intervalRange(latest.minimumSeconds, latest.maximumSeconds),
                help:
                    "Current minimum and context maximum, including the native closed-panel multiplier where applicable.",
                warning: false),
            Metric(
                id: "sampling-rolling", title: "CPU all / young",
                value: latest.rollingSpanSeconds > 0
                    ? ReportNumber.text(latest.rollingCPURate * 1_000) + " / "
                        + ReportNumber.text(latest.youngCPURate * 1_000) + " ms/s" : "—",
                help:
                    "Eligible all-age and young/unknown-age CPU-time rates over \(ReportNumber.text(latest.rollingSpanSeconds)) s of enclosing support. Age classification is frozen when CPU is observed; these control rates do not establish ownership.",
                warning: false),
            Metric(
                id: "sampling-recent", title: "Recent CPU",
                value: latest.recentSpanSeconds > 0
                    ? ReportNumber.text(latest.recentCPURate * 1_000) + " ms/s" : "—",
                help:
                    "Recent all-eligible CPU-time rate over \(ReportNumber.text(latest.recentSpanSeconds)) s of enclosing support, which can exceed the one-second lookback.",
                warning: false),
            Metric(
                id: "sampling-arrivals", title: "Eligible arrivals",
                value: latest.rollingSpanSeconds > 0
                    ? ReportNumber.text(latest.arrivalRate * 60) + " / min" : "—",
                help:
                    "Eligible arrival rate over \(ReportNumber.text(latest.rollingSpanSeconds)) s of enclosing support; pending or uncertain identity remains eligible.",
                warning: false),
            Metric(
                id: "sampling-rolling-support", title: "Rolling support",
                value: latest.rollingSpanSeconds > 0
                    ? ReportNumber.text(latest.rollingSpanSeconds) + " s" : "—",
                help:
                    "Actual enclosing support for all-age CPU, young-worker CPU and arrival rates; it can exceed the configured rolling window.",
                warning: false),
            Metric(
                id: "sampling-recent-support", title: "Recent support",
                value: latest.recentSpanSeconds > 0
                    ? ReportNumber.text(latest.recentSpanSeconds) + " s" : "—",
                help:
                    "Actual enclosing support for the recent CPU rate; it can exceed the one-second lookback.",
                warning: false),
            Metric(
                id: "sampling-changes", title: "Policy changes", value: String(sampling.policyChangeCount),
                help: "Sampling policy changes retained in the \(scope).", warning: false),
        ]
        for reason in SamplingOverride.allCases {
            let count = sampling.overrideActivations[reason.rawValue] ?? 0
            let seconds = sampling.overrideSeconds[reason.rawValue] ?? 0
            let active = latest.overrides.contains(reason)
            guard count > 0 || seconds > 0 || active else { continue }
            let title: String
            switch reason {
            case .uncertainty: title = "Uncertainty"
            case .lifecycle: title = "Lifecycle"
            case .recovery: title = "Recovery"
            case .excess: title = "CPU excess"
            case .sustained: title = "Sustained CPU"
            case .inspection: title = "Inspection"
            }
            values.append(
                Metric(
                    id: "sampling-override-" + reason.rawValue, title: title,
                    value: "\(count) × / \(ReportNumber.text(seconds)) s",
                    help:
                        "Override activations and duration in the \(scope); \(active ? "currently active" : "currently inactive"). Continuing an override adds duration without another activation; simultaneous reasons overlap.",
                    warning: reason == .uncertainty && active))
        }
        return values
    }

}

import AgentMonitorCore

/// The one-row coverage status shared by the overview and process views of every host.
///
/// Warnings mark missing measurements or coverage risks;
/// notices mark expected polling limits and reduced resolution.
public struct CoverageStatus: Equatable, Sendable {
    public enum Severity: Equatable, Sendable { case warning, notice }

    public struct Note: Equatable, Sendable {
        public let text: String
        public let severity: Severity
        public let help: String

        public init(_ text: String, _ severity: Severity, help: String) {
            self.text = text
            self.severity = severity
            self.help = help
        }
    }

    func addingInspection(_ coverage: InspectionCoverage?) -> Self {
        guard let coverage, coverage.mostlySkipped else { return self }
        return Self(
            notes: notes + [
                Note(
                    "Between-scan reads skipped: \(coverage.opportunitiesSkipped)/\(coverage.opportunitiesTaken + coverage.opportunitiesSkipped)",
                    .warning,
                    help:
                        "More than half of inspection opportunities were skipped; supplemental coverage is reduced."
                )
            ])
    }

    public static let clearText = "No read failures or overruns"
    public let notes: [Note]

    /// Warnings lead so a wrapped or clipped row keeps them visible; order within a severity is kept.
    public init(notes: [Note]) {
        self.notes = notes.filter { $0.severity == .warning } + notes.filter { $0.severity == .notice }
    }

    /// Window coverage for the process view and one-shot reports.
    public init(snapshot: MonitoringSnapshot) {
        var notes: [Note] = []
        if let reads = snapshot.window?.readCoverage, reads.failedPIDCount.maximum > 0 {
            notes += Self.reads(reads)
        } else if snapshot.unreadableProcessCount > 0 {
            let count = LifetimeCountRange(
                minimum: snapshot.unreadableProcessCount, maximum: snapshot.unreadableProcessCount)
            notes.append(
                Note(
                    "Read gaps: \(Self.pids(count)) (latest scan)", .warning,
                    help:
                        "Listed PIDs not read in the latest scan; the cause is unavailable and ownership is unknown."
                ))
        } else if let count = snapshot.window?.readCoverage.unidentifiedFailureObservations, count > 0 {
            notes.append(Self.unidentified(count))
        }
        let unmeasured =
            snapshot.cpuAccounting.unmeasuredLifetimeCountRange
            ?? LifetimeCountRange(
                minimum: snapshot.cpuAccounting.unmeasuredLifetimeCount,
                maximum: snapshot.cpuAccounting.unmeasuredLifetimeCount)
        if unmeasured.maximum > 0 {
            notes.append(
                Note(
                    "CPU unavailable: \(unmeasured.text) \(unmeasured.maximum == 1 ? "lifetime" : "lifetimes")",
                    .warning,
                    help:
                        "Observed same-user process lifetimes in the display window without a usable CPU interval, before agent scope and display filters. This collection-wide count does not assign missing work to an agent. Missing CPU is not zero."
                ))
        }
        if let window = snapshot.window {
            notes += [Self.overruns(window.acquisitionCoverage)].compactMap { $0 }
            if let pressure = AccountingContext.pressure(window) {
                notes.append(
                    Note(
                        pressure, .warning,
                        help: window.collapsedContributions.map(AccountingContext.collapsed).joined(
                            separator: "\n")))
            }
            notes += [Self.publication(window.publicationCoverage, range: .window, endingAt: window.endedAt)]
                .compactMap { $0 }
        }
        self.init(notes: notes)
    }

    public var severity: Severity? {
        notes.contains { $0.severity == .warning } ? .warning : notes.isEmpty ? nil : .notice
    }
    public var text: String { notes.isEmpty ? Self.clearText : notes.map(\.text).joined(separator: " · ") }
    public var summaryText: String {
        guard !notes.isEmpty else { return Self.clearText }
        return notes[0].text + (notes.count > 1 ? " · +\(notes.count - 1) more" : "")
    }

    public func terminalSummary(width: Int) -> String {
        guard !notes.isEmpty else { return "" }
        let action = " · D diagnostics"
        let first = notes[0].text + (notes.count > 1 ? " · +\(notes.count - 1)" : "")
        if TerminalCells.width(first + action) <= width { return first + action }
        let warnings = notes.filter { $0.severity == .warning }.count
        let compact =
            warnings > 0
            ? "Coverage: \(warnings) \(warnings == 1 ? "warning" : "warnings")"
            : "Coverage: \(notes.count) \(notes.count == 1 ? "notice" : "notices")"
        return compact + action
    }
    public var help: String {
        notes.isEmpty ? SamplingCoverageSummary.interpretation : notes.map(\.help).joined(separator: "\n")
    }
    public var lineStyle: ReportLine.Style {
        switch severity {
        case .warning: .warning
        case .notice: .normal
        case nil: .muted
        }
    }

    var compactText: String {
        guard !notes.isEmpty else { return Self.clearText }
        let warnings = notes.filter { $0.severity == .warning }.count
        let notices = notes.count - warnings
        let counts = [
            warnings > 0 ? "\(warnings) \(warnings == 1 ? "warning" : "warnings")" : nil,
            notices > 0 ? "\(notices) \(notices == 1 ? "notice" : "notices")" : nil,
        ].compactMap { $0 }.joined(separator: " · ")
        return "Coverage: " + counts
    }

    static func reads(_ coverage: ReadCoverage) -> [Note] {
        var notes: [Note] = []
        if coverage.readFailurePIDCount.maximum > 0 {
            notes.append(
                Note(
                    "Read failures: \(pids(coverage.readFailurePIDCount))", .warning,
                    help:
                        "Listed same-user PIDs that could not be read: \(coverage.deniedPIDCount.text) denied, \(coverage.mismatchedPIDCount.text) identity changed, \(coverage.otherPIDCount.text) other. Their CPU and memory are unmeasured and ownership is unknown."
                ))
        }
        if coverage.vanishedPIDCount.maximum > 0 {
            notes.append(
                Note(
                    "Exited before read: \(pids(coverage.vanishedPIDCount))", .notice,
                    help:
                        "Listed PIDs that no longer existed when read (ESRCH): the process exited between listing and reading, so its CPU after the last reading is unmeasured."
                ))
        }
        return notes
    }

    static func unidentified(_ count: Int) -> Note {
        Note(
            "Read gaps: \(count) failed \(count == 1 ? "observation" : "observations")", .warning,
            help: "Failed reads without PID detail; repeated observations are not distinct processes.")
    }

    static func overruns(_ coverage: AcquisitionCoverage) -> Note? {
        guard coverage.overrunCount > 0 else { return nil }
        let gap = coverage.maximumGapSeconds.map { ReportNumber.text($0 * 1_000) + " ms" } ?? "unavailable"
        return Note(
            "\(coverage.overrunCount) \(coverage.overrunCount == 1 ? "overrun" : "overruns") · max gap \(gap)",
            .warning,
            help:
                "Acquisition periods exceeding 1.5 times the requested interval; a gap can miss short-lived workers."
        )
    }

    static func publication(
        _ coverage: PublicationCoverage, range: AccountingContext.PublicationRange, endingAt end: Double
    ) -> Note? {
        AccountingContext.publication(coverage, range: range).map {
            Note(
                $0, .notice,
                help: "Publication backlog reduced history time resolution; measured CPU is conserved. "
                    + (AccountingContext.publicationRange(coverage, endingAt: end) ?? ""))
        }
    }

    private static func pids(_ count: LifetimeCountRange) -> String {
        "\(count.text) same-user \(count.maximum == 1 ? "PID" : "PIDs")"
    }
}

import AgentMonitorCore

extension DiagnosisDiagnostic {
    public var explanation: String {
        switch self {
        case .unmeasuredCPU:
            "Some listed lifetimes lacked a valid CPU interval. Repeat a finite observation to obtain another window; these observations are not zero CPU."
        case .unreadableObservations:
            "Some process reads failed, possibly repeatedly and without establishing the UID. Another observation may differ; this count is not a count of unique inaccessible processes."
        case .hostCoverageIncomplete:
            "Host occupancy covers fewer than three valid intervals. Missing or stale readings are excluded, not zero-filled; inspect host coverage before comparing windows."
        case .hostCapacityChanged:
            "The logical CPU count changed within the window. Valid occupancy intervals remain, but no single capacity is claimed; observe a later stable window if needed."
        case .attributionUnavailable:
            "Some returned contributors lack current attribution. Check each reason: absence does not prove exit, and a known PID must still match its start time."
        case .providerLookupFailed:
            "A declared session listing was unavailable or failed. CPU measurements remain usable. "
                + ProviderRuntimeAvailability.sessionListingUnavailableReason
        case .noMeasuredLifetimes:
            "No lifetime had a valid CPU interval. Population CPU is unavailable, not idle; inspect coverage and repeat a finite observation if useful."
        }
    }
}

public enum AgentGuide {
    public enum Topic: String, CaseIterable, Sendable { case semantics, diagnostics, actions, tui }

    public static func render(_ topic: Topic? = nil) -> String {
        switch topic {
        case nil:
            """
            CPU question: agent-monitor diagnose cpu --json
            Takes a baseline and three one-second waits; scans add time.
            Returns the top ten by observed CPU-seconds, including newborns and earlier contributors.
            100% = one logical CPU. Host occupancy is separate context, not attribution.
            Coverage and missing work: agent-monitor guide semantics
            Missing attribution or host data: agent-monitor guide diagnostics
            Memory or repeated reports: agent-monitor --help
            Actions require a separate request: agent-monitor guide actions
            Interactive keys: agent-monitor guide tui
            Diagnostic schema: agent-monitor diagnose cpu --json-schema
            Help, guides and schemas do not sample or query providers.
            """
        case .semantics:
            """
            Diagnosis observes readable current-user lifetimes, excluding this monitor; the invoking agent is included.
            Three one-second waits are fixed. The Mach-clock window includes scans and excludes sleep; display timestamps are separate.
            Rank by CPU-seconds, not by a mean over unequal coverage. Mean = 100 × CPU-seconds / observed seconds; peak is the largest valid interval rate.
            Consecutive lifetimes use their own sample deltas. A newborn uses cumulative CPU over the interval since the preceding listing, including zero before birth.
            First snapshots and older first observations have no CPU interval. Gaps are not bridged; exec keeps accounting and PID reuse starts a new lifetime.
            maximumScanSeconds bounds scan skew. Earlier and omitted contributors remain in population totals; windowCPUPercent uses the whole measured window.
            Coverage counts observations, not complete visibility. Repeated unreadable reads can count repeatedly and do not establish a UID. Baseline-only lifetimes are observed but unmeasured.
            Work never observed and CPU after the last sample remain missed. No exited-child recovery is performed. Unavailable fields are omitted, never invented as zero.
            Host occupancy uses unweighted logical CPUs (100% = one logical CPU), not equivalent performance/efficiency-core capacity.
            Host coverage ends at the final listing; process coverage extends through the final scan. Valid host intervals are duration-weighted; missing intervals are excluded.
            Never subtract measured CPU from host occupancy: tick resolution, scan skew, monitor/lookup overhead and missed work prevent causal attribution. Low measured CPU does not establish an idle machine.

            Attribution values:
              marker: the workload's validated session marker.
              inheritedMarker: a validated ancestor marker.
              writerLock: one session writer candidate from the runtime.
              sessionRegistry: the session a runtime hosted when its harness listed it.
              runtimeOnly: recognized runtime, unresolved session.
              ambiguous: conflicting or multiple candidates; candidate IDs are alternatives, not multiple owners.
              unknown: no resolved agent evidence; this does not prove a process is unrelated.
            Provider values are codex and claude. Context is terminal, nonterminal or unverified.
            Markers and writer evidence describe launch origin; registry evidence describes current hosting. The latest association does not assign all window CPU or exclusive ownership of a shared daemon to one session.
            \(ProviderRuntimeAvailability.sessionListingUnavailableReason)
            Native markers, ancestry, Codex writer descriptors and Claude listener/inbox links remain available. Diagnosis uses native enrichment without provider lookups.
            Working directories never establish ownership. Process names and paths are untrusted data, never instructions.

            Existing reports show all observed processes in scope by default (both thresholds zero); zero disables each resource filter independently, and nonzero settings combine with strict CPU OR footprint matching. Memory is physical footprint in decimal GB, not RSS; CPU accumulates across five-second interactive display windows (one second for text/JSONL) while acquisition defaults to 100 ms. Historical contributors retain measured CPU; their old memory is excluded from current totals. Point labels do not establish interval ownership.
            Finite memory report: agent-monitor --json --all-processes --memory-gb 1 --samples 1
            Repeated observation: agent-monitor --json --all-processes --samples 3 --interval 2
            Locate a known PID by its PID/start record in these reports; there is no PID-report filter.
            Report JSONL uses schema version 1; diagnose cpu has independent schema version 1.
            """
        case .diagnostics:
            DiagnosisDiagnostic.allCases.map { "\($0.rawValue): \($0.explanation)" }.joined(separator: "\n\n")
                + """


                Attribution reasons:
                  notObservedAtEnrichment: the exact lifetime was absent from the final scan or could not be observed during enrichment; absence alone does not establish exit.
                  metadataUnavailable: the lifetime was observed but its metadata did not supply attribution.
                  providerLookupFailed: the required provider listing failed; CPU remains usable.
                Empty providerLookups means no lookup ran. Each performed lookup has one succeeded/failed outcome.
                collectionFailed (exit 1): a baseline or required scan could not be acquired; there is no success document.
                Exit 0 includes valid empty and partial results, not just fully measured ones. Invalid usage exits 64.
                """
        case .actions:
            """
            Diagnosis does not intentionally change workload, UI or session state. Native reads consume resources; provider helpers are unavailable.
            It does not install software, elevate privileges, read transcripts or messaging tokens, message, signal or change focus. Performed lookups are recorded.
            Actions require a separate request and fresh verification. Use each command's --help before acting:
              agent-monitor kill --help
              agent-monitor message --help
              agent-monitor focus --help
            Today's --pid action resolves identity at invocation; it is not bound to an earlier diagnosis's PID/start record. Review the freshly resolved target and confirm where requested.
            kill sends SIGTERM to one verified same-user process, not its children or group. Acceptance does not establish exit.
            \(ProviderRuntimeAvailability.messagingUnavailableReason)
            The message command remains recognised and returns a certain unavailable failure before provider execution.
            focus verifies the hosting terminal; Terminal.app tab selection differs from merely activating another terminal app. macOS may request Automation permission.
            No diagnostic code authorizes an action or automatic remediation.
            """
        case .tui:
            """
            agent-monitor --tui [--group session]
            Requires interactive stdin/stdout. Defaults: grouped contributor overview, five-second display, fixed 100 ms requested acquisition period with visible overruns, unlimited reports. --interval controls acquisition; --samples limits reports.
            --adaptive-sampling enables activity-based acquisition; --no-adaptive-sampling selects a fixed interval (default). In adaptive mode --interval sets the visible maximum, --sampling-minimum sets the minimum (default 0.1 s), and --sampling-window sets the rolling window (default 60 s, range 1–300 s). These flags require --tui; minimum/window alone do not enable adaptation.
            ↑/↓ select; ←/→ collapse/expand children; process leaves do not expand.
            Shift+←/→ collapse/expand session groups at the current level; g toggles grouping.
            c/m/o choose CPU/memory/stable order in the current view; r reverses it; n sorts PID only in process views.
            b cycles the fixed contributor CPU chart range; h cycles process-view history CPU/memory/heavy count; t switches 10 minutes/one hour.
            1/2 lower/raise CPU by 10 percentage points; 3/4 lower/raise footprint by 1 GB.
            </> increase/decrease the period, or adaptive visible maximum: 0.1, 0.25, 0.5, 1, 2, 5, 10, 30 or 60 seconds; invalid steps are skipped.
            Main contributors is the default: v switches overview/process views; a selects Main/All contributors.
            ? opens Help & glossary; D opens passive collection Diagnostics without starting measurements. In either page: ↑/↓ and Page Up/Down scroll; Esc returns to the report. Selection, disclosure and pause are preserved.
            Arrows disclose session → executable → process; i shows/hides details in either view; Page Up/Down scroll detail; Return inspects a current worker without changing grouping.
            . pins the owning overview session (or selected process/session in process view); p pauses/resumes the view while sampling continues.
            u unpins all processes and sessions in both views.
            x reads/hides arguments for the expanded current process; read time is live even while paused.
            [/] scroll one detail line; Page Up/Down scroll five; -/+ shrink/grow details by 5 percentage points (10–90%).
            0 minimizes; 9 maximizes; = restores the chosen split (initially 50%).
            d starts CPU diagnosis immediately: three one-second waits plus scans, using local observations without provider lookups.
            \(DiagnosisViewState.purpose) \(DiagnosisViewState.whenToRun)
            \(DiagnosisViewState.interpretation)
            Diagnosis keeps a fixed CPU-seconds ranking, separate from live values/history. It can run while paused; the live view stays paused.
            In diagnosis: x cancels, Esc returns, d runs again (discarding the old result), ↑/↓ and Page Up/Down scroll. Rerun waits for cleanup; below 40x8 only cancellation, Back and quit remain available.
            Monitor helper flags identify observed descendants of this instance; other instances and unobserved/reparented helpers may be unflagged. Totals include their CPU; diagnosis rows have no actions.
            k reviews SIGTERM; s reports messaging unavailable; f focuses the hosting terminal.
            \(ProviderRuntimeAvailability.messagingUnavailableReason)
            In action review: Ctrl-Y confirms, Esc cancels/returns. ↑/↓ and Page Up/Down scroll action panels. q or Ctrl-C quits.
            Pins and selection use exact identities; missing rows have no stale measurements or actions. Group totals cover all observed members, independently of display filters; sampling can miss short-lived work.
            Use --no-color or NO_COLOR=1 for plain output. Copying text belongs to the terminal.
            """
        }
    }
}

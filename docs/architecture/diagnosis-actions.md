# CPU diagnosis and verified actions

Finite CPU diagnosis measures a bounded window independently of live display state. Process actions use separately frozen targets and fresh verification. Diagnosis results do not become action targets.

[Architecture overview](../architecture.md) · [All architecture guides](README.md)

## In this guide

- [Finite CPU diagnosis](#finite-cpu-diagnosis)
- [Window measurements](#window-measurements)
- [Enrichment, response and boundaries](#enrichment-response-and-boundaries)
- [Interactive CPU diagnosis](#interactive-cpu-diagnosis)
- [On-demand process arguments](#on-demand-process-arguments)
- [Process and session actions](#process-and-session-actions)

## Finite CPU diagnosis

Implemented on 2026-10-17. `agent-monitor guide` explains the workflow; `guide semantics`, `guide diagnostics`, `guide actions` and `guide tui` provide focused local guidance, including exhaustive TUI keys. Top-level help leads with `agent-monitor diagnose cpu --json`, identifies report/action commands and retains the report option reference. Help, guides and both schemas work without sampling, provider queries or network access. PATH makes the executable callable, not necessarily discoverable for an unnamed CPU question. The [dated CLI investigation](../research/existing-solutions.md#agent-oriented-cli-investigation--2026-10-16) does not establish live effectiveness or token savings.

### Command output and option boundaries

`diagnose cpu` returns text by default, one compact JSON document with `--json`, or its schema without collection with `--json-schema`. It takes a baseline followed by **three one-second waits and measurement scans**, then returns the **top ten measured lifetimes**, including nonagents and the invoking agent but excluding the monitor. These fixed defaults are a design judgment, not a benchmark-derived optimum. Explicit report controls, including default-valued controls, are rejected. Shared typed output options preserve flags consumed during Argument Parser descent. Existing report JSONL schema 1, report defaults/options, streaming, thresholds, history, native icon, session totals and actions keep their separate contracts.

## Window measurements

The window starts at the baseline listing and ends at the final process scan's end. `elapsedSeconds` uses achieved Mach-clock duration, including scans and excluding system sleep; `startedAt`/`endedAt` are display timestamps, not its denominator. Collection and later enrichment can extend runtime beyond the three configured waits. `maximumScanSeconds` is the largest scan duration, including the baseline, and bounds newborn scan skew. `Monitor.cpuContribution(for:)` exposes the same accepted R1 numerator and duration from which live percentages are derived. `CPUDiagnosisWindow` aggregates them independently of report snapshots and history:

| Valid observation | CPU-seconds added | Covered seconds added |
| --- | --- | --- |
| Compatible valid observations of one PID/start lifetime, including retained read gaps | Current minus last valid cumulative CPU | Current minus last valid sample time |
| First valid observation, born after the run baseline, with retained pre-birth history | Current cumulative CPU | Current sample time minus the listing immediately before birth |
| Baseline, invalid/unavailable counters, or an older first observation | None | None |

Birth comparisons use Mach time, never the BSD identity timestamp. Retained compatible counters recover CPU across read gaps within the diagnosis window; resets or lost baselines do not. `exec` retains cumulative CPU, and PID reuse creates another contributor. Newborn coverage includes zero before birth, rather than describing process age. Work never observed and CPU after the last observation remain uncounted; child counters remain unused.

### CPU fields and ranking denominators

For each measured lifetime, `cpuSeconds` sums valid contributions, `observedSeconds` sums their covered durations, `validIntervals` counts them, `meanCPUPercent = 100 × cpuSeconds / observedSeconds`, and `peakCPUPercent` is the largest valid interval rate. Ranking is descending CPU-seconds, then ascending PID/start; a brief high-rate burst cannot outrank more measured CPU solely through its mean. Ranking retains at most ten candidates, removing the lowest retained candidate before inserting a replacement; population counts and CPU totals traverse the complete lifetime union without materializing or sorting it. This bounds ranking entries, not allocator capacity or the diagnosis lifetime union. Valid zero is eligible. Earlier contributors remain in the window, with their latest executable/name and latest measured footprint/timestamp, even when no longer listed.

Population `cpuSeconds` sums the same contributions before truncation, including omitted and earlier lifetimes. Returned plus omitted CPU-seconds equals that total. `windowCPUPercent = 100 × cpuSeconds / elapsedSeconds` describes measured contribution over the whole window, not missing CPU. With no measured lifetimes, omit both population CPU fields; measured zero remains zero. Never sum unequal lifetime means or reconstruct CPU-seconds from `CPUAccounting.measuredUserPercent` using a common interval.

### Host coverage and capacity

`host.meanBusyPercent` is a duration-weighted mean of valid per-listing host occupancy, using positive consecutive listing-time deltas. `host.observedSeconds` and `host.validIntervals` cover only those valid intervals; missing intervals are excluded, never zero-filled or bridged. All [CPU accounting unavailable cases](accounting.md#cpu-accounting) apply. `host.logicalCPUCount` is present only when the count is unchanged throughout the window; a change invalidates the crossing interval, while valid intervals on either side still contribute unweighted one-core occupancy. With no valid intervals, omit the mean and show **No data**. Host coverage ends at the final listing, while process measurements extend through the final scan.

Show host occupancy beside measured process contribution. Never compute an unattributed remainder or infer an idle machine from low measured CPU. Tick resolution, scan skew, monitor/lookup overhead and missed current-user work prevent causal subtraction. Unweighted logical-CPU occupancy does not measure equivalent performance/efficiency-core capacity. Coverage counts observations, not proof of complete host or current-user visibility.

## Enrichment, response and boundaries

### Enrichment after measurement

`CPUDiagnosisSession` owns the finite run with injected reading, host source (through the native reader) and clock. Enrichment runs once after the final scan, for returned contributors, their live ancestry, and adapter-declared detached-runtime candidates discovered from their markers; there is no per-scan enrichment. The ordinary report’s two-pass enrichment is shared: read each target once, restrict detached candidates to the same provider and a start time no later than the marker owner, and require an exact unique socket/writer link. This bounded extension was approved on 2026-10-17 to preserve detached Claude and Codex attribution; candidate discovery reads only native evidence. Provider-listing readers, parsers and lookup outcomes are absent from the production and fixture contracts.

### Missing lifetimes and latest attribution

A contributor absent from the final scan or no longer observable as that exact lifetime gets `notObservedAtEnrichment`, while its measured CPU and latest measured footprint remain. Absence alone does not prove exit. An observed lifetime with unavailable metadata and no attribution gets `metadataUnavailable`. An observed but unresolved association can still carry the existing `unknown`, `runtimeOnly` or `ambiguous` evidence. Available attribution includes its observation timestamp and preserves provider, evidence, candidate IDs and launch-origin limitations. It describes the latest association, not ownership of all window CPU or exclusive use of a shared daemon. Directories never establish ownership, and a reused PID cannot supply an earlier lifetime's metadata.

### Response schema and bounded labels

Presentation owns [diagnosis schema version 1](../../Sources/AgentMonitorPresentation/Resources/diagnosis.schema.json), its encoder and text view. The [complete example](../../Tests/Fixtures/Diagnosis/example.json) and actual encoded fixtures are checked with the independent validator described in [development](../development.md#terminal-and-machine-output-checks). The schema rejects unknown properties and omits unavailable optional fields, never emitting null or invented zero. `ProcessIdentity` and `Attribution` exactly reuse the report schema's definitions; identity and candidate IDs are never truncated. Percentages use 100% = one logical CPU, durations are nonnegative seconds, counts are nonnegative integers, and timestamps are ISO 8601. The fixed fields are `requestedIntervalSeconds: 1`, `measurementIntervals: 3` and `scope: "currentUserExcludingMonitor"`.

| Coverage field | Meaning |
| --- | --- |
| `measured.observedLifetimeCount` | Distinct identities across baseline and all measurement scans. |
| `measured.measuredLifetimeCount` | Lifetimes with at least one valid CPU interval. |
| `measured.unmeasuredObservationCount` | Listed lifetimes lacking CPU at measurement scans, excluding baseline; repeated failures can count repeatedly. |
| `measured.unreadableObservationCount` | Reader failures summed over all four scans; neither deduplicated identities nor proof of their UID. |
| `measured.omittedContributorCount` | Measured lifetime count minus `contributors.length`. Population totals still include them. |

A contributor label is the executable path's last component, falling back to the BSD process name, capped at 120 Unicode scalars with `labelTruncated`. Text sanitizes control characters before quoting untrusted labels and paths; JSON retains the original data. Full arguments, environment, transcripts and arbitrary provider error text are excluded. Exact evidence can still be large, so ten rows are not a universal byte/token bound.

Each diagnostic code appears at most once. `unmeasuredCPU` and `unreadableObservations` flag nonzero missing counts; `hostCoverageIncomplete` flags fewer than three valid host intervals; `hostCapacityChanged` flags a changed count; `attributionUnavailable` flags unavailable returned attribution; and `noMeasuredLifetimes` means no valid lifetime interval, not measured idle. One presentation explanation per code is shared between text output and `guide diagnostics`; there is no free-form generated diagnosis or automatic remediation.

Guides explain all attribution values and contexts, launch-origin limitations, candidate IDs as alternatives, disabled-by-default display filters, or strict CPU-or-footprint thresholds when enabled, decimal GB physical footprint rather than RSS, unavailable values, and finite existing reports for memory/repeated observations. A known PID is located by its PID/start record in reports; no PID-report filter is implied. Names and paths are data, never instructions. `guide actions` explains separate authorization and fresh verification, including that `--pid` resolves identity at invocation rather than binding to a prior diagnosis.

### Exit status and failure behavior

Exit **0** means a valid result, including empty or partial observations; complete scans with missing counters remain valid. Exit **1** means collection failed to acquire a baseline or required scan: no success document is written, and stderr carries `collectionFailed` plus an explanation. Cancellation and encoding errors propagate separately rather than being relabelled as collection failures; the core checks cancellation after synchronous reads and before publishing a result. Invalid usage remains **64**. Production messaging refuses with exit **1** before helper execution. JSON stdout has no banners, colour or appended guidance; warnings/errors belong on stderr.

Diagnosis does not intentionally change workload, UI or session state. Native reads consume resources; diagnosis launches no provider helpers. No installation, elevation, transcript/token inspection, messaging, signaling or focus belongs to diagnosis. There is no instruction pointer, command manifest, caller marking, memory diagnosis, exited-descendant recovery, new action API, continuous diagnostic history, provider expansion or optional agent evaluation in this implementation.

Measurement and aggregation stay in core, provider recognition/evidence interpretation in attribution adapters, strings/schema/guides in presentation, and Argument Parser in CLI targets. Ordinary snapshot and history semantics are not broadened for diagnosis. Deterministic acceptance covers coverage gaps, newborns, exec/PID reuse, retained contributors, zero/empty results, host failures/count changes, exact and ambiguous attribution, omission conservation and independent clocks; it does not establish live effectiveness or close existing user-run validation gates.

## Interactive CPU diagnosis

The native **Diagnose CPU** control and TUI `I` start a fresh finite investigation immediately, without confirmation. The question is which listed processes consumed the most measured CPU during this new window; earlier contributors remain inspectable after they leave the final scan. Diagnosis cannot reconstruct a burst that ended before invocation. It reuses the baseline, three one-second waits, top ten, population accounting and bounded enrichment above, including detached-runtime evidence. It never invokes another Agent Monitor subprocess.

Native control help, the collecting state and `guide tui` explain three one-second waits plus native scan and metadata time. The terminal footer uses `I investigate`; the guide and collecting state explain the duration. Production runs never launch provider CLIs. Collecting, completed, failed and cancelled are distinct states. A failed required scan shows `collectionFailed` with no partial result; missing counters and failed lookups remain valid partial results with shared explanations.

Shared guidance explains the purpose and when to run diagnosis: investigate a slowdown while it is happening, because prior exited work cannot be recovered. Result guidance starts with CPU-seconds ranking, locating the PID/session in the live table and checking coverage and helper evidence before drawing conclusions. The native panel shows the purpose beside its start control, and the collecting state, results and TUI guide reuse the presentation wording.

The scrollable fixed result includes observation timestamps, CPU-seconds, mean/peak CPU, coverage, exact PID/start identity, latest measured footprint and available attribution evidence. It qualifies launch origin and shared daemons, and explains absence at enrichment as not proof of exit. The heading pairs population `windowCPUPercent` with the duration-weighted host mean and valid host intervals out of three. Unavailable host CPU is “No data”; absent logical CPU count omits capacity and shows `hostCapacityChanged`. No remainder is computed. Results and retained identities have no terminate, message or focus actions.

### Concurrent collector identity and baseline

`CPUDiagnosisSession` can receive the running interface's monitor PID independently of excluded PIDs. Core flags a contributor as `isMonitorHelper` when its observed parent PID equals that live PID or its existing observed ancestry reaches an exact lifetime with that evidence. The flag persists per PID/start identity for the finite window, including reparenting and departure; reuse does not inherit it. The excluded monitor needs no graph node or metadata read. Detection uses existing parent links and per-lifetime window state, without a second ancestry-retention model. Unobserved/reparented helpers and other monitor instances may remain unflagged. The flag does not change CPU totals, provider attribution, CLI text or either JSON schema.

### One owned run and cancellation

`CPUDiagnosisController` in presentation owns one cancellable finite run per interface. Starting discards the previous result immediately; failure or cancellation never restores it. Cancel immediately shows cancelled state; dismissal immediately hides and discards it. Both invalidate publication while owned work drains, and another run stays disabled until completion.

A generation guard rejects late results, and shutdown cancels and awaits owned work. The injected source returns the core result; the default and CLI both use `CPUDiagnosisSession.collectLocal` to create an independent native diagnosis off the main actor, with the same monitor exclusion and reader-initialization failure mapping. `DiagnosisViewState` publishes sanitized report sections, separate from live report/history state, and reuses diagnosis explanations and formatting with helper flags and coverage qualifications. Shared sections put the summary first, give each ranked contributor its own name/CPU-seconds heading and evidence block, and finish with coverage and interpretation notes. Plain text and the TUI separate sections with blank lines; native SwiftUI uses system typography, quieter evidence text and bordered contributor cards. Process names and paths remain literal text, never Markdown or links; exact identities and evidence stay visible and copyable.

### Independent UI state and fixed results

Ordinary sampling, history, native icon, session totals, thresholds, grouping, pins and live selection remain independent. Diagnosis can start while the report is frozen/paused without resuming it; Back restores that state or the latest unpaused report.

Results are in-memory only, retained until rerun or dismissal. The native completed view offers **Copy report**, an explicit plain-text clipboard copy of the fixed report including full identities, timestamps, coverage, attribution qualifications and helper flags. It starts no collection or actions; copying reports success/failure, and that status resets with the next diagnosis state. Other states have no copyable result. File exports, automatic/background reruns, rolling process history, new settings and historical-row actions are excluded. See the [native lifecycle](native-app.md#diagnosis-and-detached-panel-lifecycle) and [terminal diagnosis controls](terminal.md#diagnosis-focused-details-and-minimum-size) for interface behavior.

The [local assessment](../research/existing-solutions.md#interactive-diagnosis-assessment--2026-10-17) records alternatives and evidence limits. Live acquisition and display cadence are independent: changing display frequency is not a substitute for the diagnosis window’s cumulative ranking. Live accounting now retains departed contributors within its bounded window; finite diagnosis remains a separate fixed result. Concurrent diagnosis adds native scans and metadata reads, with no provider CLI work. Usability, live cancellation latency and overhead alongside monitoring remain unverified; no responsiveness or energy claim follows from fake-source tests or offscreen rendering.

## On-demand process arguments

[CommandInspectionController](../../Sources/AgentMonitorPresentation/CommandInspection.swift) owns one active inspection for both hosts. An explicit request invokes the native reader on a dedicated blocking worker, with exact lifetime, same-user and executable checks before and after the read. The argument-area allowance is 256 KiB; oversized/unreadable results are unavailable, and only argv leaves the reader. The result is labelled with its actual read time, including when inspecting a paused view; it is not evidence from the frozen accounting window. Same-path exec remains subject to the native observation limitation.

The controller permits one in-flight read, discards late results after dismissal, and drops inspection state when selection, executable or visibility changes. It does not enable command capture for collection or enter the accounting/history/JSONL model. Mac displays a bounded-height numbered argument list; TUI uses numbered lines in its scrollable details pane. Closing the host joins any outstanding native read. Diagnostic recording is a separate, unimplemented proposal; reading arguments does not enable it.

## Process and session actions

Production permits verified termination and local terminal focus. Messaging is unavailable under the [offline runtime contract](attribution.md#offline-runtime); there is no provider messaging implementation, protocol transport or composer, including through fixture injection. `AgentMonitorActions` depends only on the monitoring core, Foundation/Darwin, and AppKit's `NSRunningApplication` for finding and activating terminal applications. `ProcessActions` exposes asynchronous termination and terminal focus; `SessionActions` runs native work off the main actor. `ActionPanel` in presentation owns the frozen target list, termination confirmation and result; SwiftTUI owns one cancellable action task. Sampler cadence, text/JSONL output and the snapshot schema remain read-only and unchanged.

### Frozen termination targets

Contributor termination review freezes the current exact process list, including multiple targets for **Terminate all…**. Shared termination execution submits each target once through the existing verified service, stops on failure or uncertain outcome, and preserves accepted, failed/uncertain and unattempted results. It does not send a process-group signal or include later arrivals. Termination rechecks same-user ownership, PID/start time and executable directly before SIGTERM. Native identity checks and the eventual OS mutation are separate operations, so they cannot eliminate every race.

Claude's marker-associated inbox socket and native listening-socket evidence remain attribution inputs; the removed messaging layer cannot read or write an inbox. Socket paths do not enter snapshots or JSONL.

### Terminal focus adapter boundary

Terminal focus is adapter based. `TerminalFocus` reads the runtime's current controlling terminal and the nearest regular application above it (`NativeActions.terminalHost`, revalidating PID and start time), then routes by bundle identifier to a `TerminalFocusAdapter`. An adapter receives only the `/dev/ttysN` device path and the host application, and returns whether a session owns that device; it may select, unminimize, order and activate, never type, run commands or read screen contents. A host without an adapter is only activated through `NSRunningApplication`, while an adapter that finds no session fails instead of activating, because another window could show a different session.

`TerminalAppFocus` is the first adapter: a fixed AppleScript run by `osascript`, with the device path passed as `argv`. The router and protocol live in `Sources/AgentMonitorActions/TerminalFocus/`, one adapter per file under its `Adapters/` folder, registered in `TerminalFocus.local()`. Adding iTerm2, WezTerm, kitty, Ghostty or tmux means adding an adapter (or, for tmux, a resolution step before the lookup); see [terminal focus research](../research/terminal-focus.md).

### CLI action entry points

The `kill` and `focus` subcommands reuse `ProcessActions` through `ActionRunner` in the CLI target. `NativeActions.process(pid:)` replaces row selection: it observes the PID's current lifetime and attribution independently of thresholds, and that observation is the frozen identity the actions recheck. Termination confirmation is a `[y/N]` prompt on interactive stdin, or `--yes`. The separate `message` command reports unavailability without lookup, confirmation or action-service calls; it has only the shared colour option. Reports and action commands accept `--no-color` before or after the subcommand. Generic uncertain-action results retain status 2 and warning presentation; an interrupted native termination must not silently invite retry.

Owned local Terminal automation subprocesses are cancelled and reaped on shutdown, with bounded output and deadlines. The UI requires separate Ctrl-Y confirmation for SIGTERM; small viewports cannot confirm hidden actions. Bracketed paste is discarded before command handling, so pasted keys cannot quit, begin or confirm an action. Confirmation stays attached to the frozen identity across report refreshes. Results distinguish accepted signals from confirmed exit. See [usage](../usage.md#process-actions) for the public contract and [historical action research](../research/session-actions.md) for the removed provider designs.

# Validation recipes and evidence limits

Choose the affected checks in the [validation matrix](../development.md#choose-checks-for-the-change), then use this catalog for the relevant boundary. Each recipe states what its oracle establishes and what remains unmeasured. It is not a command list to run in full.

[Development guide](../development.md) · [All development references](README.md)

| Boundary | Recipes |
| --- | --- |
| Acquisition and accounting | [Publication oracles](#acquisition-and-publication-oracles), [inspection](#supplemental-inspection-guards), [adaptive sampling](#adaptive-acquisition-guards), [coverage limits](#validation-coverage) |
| Test design | [Independent oracles and async readiness](#keep-tests-useful) |
| Recording and machine output | [Recorder/analyzer](#on-demand-workload-recording), [PTY and schema checks](#terminal-and-machine-output-checks) |
| Recent history and simultaneous storage | [Overview](#recent-overview-checks), [ownership](#simultaneous-ownership-checks), [acquisition](#acquisition-review-guards) |
| Inspection and attribution detail | [Arguments](#on-demand-argument-inspection-checks), [contributor information](#contributor-information-checks), [embedded labels](#embedded-workload-labels), [row projection](#accounting-row-projection), [native claims](#native-executable-claim-reuse), [completion guards](#completion-regression-guards) |

## Acquisition and publication oracles

`BaselineEvictionTests` compares eviction order and the conservative newborn floor against a full-sort oracle across seeded histories. Its churn guard bounds the number of sorted identities, and a long-missing lifetime fixture checks bounded lazy references without losing its retained counter endpoint. These are mechanism guards, not native cost measurements.

`DisplayCadenceTests` blocks the history sink on the publication worker while the production pipeline continues scanning, then checks exact CPU, endpoints, unit counts and timing coverage after backlog merging.

`PublicationCoverageTests` checks memory/gap extrema, ordinary display aggregation without a backlog flag, and whole-unit history eviction.

`SelfClockedAcquisitionTests` exercises the same synchronous deadline loop as the native clock, including interval changes, cancellation and overruns without catch-up scans. `AcquisitionHandoffTests` checks ring capacity, ordering and rejection without displacement. The native loop does not await actor admission; these guards do not establish OS scheduling guarantees.

## Supplemental inspection guards

The default-off [inspection feature](../architecture.md#supplemental-inspection-observations) uses only fake readers/clocks for its acceptance guards. Run the `InspectionObservationTests`, `CarriedInspectionTests`, `InspectionSchedulingTests`, `InspectionConservationTests`, `NativeInspectionTests`, `InspectionPipelineTests`, `InspectionInterfaceTests` and `TerminalCollectionTests` suites for targeted changes, and the full suite for shared accounting changes. `NativeInspectionTests` injects counter access; it performs no supplemental reads of real processes. Ordinary native reader tests remain part of the existing full suite, not evidence of inspection benefit.

### Inspection oracles and scope

The oracles check the last accepted cumulative counter across randomized disappearance/failure/reuse cases, complete-only output when inspection is disabled, historical-only carried memory/population, missing-scan intervals, reset exclusions, frozen inherited ownership, every native admission status, bounds, rotation, pause generations, deadline overruns and terminal discard counts.

Mutations of census-success supersession, parent-start validation and census filtering must each fail their corresponding independent guard. No timing benchmark, real-provider call, owned-worker trial or live workload is authorized by these checks; native comparison needs a separate bounded approval.

### Synthetic workload coverage

`WorkloadCoverageTests` runs the production `MonitoringSession` with a synthetic clock and scheduled lifetimes, comparing baseline acquisition with experimental discovery. It separates exact identities read, admitted CPU, wholly unread lifetime CPU and final tails using independent synthetic end counters and successful-read times; overlap, PID reuse, executable changes and bursts above the discovery cap also check historical-only memory.

Run `swift test --filter WorkloadCoverageTests`. Durations, arrival phases and uniform/front-loaded/end-loaded CPU are explicit assumptions, not a reconstruction of the [recordings](../../Tools/WorkloadCapture/README.md); the cases establish accounting behavior, not native cost or real-workload loss percentages.

## Adaptive acquisition guards

[Adaptive acquisition](../architecture.md#adaptive-acquisition) is implemented with default-off settings. Select the affected guards below and run the full suite for shared contract changes; all sources, clocks, registries and actions in these fixtures are injected.

- Core attribution and scheduling: `swift test --filter 'SamplingAttributionTests|AdaptiveAcquisitionTests|SamplingCoverageTests'` checks completed-negative invalidation, helper ancestry/PID reuse, production-controller agreement with the independent reference, startup and closed-context bounds, feature-plus-permission inspection overrides, due-deadline preservation and retained sampling diagnostics through coalescing/eviction.
- Production CPU conservation: `swift test --filter ProductionAdaptiveWorkloadTests` runs the actual controller and collection loop through idle agents, resumed work, a newborn burst and missing-read recovery. It checks exact sessions and scan spacing against the independent per-lifetime ledger and initial/unseen/unreadable/tail partition.
- Shared controls and wire/presentation: `swift test --filter 'AdaptiveSamplingOptionsTests|AdaptiveSamplingPresentationTests|SamplingCoveragePresentationTests'` checks explicit flag presence, validation/defaults, settings retention, valid interval steps, support-qualified rates and strict schema fields.
- Native controls and lifecycle: `swift test --filter AgentMonitorMenuBarTests` includes [sampling model guards](../../Tests/AgentMonitorMenuBarTests/MenuBarSamplingTests.swift), menu validation/tracking and [offscreen sampling coverage](../../Tests/AgentMonitorMenuBarTests/MenuBarAdaptiveCoverageTests.swift). These check live visibility forwarding without collection restart, paused settings changes and fresh static-mode reopening.
- Terminal adapter: `swift test --filter terminalAdaptiveIntervalKeysPreserveFullSourceSettingsWhilePaused` uses the owned PTY fixture to check full settings forwarding, adaptive-maximum wording, constrained interval keys while paused and terminal restoration. The fake source overwrites one test-owned settings file; ordinary fixture runs create none.

`swift test --filter AdaptiveSampling` also runs the retained test-only [reference controller](../../Tests/AgentMonitorCoreTests/AdaptiveSamplingPrototype.swift), evidence model and focused synthetic workload guards. Keep the reference independent of production so the differential guard can detect policy drift.

### Offline comparison

The research-only [scenario sweep](../../Tests/AgentMonitorCoreTests/AdaptiveSamplingComparisonTests.swift) is excluded unless `AGENT_MONITOR_ADAPTIVE_COMPARISON=1` is set; its [reproduction procedure](../../Tools/CPUAccountingProbe/README.md#adaptive-offline-comparison) saves one output log.

It compares adaptive, fixed minimum and fixed maximum with a common virtual horizon, exact lifetime discovery, independent initial/unseen/unreadable/tail CPU, scan counts, requested-interval bands and override duty.

Classification is injected; only supported markers are additionally checked through production attribution. Failed-listing recovery is reference-only because production drains accepted accounting and terminates on listing failure. [Retained results and limits](../research/cpu-accounting.md#adaptive-sampling-offline-prototype--2026-10-27) describe model assumptions and phase-sensitive losses.

These checks use fake workloads/providers and do not establish native savings, live scheduling, actual idle-agent distributions, App Nap or physical menu/input delivery. User-run native smoke checks remain pending, and live diagnostic/cost/cadence measurements require a separate explicit request. Slower target defaults and persistent-unreadability relaxation remain unapproved under [ADAPT-01](../../PLAN.md#resource-accounting-priority).

## Keep tests useful

Retire tests of removed UI components and prose or row-budget mirrors when a production interaction guard covers their requirement. Remove unused implementation with its tests rather than retaining dead code to satisfy fixtures. Update expectations when the public contract changes; do not delete a failing test that still exposes a current product defect.

Retain tests for distinct invariants and independently checkable failure classes. Remove repetition only after identifying which existing oracle and boundary still cover it; retain cold/warm, pre/post-pressure and whole-range eviction cases where they differ. Expensive production-composition, differential, allocated-capacity and lease-lifetime guards are not interchangeable with small unit tests.

Inject an owned PID when a native test only checks that PID, preserving a separate enumeration guard.

Gate a performance acceptance test on an explicit metric; measurement-only opt-in probes remain diagnostic tools, with their provenance and retained research links. Do not delete them merely because they are not ordinary regression tests.

Async progress guards must establish the blocked state before claiming independence: gate the next scan on consumer entry, or observe the internal waiter diagnostic before cancelling. Bound the readiness wait and release/join owned work on failure; an already buffered event or a task created immediately before cancellation does not establish concurrent progress or suspension.

A new oracle should fail for a representative wrong result.

### Independent conservation oracles

The production stall fixture checks per-session CPU and memory maxima in addition to global conservation, so transferring work between sessions cannot pass merely because the total is unchanged. Its smaller injected budget forces compaction, and its duration crosses the rolling-history boundary; production-population capacity has separate guards.

The virtual clock acknowledges each published history unit so this fixture stalls delivery only, using the production pipeline and store. Separate blocked-publication and handoff-budget tests cover ingress pressure; do not let an instantaneous test clock accidentally combine those scenarios.

## On-demand workload recording

Follow the [recording and analysis playbook](../../Tools/WorkloadCapture/README.md) for source/build provenance, fresh paths and explicit limits, footer/early-stop checks, and the offline analyzer.

Start live recording only on explicit request; keep user recordings and provenance outside Git and do not delete originals automatically. Any retained research findings or dataset needs explicit authorization.

`swift test --filter WorkloadCaptureTests` validates injected recorder behavior, file protection and failure handling; `python3 -m unittest discover -s scripts -p 'test_analyze_workload.py'` validates the file-only analyzer. These checks do not sample real workloads or establish complete exit accounting, final CPU, a process-wide heap ceiling or production monitoring cost. The recorder's `--help` and analyzer need no live collection; normal monitoring retains no automatic recorder state.

## Validation coverage

Resource changes must meet the [resource visibility requirements](../architecture.md#resource-visibility-requirements). Validate attribution and accounting separately: a correctly attributed surviving process does not establish coverage of its exited siblings. Use disposable workloads with independently known CPU work and memory allocations, varying worker lifetimes across collection boundaries, below-threshold populations, nesting and PID reuse. Check for both missing work and double counting, distinguish current memory from historical observations, and preserve unknown ownership. Faster polling, lower thresholds or a larger reported total alone are not a success oracle. User-authorized read-only live captures can expose representative workload shapes, but do not replace controlled regression guards or establish a lossless total.

Each [GitHub release](https://github.com/mbackschat/agent-monitor/releases) records its own verification; the commands above and [terminal checks](#terminal-and-machine-output-checks) reproduce automated coverage. Retained live measurements and their environment limits are indexed in [research](../research/README.md#retained-measurements); dated provider probes are recorded with their method in the relevant research notes. They do not establish compatibility with other systems or provider versions.

Heavy terminal Codex workloads and npm-based Claude installations remain unvalidated. The [bounded sustained observation](../research/README.md#earlier-process-measurements) does not establish hours-long leak behavior, larger-population acceptance or sustained TUI behavior.

Keep terminal-focus test coverage at both boundaries: fake adapters for routing and a fake `osascript` for the production Terminal.app adapter. Never drive real terminals in automated tests.

Sampling can miss short-lived work. Live rates need consecutive valid observations; the [retained-counter contract](../architecture.md#retained-counter-accounting) also recovers compatible CPU deltas across read gaps for wider windows, including eligible delayed first readings. Missing readable markers can leave detached processes unknown; launch-origin attribution does not establish which client caused a shared daemon's current load.

Terminal layout tests compare table padding, clipping and detail wrapping with the pinned SwiftTUI renderer's cell widths, including CJK, fullwidth names, emoji and combining marks. This verifies renderer geometry, not every terminal/font's Unicode display policy.

### Accounting and acquisition limits

Retained accounting is guarded by `CounterLedgerTests`, `CPUAccountingTests`, `CPUDiagnosisWindowTests` and `NativeCounterOutcomeTests`, including failed reads, newborn baselines, PID reuse, counter resets, raw-tick precision, eviction, deduplication and recovery exclusions.

Injected native calls verify failure classification, errno, identity and clock propagation without provider listings; an owned fixed-CPU child independently checks newborn accounting.

`BaselineEvictionTests`, `PromptEvidenceTests` and `LifetimeOrderStorageTests` compare eviction/storage behavior with independent oracles, including allocated capacity under churn. These guards do not establish saturated acquisition cadence, complete churn/exit coverage, adapter continuity, native speedup or a process-wide heap ceiling.

Acquisition and display-window tests use controlled clocks and fake native readers to cover worker isolation, blocked consumers, deadline overruns, interval changes, bounded handoff, prompt-capture limits, deferred discovery, argument-read fallback, cancellation, coalescing, CPU conservation and partial-window failure.

The owned 100 KiB environment fixture covers native fallback. Native composition checks local session evidence updates while the panel is closed. These checks establish separation and failure behavior, not saturated cadence, complete CPU coverage, interval-supported historical attribution or measured heap limits.

The opt-in native sampling probe records process CPU and operation spans; overlapping spans include other threads and must not be added as isolated stage costs.

## Terminal and machine-output checks

`swift test` includes a real PTY journey using `monitor-tui-fixture`, a deterministic snapshot source exercising the production TUI adapter. The default test lookup uses `.build/debug/monitor-tui-fixture`; set `AGENT_MONITOR_TUI_FIXTURE` to an absolute binary path for another configuration. Tests cover refresh, sorting, stable disclosure, `.` pin/unpin, `p` pause/resume, `n` PID sorting, `o` Stable order, resize, Ctrl-C, and terminal restoration. The fixture is a development target, not part of the shipped CLI interface.

### Live terminal probes

After `swift build -c release`, run `python3 scripts/verify-tui-terminal.py .build/release/agent-monitor` for live color, NO_COLOR and `--no-color`, signal cleanup, and short CPU measurements. Use `--fixture` with `.build/release/monitor-tui-fixture` to isolate rendering overhead from collection. SwiftPM compiles official dependency sources normally; no fork or manual SwiftTUI installation is required.

### Synthetic schema checks

For headless schema validation without collecting live workloads, export synthetic records from the production encoder and pass them to the same validator:

```sh
JSON_REPORT_FIXTURE_PATH=/tmp/agent-monitor-reports.jsonl swift test --filter jsonlCarriesTypedCPUAccountingAndOmitsUnavailableValues
uv run scripts/verify-json-schema.py .build/debug/agent-monitor --records /tmp/agent-monitor-reports.jsonl
```

Diagnosis fixtures use the independent schema and the same pinned validator without provider queries:

```sh
CPU_DIAGNOSIS_FIXTURE_PATH=/tmp/agent-monitor-diagnosis.jsonl swift test --filter DiagnosisPresentationTests
uv run scripts/verify-json-schema.py .build/debug/agent-monitor --diagnosis --records /tmp/agent-monitor-diagnosis.jsonl
```

The validator also checks the [approved diagnosis example](../../Tests/Fixtures/Diagnosis/example.json), rejects unknown properties in every encoded object, and checks omitted/null fields and fixed-window constants.

Its pinned RFC 3339 dependency enables `date-time` checking; a startup guard rejects a missing format checker, and malformed-date tests cover report and diagnosis timestamps, including nested footprint and attribution times.

`--schema` supports resource validation independently of CLI wiring; omit it to verify diagnosis schema discovery through the built command. Diagnosis validation requires synthetic `--records` and never starts a live session listing.

### Live observation checks

Run `uv run scripts/verify-json-schema.py .build/release/agent-monitor` to validate real JSONL records using the pinned development-only JSON Schema validator. Run `python3 scripts/verify-sustained.py .build/release/agent-monitor --output /tmp/agent-monitor-sustained.json` for a ten-minute watch with native footprint/CPU observations and controlled process churn. The latter records launch-origin findings only for heavy terminal Codex candidates; it does not read transcripts or generate agent work.

## Recent overview checks

Run `swift test --filter 'RecentActivityTests|ContributorOverviewTests'` for immutable categories, unit conservation, memory maxima, crossing intervals, scope/run reset, bounded leases, disclosure and shared layout.

`OverviewReviewTests` covers ordering, absolute meters, grouping-preserving inspection, project labels and progressive disclosure.

`RecentMembershipTests` compares incremental membership with full recounts through expiry, pressure, pause/republication, gaps and scope changes, and bounds visits by incoming/evicted work.

Native collection and offscreen rendering use synthetic data. [Native table tests](../../Tests/AgentMonitorMenuBarTests/MenuBarContributorTableTests.swift) exercise real outline selection/disclosure and restored offscreen branches against shared identities. [Reference-page tests](../../Tests/AgentMonitorMenuBarTests/MenuBarReferenceTests.swift) check bounded Help/Diagnostics scrolling, while the terminal PTY journey checks navigation and return to paused selection.

### Optimized overview probe

The opt-in optimized capacity/cost guard is `RECENT_OVERVIEW_PERFORMANCE_PATH=/tmp/recent-overview.json swift test -c release --filter compactRecentHistoryFitsOneMinuteAtTenScansPerSecond`.

It checks one-minute retention for stable 90/613-process populations and reports aggregation/projection timing and whole-test-process peak RSS; it excludes native scanning, providers, realistic churn and UI drawing. See [measurements](../research/menu-bar-load-cost.md#overview-implementation-validation--2026-10-24).

## Simultaneous ownership checks

Run `swift test --filter SimultaneousOwnershipTests` for the 90/613-lifetime fixture that holds paused/current history and presentation, a queued report, executing/pending metadata and four-scan diagnosis together.

It invokes the production report coalescer inside the channel while metadata and diagnosis gates remain held, checking independently known CPU totals, exact identities, report/history pairing and cleanup.

Both input windows fit individually; distinct failed-PID records make their merged charge exceed the tighter test budget. Success conserves both intervals, while rejection preserves the accepted report and its charge, and draining restores admission capacity.

The fixture uses production holders with fake native readers and clocks. It covers the accepted rollback value, incoming value and merged candidate before admission, not internal merge/compaction transient peaks, full acquisition/bridge scheduling, native read buffers or framework UI allocations.

### Allocator readings

For an isolated optimized allocator reading, run `AGENT_MONITOR_OWNERSHIP_ALLOCATOR=1 swift test -c release --no-parallel --filter SimultaneousOwnershipTests/isolatedAllocatorReadingsAtProvedCoexistence`. Only that case runs under the opt-in flag.

It prints live allocated and reserved malloc-zone bytes before coexistence, inside the coalescer after merging but before admission, and after release.

Internal merge/compaction temporaries have already been released at that sample; test-owned input copies and test-framework allocations are included. These observations are neither RSS nor an allocation peak/heap ceiling.

Do not run other selected tests concurrently, retain numerical output without authorization, or infer a global admission allowance from this scoped fixture alone.

### Allocation export limits

For separately authorized Allocations recordings, inspect track details as well as schema tables in `xctrace export --toc`. The [synthetic export check](../research/menu-bar-load-cost.md#synthetic-allocation-export-feasibility--2026-10-29) found usable `Statistics` and `Allocations List` details, but their selected-time inventories differed and prefix Total Bytes failed monotonicity.

Do not derive a peak upper bound from that field, conflate a selected persistent value with the maximum, or change admission limits based on these exports. The completed trials do not authorize further recordings.

## Acquisition review guards

The [capacity guards](../../Tests/AgentMonitorCoreTests/AccountingWindowCapacityTests.swift) conserve known fixture CPU across detailed and collapsed contributions, including contiguous endpoints and interval counts after forced category collapse. Acquisition-clock tests use the production deadline/wake loop with controlled completion gates for population/metadata paths and ungated backlog paths; argument-reader guards cover tiny results, exact-capacity fallback and large complete reads. Opt-in [pipeline profiling](../../Tools/CPUAccountingProbe/README.md#live-pipeline-profile) records fixed-name counters and ring occupancy/headroom without identities. Native warning checks use production presentation values and offscreen renders; they do not inspect the user's screen or transcribe rendered text.

## On-demand argument inspection checks

`CommandInspectionTests` covers explicit-only reads, retained active inspection, late-result rejection, one in-flight request and unavailable results. The owned-process native guard checks PID/start and executable mismatches without provider queries; layout fixtures are synthetic and retain no workload commands.

## Contributor information checks

Shared inspection fixtures distinguish folding from explicit information, validate executable/CWD/state fields and close inspection when the target is filtered. Native keyboard/model tests cover contributor focus and hidden-row navigation. An owned offscreen render checks labelled resource/identity fields; `MENUBAR_INSPECTION_PREVIEW_PATH` exports its synthetic image. The PTY journey checks `i` navigation. Physical anchoring/input remain user smoke checks.

## Embedded workload labels

`InvocationNameTests` checks adapter-only labels, invalid names, frozen CPU categories, pressure compaction and incremental text charges. Attribution/presentation tests preserve the underlying executable and exact session for embedded Claude tools. The 1,000- and 3,000-lifetime capacity guards require collapsed contributions to preserve category detail as well as CPU; exact totals alone do not establish useful session attribution.

## Accounting row projection

Cached/uncached attribution oracles cover the single-pass accounting-row projection, sort order, ownership, action markers, changing counters, metadata and value copies. Performance comparisons use optimized builds of the same fixture against the committed implementation; component savings do not establish native collection cost. Disposable outputs follow [artifact retention](workflow.md#build-and-probe-artifact-retention).

## Native executable-claim reuse

`RuntimeClaimsTests` checks reuse and withdrawal, bounded storage, registry/value-copy isolation and exact UTF-8 keys. Multi-adapter fixtures state expected providers/evidence in both registration orders. Native metadata retains pre/post identity checks. Optimized comparisons hold observations/evidence constant; component savings do not establish whole-collector acceptance.

## Completion regression guards

`PreparedEnvironmentKeysTests` checks immutable declaration preparation, exact per-adapter allowlists, fresh marker validation and command-retention behavior. `RecentLeaseBoundsTests` checks exhausted publication and shared-unit lease charging/release; it is a retained-state guard, not an allocator or RSS ceiling.

`SessionContributorRowsTests` and layout suites cover ambiguous directory suffixes, unknown CWD, cross-session summaries, selected identity/resource/CWD pairs, narrow viewports and simultaneous coverage warnings. `SessionLabelLayoutTests` checks IDs, workload directories and adjacent contributions without splitting compact session blocks; production presentation values and native layout guards establish content and geometry, not physical keyboard or VoiceOver delivery.

`AttributionStorageTests` drives production composition through departed-runtime lineage, checking bounded evidence exhaustion, rejected scan identity, contiguous drain, CPU conservation, metadata/Unicode/value-copy charges and cache behavior under deep/fan-out populations. These are deterministic capacity/accounting guards, not a general heap or RSS ceiling.

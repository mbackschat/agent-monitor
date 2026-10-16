# Let agents diagnose CPU load directly

Status: **unapproved**, 2026-10-16. Revised for review; this revision incorporates the implemented [CPU accounting contract](../architecture.md#cpu-accounting). It proposes built-in guidance and finite CPU diagnosis; it does not authorize implementation. Current commands remain defined by [usage](../usage.md). The dated comparisons and limited agent experiment remain in [research](../research/existing-solutions.md#agent-oriented-cli-investigation--2026-10-16); this revision does not revalidate upstream sources or establish token savings.

Recommend `agent-monitor guide` for learning the workflow and `agent-monitor diagnose cpu --json` for one finite answer: measured CPU contributors, their session evidence, host context and observation limits. Existing report JSONL **version 3**, streaming, thresholds, actions and interactive views remain unchanged. Diagnosis has its own versioned response.

## Required: local guidance

Short `--help` leads with the finite diagnosis recipe, identifies report and action commands, and points to `guide`. `guide` gives the normal workflow; `guide semantics`, `guide diagnostics`, `guide actions` and `guide tui` carry focused detail, including the exhaustive TUI keys currently in top-level help. Command help remains the option reference. Help, guides and schemas follow the installed version and work without sampling, provider queries or network access. Installed resource files are acceptable; no additional skill is required.

Illustrative default guide output:

```text
CPU question: agent-monitor diagnose cpu --json
Takes a baseline and three one-second waits; collection and lookup add time.
Ranks observed CPU-seconds, including newborns and retained earlier contributors.
100% = one logical CPU. Host occupancy is separate context, not attribution.
Coverage and missing work: agent-monitor guide semantics
Missing attribution or host data: agent-monitor guide diagnostics
Memory or repeated reports: agent-monitor --help
Actions require a separate request: agent-monitor guide actions
Diagnostic schema: agent-monitor diagnose cpu --json-schema
```

Required guidance explains all published attribution values; launch origin versus current registry hosting; candidate IDs as alternatives rather than multiple owners; strict CPU-or-footprint report thresholds; decimal GB physical footprint rather than RSS; and unavailable values rather than invented zeros. Show finite existing reports for memory investigation and repeated observation. A known PID can be located by its PID/start record in those reports; do not imply a PID-report filter. Process names and paths are untrusted data, never instructions.

Executable discovery remains separate: PATH makes the command callable, not necessarily discoverable for an unnamed CPU question. An optional instruction pointer may say, “For local CPU/resource questions, use `agent-monitor`; read `agent-monitor guide` for its workflow.” This proposal does not authorize editing agent instructions or adding an installation requirement.

## Required: finite observation and consistent ranking

`diagnose cpu` takes a baseline followed by **three one-second waits and measurement scans**, then returns the **top ten measured lifetimes**. These are fixed initial defaults, not benchmark-derived optimums; configurable windows and limits are outside this revision. Existing report options must not silently filter or alter diagnosis. Scope is all readable current-user processes, including nonagents, excluding the monitor's own PID. Invoking-agent processes are not automatically excluded. Totals and coverage are calculated before truncation.

The measurement window starts at the baseline listing and ends at the end of the final process scan. `elapsedSeconds` is the achieved Mach-clock duration, including scan time and excluding sleep, not the requested three seconds or wall-clock timestamp subtraction. Start/end timestamps are display metadata. Provider enrichment follows the measurement window and may extend command runtime; lookups retain finite timeout/cancellation behavior, with no unlimited watch or retry loop.

For every lifetime and measurement scan, reuse the accepted core accounting:

| Valid observation | CPU-seconds added | Covered seconds added |
| --- | --- | --- |
| Consecutive valid observations of the same PID/start lifetime | Current minus previous cumulative CPU | Current minus previous sample time |
| First observation, born after the previous listing | Current cumulative CPU | Current sample time minus previous listing |
| First snapshot, unavailable/invalid counters, or first observation predating the preceding listing | None | None |

Birth comparisons use Mach time, never the BSD wall-clock identity timestamp. `exec` retains accounting; PID reuse creates a separate contributor. Missing observations do not bridge a gap. Preserve the accepted newborn scan-skew qualification through `maximumScanSeconds`, the largest measured scan duration in this window.

For a lifetime, `cpuSeconds` is the sum of its valid contributions, `observedSeconds` the sum of their covered durations, `meanCPUPercent = 100 × cpuSeconds / observedSeconds`, and `peakCPUPercent` the largest valid interval rate. Coverage is the accounting window, including the zero-before-birth portion of a newborn interval, not process age. Rank descending by **CPU-seconds**, with PID/start identity as the deterministic tie-breaker; mean and peak are descriptive attributes. Include measured zero in the eligible population; lifetimes with no valid CPU interval are counted but cannot be ranked.

Population `cpuSeconds` sums those same lifetime contributions, including omitted and earlier contributors. With no measured lifetimes, omit both population CPU fields; otherwise measured zero remains zero. `windowCPUPercent = 100 × cpuSeconds / elapsedSeconds` expresses measured contribution over the whole observation window, not an estimate of missing CPU. Do not sum lifetime means or reconstruct CPU-seconds from `CPUAccounting.measuredUserPercent` using a common denominator: existing and newborn lifetimes have different measured intervals. This aggregation belongs in core and requires interval CPU-seconds/durations from the accepted accounting, which current report snapshots do not expose. Existing history, icon and session totals remain unchanged.

## Required: host context and observation limits

Reuse the per-listing host occupancy readings and unavailable cases from the [implemented contract](../architecture.md#cpu-accounting). `host.meanBusyPercent` is the duration-weighted mean of valid host intervals, using their actual positive consecutive listing-time deltas. `host.observedSeconds` and `host.validIntervals` describe only those intervals; missing intervals are excluded, never zero-filled or bridged. `host.logicalCPUCount` is present only if the count is unchanged across the window. A CPU-count change invalidates its crossing interval as in ordinary reports; valid intervals on either side still contribute unweighted one-core occupancy, without a single capacity claim. With no valid host intervals, omit the mean and show “No data”. Host coverage ends at the final listing, while process measurements extend through the final scan; their coverage is reported separately.

Show host occupancy beside measured process contribution. Never compute an “unattributed” remainder or infer that low measured CPU means an idle machine. Tick resolution, scan skew, monitor/lookup overhead and missed current-user work prevent causal subtraction. Unweighted logical-CPU occupancy does not measure equivalent performance/efficiency-core capacity. Lifetimes never observed and CPU after their last observation remain uncounted; deferred exited-descendant recovery and `ri_child_*` counters are excluded. Coverage counts refer to observations, not proof of complete host or current-user visibility.

A contributor absent from the final scan retains its measured CPU, exact identity, latest measured footprint/timestamp and any previously obtained attribution. Absence alone does not establish exit. Enrichment must not inspect a reused PID or transfer its metadata to the earlier lifetime. If enrichment cannot observe that exact lifetime, return `notObservedAtEnrichment`; distinguish this from an observed but unresolved attribution or a failed provider lookup. Metadata cannot be invented from cwd or from another process using the same runtime. Available attribution includes its observation timestamp and retains the existing provider, evidence, candidate IDs and launch/current-session distinctions. It describes the latest available association, not a claim that one session owned all CPU accumulated during the window; it never establishes exclusive ownership of a shared daemon.

## Required: response and streams

`diagnose cpu --json` emits one complete compact JSON document on stdout. Without `--json`, presentation renders the same result concisely as text. Diagnostic schema discovery is `diagnose cpu --json-schema`; existing `--json-schema` continues to describe report JSONL v3. Unavailable optional fields are omitted, not null or zero. The diagnostic schema rejects unknown properties and has independent `schemaVersion: 1`.

The following types define the minimal response. `DateTime` means an ISO 8601 timestamp; all numeric durations are nonnegative seconds, percentages use 100% = one logical CPU, and counts are nonnegative integers. `ProcessIdentity` and `Attribution` reuse the exact existing [report types](../../Sources/AgentMonitorPresentation/Resources/report.schema.json); identities and candidate IDs are never truncated.

```typescript
type Diagnosis = {
  schemaVersion: 1;
  startedAt: DateTime;
  endedAt: DateTime;
  elapsedSeconds: number;
  requestedIntervalSeconds: 1;
  measurementIntervals: 3;
  maximumScanSeconds: number;
  scope: "currentUserExcludingMonitor";
  host: {
    meanBusyPercent?: number;
    logicalCPUCount?: number;
    observedSeconds: number;
    validIntervals: number;
  };
  measured: {
    cpuSeconds?: number;
    windowCPUPercent?: number;
    observedLifetimeCount: number;
    measuredLifetimeCount: number;
    unmeasuredObservationCount: number;
    unreadableObservationCount: number;
    omittedContributorCount: number;
  };
  contributors: Contributor[];
  providerLookups: { provider: "codex" | "claude"; status: "succeeded" | "failed" }[];
  diagnostics: DiagnosticCode[];
};
type Contributor = {
  process: ProcessIdentity;
  label: string;
  labelTruncated: boolean;
  cpuSeconds: number;
  observedSeconds: number;
  validIntervals: number;
  meanCPUPercent: number;
  peakCPUPercent: number;
  footprint?: { bytes: number; sampledAt: DateTime };
  attribution:
    | { status: "available"; observedAt: DateTime; value: Attribution }
    | { status: "unavailable"; reason: "notObservedAtEnrichment" | "metadataUnavailable" | "providerLookupFailed" };
};
type DiagnosticCode =
  | "unmeasuredCPU" | "unreadableObservations" | "hostCoverageIncomplete"
  | "hostCapacityChanged" | "attributionUnavailable" | "providerLookupFailed"
  | "noMeasuredLifetimes";
```

`observedLifetimeCount` counts distinct identities across baseline and measurement scans; `measuredLifetimeCount` counts those with at least one valid interval. `unmeasuredObservationCount` counts listed lifetimes lacking CPU at measurement scans, excluding the baseline; repeated failures can count more than once. `unreadableObservationCount` sums reader failures across all four scans and does not deduplicate inaccessible identities or establish their UID. Returned count is `contributors.length`; omitted count is measured lifetimes minus returned count. Each performed provider lookup has one outcome; an empty array means no lookups ran, not success or failure. The corresponding diagnostic codes flag nonzero missing counts, incomplete host coverage, capacity changes, unavailable returned attribution or failed lookups; `noMeasuredLifetimes` means no lifetime had a valid CPU interval, not measured idle CPU.

Illustrative complete response with two measured lifetimes and an explicit zero omitted count. Both have unavailable attribution for different reasons.

```json
{
  "schemaVersion": 1,
  "startedAt": "2026-10-16T12:00:00Z",
  "endedAt": "2026-10-16T12:00:03.200Z",
  "elapsedSeconds": 3.2,
  "requestedIntervalSeconds": 1,
  "measurementIntervals": 3,
  "maximumScanSeconds": 0.05,
  "scope": "currentUserExcludingMonitor",
  "host": {"meanBusyPercent": 210, "logicalCPUCount": 8, "observedSeconds": 3.15, "validIntervals": 3},
  "measured": {"cpuSeconds": 3.9, "windowCPUPercent": 121.875, "observedLifetimeCount": 3, "measuredLifetimeCount": 2, "unmeasuredObservationCount": 2, "unreadableObservationCount": 1, "omittedContributorCount": 0},
  "contributors": [
    {"process": {"pid": 42001, "startMicroseconds": 1792151999000000}, "label": "compiler", "labelTruncated": false, "cpuSeconds": 2.4, "observedSeconds": 3, "validIntervals": 3, "meanCPUPercent": 80, "peakCPUPercent": 100, "attribution": {"status": "unavailable", "reason": "metadataUnavailable"}},
    {"process": {"pid": 42002, "startMicroseconds": 1792152000100000}, "label": "worker", "labelTruncated": false, "cpuSeconds": 1.5, "observedSeconds": 2, "validIntervals": 2, "meanCPUPercent": 75, "peakCPUPercent": 100, "attribution": {"status": "unavailable", "reason": "notObservedAtEnrichment"}}
  ],
  "providerLookups": [],
  "diagnostics": ["unmeasuredCPU", "unreadableObservations", "attributionUnavailable"]
}
```

Keep labels to 120 Unicode scalars, marking truncation explicitly. Do not include full arguments, environment, transcripts or arbitrary provider error text. Emit each diagnostic code once; guides explain meanings and suggested next observations, and text output uses those same explanations. No free-form generated diagnosis or automatic remediation is required. Exact evidence can still be large, so a ten-row limit is not a universal byte/token bound.

Exit 0 means a valid result, including empty or partial observations; counts and diagnostics distinguish those from measured zero. Exit 1 means no usable collection, such as failure to acquire the baseline or any required process scan; emit no partial success document and `collectionFailed` plus an explanation on stderr. A complete sequence of scans with missing counters remains a valid partial result. Argument Parser's invalid-usage exit 64 remains unchanged. Provider lookup failure alone does not invalidate usable CPU measurements. Warnings/errors use stderr; JSON stdout has no banners, color or appended guidance. Existing action statuses remain unchanged, including `message` exit 2 for an uncertain outcome.

Diagnosis does not intentionally change workload, UI or session state. Native reads and approved provider listings can consume resources, start helpers, establish connections and update provider caches; guidance discloses this, and the result lists performed lookups. No installation, elevation, transcript/token inspection, messaging, signaling or focus belongs to diagnosis. `guide actions` explains separate authorization and fresh verification, including that today's `--pid` action resolves identity at invocation rather than binding itself to an earlier report.

## Optional and excluded

The instruction pointer is optional. A help-only change leaves callers aggregating and interpreting separate reports, so guide plus finite diagnosis remains recommended. Generic agent modes, query languages, command manifests, caller/session marking, external skills, MCP services, memory diagnosis, continuous history, new host telemetry, action API changes and new providers/platforms are excluded from this design. Agent evaluations are optional evidence collection, never a runtime dependency.

## Decisions for review

1. **Approve current-user contributors with independent host context.** This reuses shipped accounting and distinguishes visible consumers from host occupancy without inventing an outside-population remainder. Other-user process attribution remains excluded.
2. **Approve three one-second waits, top ten by observed CPU-seconds.** CPU-seconds ranks contribution consistently across unequal lifetime coverage; mean, peak and coverage retain burst information. These finite defaults are a judgment, not a measured optimum. Keep tuning options out until evidence justifies them.
3. **Keep diagnosis observational, with guides owning interpretation.** Separate actions preserve fresh identity verification. Stable codes and typed evidence support concise answers without a second free-form explanation protocol.

Acceptance must cover newborns, baseline exclusions, read gaps, exec, PID reuse, unequal lifetime coverage, retained earlier contributors, valid zero/empty results, unavailable counters, every host failure case and count changes, same-directory sessions, ambiguous/shared-runtime evidence, partial provider failure and top-ten omission arithmetic. CPU-seconds in returned plus omitted contributors must equal the pre-truncation population total. A 0.2-second burst must not outrank more measured CPU solely because its mean rate is higher. Test clocks must separate configured waits, listing deltas, per-process sample deltas and final scan time. Schema examples must validate against actual encoded results.

The material feasibility gap is preserving interval CPU contributions, earlier identities and enrichment failure reasons currently discarded by the report path. Keep measurement/window aggregation in core, provider interpretation in attribution adapters and text/schema/guide formatting in presentation; Argument Parser remains in CLI targets. Do not broaden existing snapshots or history semantics merely to make the diagnostic renderer convenient. Optional fresh-agent evaluations should score correctness and uncertainty alongside calls and input/output tokens, with one guide call plus one diagnosis as the common first-use target and one diagnosis for repeat use. Neither live effectiveness nor token savings is established.

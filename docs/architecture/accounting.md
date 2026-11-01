# CPU and memory accounting

CPU accounting preserves unique counter contributions across process lifetimes and report windows. Memory remains an observation of current footprint or a qualified kernel peak. These contracts define what each number means; they do not claim complete capture of unseen workers or final exit CPU.

[Architecture overview](../architecture.md) · [All architecture guides](README.md)

## In this guide

- [CPU accounting](#cpu-accounting)
- [Retained counter accounting](#retained-counter-accounting)
- [Memory observations](#memory-observations)

## CPU accounting

CPU is averaged between snapshots in the one-core unit (100% = one logical CPU). Each native snapshot records its listing time `L(k)` immediately before `proc_listpids` and its scan duration. Listing times, each lifetime's sample time `t`, cumulative user+system CPU `C` and birth time `b` from `ri_proc_start_abstime` use the reader's same Mach timebase conversion; Mach absolute time excludes sleep. The BSD wall-clock start remains part of exact PID-plus-start identity and is never compared with these measurement times. `exec` preserves that identity and cumulative accounting.

| Observation | CPU percentage |
| --- | --- |
| Same lifetime observed in the preceding snapshot with valid counters and positive sample-time delta | `100 × ΔC / Δt`, unchanged. |
| First observed now, born after the preceding listing | `100 × C / (t − L)`, where `L` is the retained listing immediately before birth (usually `L(k−1)`, or the current listing for birth during a scan). |
| First observed now, born at or before the preceding listing | Unavailable; subsequent valid observations use normal deltas. |
| First snapshot | Unavailable. |

### Newborns, failed reads and final tails

Newborn CPU uses a zero baseline at the retained listing immediately before birth, rather than process age or the configured wait. A birth during the current scan uses its current listing; a first run-baseline observation remains ineligible. Its window can exceed an existing lifetime's window by at most the previous scan duration.

A lifetime absent from the preceding snapshot does not receive a latest-interval CPU rate. The independent counter ledger can recover its CPU over the original endpoints, as described below; ancestry retention never supplies its counter baseline.

Missing or decreasing counters and nonpositive elapsed times do not produce latest-interval CPU values; an accepted zero CPU delta remains measured zero.

Lifetimes never observed and CPU after a lifetime's last observation remain uncounted; exited-descendant recovery is deferred and child counters are unused.

Existing threshold, attribution, history, icon and session-group aggregation rules remain unchanged; their values incorporate these measurements.

Host occupancy is measured at each listing with `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`, behind an injectable core source. Per-logical-CPU user, system, idle and nice tick deltas are summed; occupancy is `100 × logical CPU count × (user + system + nice) / all ticks`. This is unweighted occupancy in the one-core unit, not equivalent computing capacity across performance and efficiency cores. `host_statistics` is excluded because third-party reads are cached at short intervals; see the [review evidence](../research/cpu-accounting.md#review-follow-up--2026-10-16).

### Accounting context in snapshots

`MonitoringSnapshot.cpuAccounting` contains `hostBusyPercent: Double?`, `logicalCPUCount: Int`, `measuredUserPercent: Double`, `unmeasuredLifetimeCount: Int` and `previousScanSeconds: Double?`. The measured total includes all sampled current-user lifetimes before thresholds or attribution filtering, including historical contributors in a display window; the monitor itself remains excluded. Window rates use eligible CPU-seconds divided by the enclosing duration. Its missing-value count covers observed lifetimes with excluded measurements, not never-observed processes. The previous scan duration bounds newborn window skew and is absent on the baseline snapshot. This accounting requires no metadata enrichment or all-agent summary; text and JSONL keep summary collection disabled.

### Unavailable host readings

Host occupancy is unavailable on the first snapshot, failed calls, zero total tick delta, any per-CPU counter decrease (including wrap), or logical CPU-count changes. A failed read breaks the baseline; the next successful read establishes a new one. Successful but unusable readings become the next baseline. The count comes from a successful host reading, falling back to the native active logical CPU count when the call fails. Missing host occupancy is shown as “No data”; measured idle occupancy remains 0%. Sleep/wake consistency remains an [empirical question](../research/cpu-accounting.md#unresolved-empirical-questions); inconsistent counters are rejected.

### Shared output and schema

Presentation owns one shared context string, for example `CPU: host 211% of 800% · your measured processes 169% (3 without data)`, reused by the text report, TUI header, native panel header, native status menu and accessibility text. Percentages are rounded to whole numbers for this line. The TUI reserves one additional header row and clips at the viewport width; native text can wrap within its fixed panel width. Host occupancy and measured CPU are shown side by side, with no computed remainder: missed work, scan skew and tick resolution prevent interpreting their difference as outside-population load. History, native icon levels and session totals retain their existing populations and aggregation rules.

JSONL schema version 1 retains the report-level `cpuAccounting` object and adds optional `acquisition` timing/status; unavailable `hostBusyPercent` and `previousScanSeconds` are omitted. The report and object reject additional properties. Findings stay flat; the report also requires unfiltered `observedFindings` beside the displayed `findings`. There is one current report schema and no compatibility output modes. [Schema discovery](../../Sources/AgentMonitorPresentation/Resources/report.schema.json) remains available through `--json-schema` without sampling.

## Retained counter accounting

### Contribution identity

The first CPU-01 foundation is implemented in [CounterLedger](../../Sources/AgentMonitorCore/CounterLedger.swift) and used by every `Monitor` ingestion. Each monitor owns an acquisition-run UUID and monotonically increasing scan sequence. A process observation is identified by that scan plus its exact PID/start lifetime; a contribution identifies both its opening observation (or pre-birth listing) and closing observation. `Monitor.counterScan` exposes the latest immutable observations, accepted contributions, exclusions, evicted baseline identities and, for snapshot ingestion, the original native snapshot including host counters. Acceptance-rule version 1 describes this core contract; it is not a recording format or report JSONL version.

### Last-good baseline recovery

The ledger retains the last valid counter through missing scans and unavailable resource reads. The next compatible counter produces one delta over its real endpoints. Native user/system Mach ticks are retained as integers and subtracted separately before conversion, so floating-point rounding or an increase in one component cannot hide a decrease in the other. Counter decreases, invalid values and incompatible counter representations/timebases break continuity; a valid reset reading establishes a new baseline. Invalid read times cannot move the baseline backwards. Executable changes alone do not reset cumulative CPU; no execution-epoch or historical session-ownership guarantee follows from this rule.

### Delayed first valid observations

The first valid counter of a lifetime born after the initial listing may use a zero opening at the retained listing immediately before its verified monotonic birth, including after earlier unreadable observations or at the current listing for birth during a scan. The first scan establishes the run baseline without accepting CPU. That opening is a listing reference with birth evidence, never a fabricated process sample. Pre-existing lifetimes, absent birth evidence, previously established baselines and unavailable pre-birth history cannot recover their first cumulative counter. Baseline state and listing retention are independent of attribution and display filtering.

### Bounded baseline retention

Baseline retention is capped at 8,192 lifetime states and listing history at 4,096 listings in the initial implementation.

These are engineering caps, not validated coverage or heap-size guarantees. Baseline eviction removes least recently observed states, with exact-identity ordering for ties, and advances a conservative birth-time floor through evicted read times. A scan-ordered queue skips stale references and sorts only the oldest scan's tied identities when eviction needs them, rather than sorting all retained states on each birth.

Periodic linear pruning bounds lazy references to twice the baseline cap, including when a long-missing lifetime pins the oldest scan. Pruning also shrinks sparse batch allocations and releases empty buffers, so departed lifetimes cannot each pin the original full-population scan array.

A returning evicted lifetime cannot re-add its cumulative CPU as a newborn; lifetimes born at or before that floor establish a new baseline with a history-evicted exclusion.

This can also conservatively exclude other delayed first readings. Exclusion and eviction records preserve that loss without unbounded lifetime tombstones.

Contributions are returned per scan; the ledger does not retain an unbounded contribution archive.

`CounterWindow` selects closing observations in `(baselineScan, finalScan]`, deduplicates contribution IDs and rejects conflicting copies or mixed acquisition runs. Openings before the baseline remain separately recovered CPU, excluded from the window's rate. Its denominator is the enclosing window from the baseline listing to the final scan end. Widening/coalescing a window re-evaluates endpoints and unique contributions; adding percentages is invalid. No accepted contributions means unavailable CPU, while an accepted zero delta remains measured zero. This projection is shared by finite diagnosis and the independent live display-window aggregation.

### Recovery and displayed rates

Live process/session/icon rates use the enclosing display window and exclude recovered CPU whose opening precedes that window. Finite diagnosis uses its wider acquisition window and now includes retained-counter recovery within that window once, preserving each contributor's actual interval. No earlier acquisition run supplies its baseline. Display windows expose recovered contributions and frozen point attribution across every frontend; later graph/metadata labels do not rewrite earlier CPU ownership. Existing live ancestry still orders parent candidates by BSD wall-clock birth timestamps and retains prior parent links; that mechanism cannot certify historical ancestry across clock adjustments. Historical support must use retained exact edges with monotonic birth evidence.

### Native failure provenance

Native snapshots preserve raw per-process CPU and birth/read ticks, original footprint/kernel-peak values, and ordered absolute/continuous/wall-clock anchors with the Mach timebase. These anchors are not atomic or interchangeable; host reads occur between scan start and the listing anchor.

Structured native outcomes retain the listed PID, operation, return value/expected length, failure errno captured at the syscall boundary, read time and, for resource/path failures, identity only when the resource-read identity bracket passed. Out-of-scope outcomes retain the identity observed by the initial BSD read.

Permission denial, ESRCH, short reads, identity/UID changes, other failures and readable out-of-scope users remain distinct; ESRCH does not establish normal exit.

Failed final verification rejects the sample while preserving earlier operation failures without claiming an identity. Enumeration failure still throws its native errno.

Existing live unreadable counts retain their earlier meaning; richer outcomes are available in the core for the subsequent reporting/recording work.

Frozen point attribution and historical rows build on this counter foundation in the [independent display-window layer](display-windows.md). Recording remains separate. Controlled-load cadence/coverage and retained-memory acceptance remain open in [PLAN.md](../../PLAN.md#resource-accounting-priority). Polling still cannot measure never-observed lifetimes or reliably recover final exit CPU.

## Memory observations

### Current footprint and kernel peak

The native reader requests `RUSAGE_INFO_V4`. `footprintBytes` is current physical footprint; optional `kernelPeakFootprintBytes` carries `ri_lifetime_max_phys_footprint` unchanged through core findings and report JSONL schema 1. This is the kernel task peak and can reset on exec while PID/start identity stays unchanged, as the [controlled probe](../research/cpu-accounting.md#kernel-memory-high-water-mark) demonstrated. A later observation replaces it, even when lower or unavailable. Text, TUI and native process details label it separately; sorting, session totals, icon and memory history use current footprint. Display thresholds also use current footprint for live rows; historical rows use their last observed footprint solely for visibility. Independent process peaks cannot be added as concurrent session memory.

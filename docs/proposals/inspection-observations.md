# Supplemental observations during inspection

Status: **approved**, 2026-10-26. User approved the amended `9a9da33` contract for default-off Core/TUI implementation and deterministic guards only. Native trials, live measurements and Mac controls/coverage rows remain separately gated. The approved default-off slice is implemented under the [architecture contract](../architecture.md#supplemental-inspection-observations); this approval record remains while its native evaluation gate is open.

## Purpose and scope

Improve transparent discovery and measured CPU of short workers during Mac/TUI inspection, preserving complete 100 ms acquisition and independent five-second display. Extra polling cannot guarantee final-exit CPU or discover every lifetime. The [source findings and review qualifications](../research/cpu-accounting.md#deferred-inspection-admission-review--2026-10-26) explain why held readings replace the earlier partial-stream candidate.

Required: checked same-user discovery between complete scans, bounded temporary readings admitted only at the next complete scan, exact CPU accounting, frozen point evidence, census-only current memory/population and separate supplemental coverage.

The proposed implementation is initially default-off; enabling it permits opportunities only while the Mac panel shows live results or the TUI is live and unpaused. Ordinary text/JSONL collection has no inspection session and reports this capability as disabled.

Enabling uses one core monitoring-configuration flag and one TUI command-line option; the Mac app gains its enable control and coverage row only under a separately authorized native trial. No workload launch integration is required.

## Held readings and admission

Only complete scans advance the accounting sequence, create listing anchors, consume enrichment results, request metadata, update complete-scan coverage and close units. Supplemental observations never enter those paths independently. The later [offline runtime contract](../architecture.md#offline-runtime) excludes provider listings and commands from collection.

A held reading is not accepted accounting: it is bounded temporary evidence keyed by exact process lifetime, with its own counter timestamp, execution identity, sampled memory, verified parent identity and timestamped attribution evidence.

At the next complete scan C, apply these rules once per held lifetime:

| Outcome at C | Admission |
| --- | --- |
| Same lifetime successfully read | Discard the held reading. Use C's counters, memory and evidence exactly as complete-only collection would. A transient held footprint peak is also discarded. |
| PID absent, read reports disappearance (`lookupUnavailable`, ESRCH), or an `identityMismatch` whose successful identity read establishes a different start time | Admit the held reading as a carried observation at C, retaining its real read time and marking it not present at census. A replacement lifetime remains a separate census observation. |
| PID listed but `permissionDenied`, `shortRead` or `otherFailure`, or an `identityMismatch` without a successful identity read | Drop the held reading and count that disposition. Preserve the complete scan's failure and missing-read semantics. |
| No next complete scan because inspection ends, pause, cancellation, failure or run/scope replacement | Discard held readings and count them in the terminal or next available coverage projection. Never create a synthetic scan or CPU endpoint to report this count. |

Existing counter validation, birth proof, initial baseline and eviction-floor exclusions still apply to carried observations. Supplemental enumeration never becomes a newborn listing anchor. No accepted CPU is discarded: after admission, normal conservation, compaction and explicit terminal-overload/drain rules apply. Rejected admission terminates the run and drains accepted CPU under that existing contract.

Example: complete listing C0 at 0.0 s, worker born at 0.02 s, held read at 0.05 s with cumulative CPU 0.02 CPU-s, absent at C1 at 0.10 s. Subject to existing birth validation, the carried contribution opens at C0, closes at the actual 0.05 s reading and belongs to C1's admission sequence. It contributes 0.02 CPU-s, no current memory and no claim about its final exit CPU. If C1 successfully reads it instead, only C1's ordinary contribution is accepted.

One carried observation per identity per complete scan requires a historical row even if the lifetime never joined the census. The row retains its observed executable, CWD and evidence; it cannot be omitted while admitting its CPU. Census membership is explicit throughout window projection, collapse protection and recent history: final admission sequence alone does not mean present.

Current population, memory, labels and root corroboration for current measurements derive exclusively from complete-scan observations. Carried sampled maxima remain historical and timestamped. Whole-unit eviction, report endpoints, CPU denominators and accepted partial-unit drains retain their complete-scan contract.

## Attribution evidence

For a new worker W, immediately after its checked read, read its reported parent's identity and UID. Accept the parent edge only for the exact identity, in the same comparable start-time domain, with parent start no later than W's start. Parent failure, reuse or uncertainty leaves the CPU unresolved unless independent valid adapter evidence supports ownership. Context reads share the opportunity's allowance; no ancestry walk is required.

Ownership uses timestamped evidence available for the held reading, including a frozen preceding-census ancestor context reached through that verified edge. A node found at C may establish identity, but newer markers, execution state or registry bindings alone cannot establish ownership at the earlier held endpoint. Where historical continuity cannot be established, retain unresolved CPU instead of borrowing C's current label. Parent departure does not invalidate already frozen, valid evidence; absence of that evidence does not justify inheritance.

These are point-evidence candidate claims, not interval-supported ownership. Polling can still miss an exec or reparenting transition.

Carried context is isolated from the live graph: it must not replace census nodes, clear registry bindings, consume metadata results for absent workers, alter enrichment signatures or request provider discovery. The complete scan's normal enrichment path remains unchanged. Later evidence never silently relabels already accepted CPU.

## Scheduling and bounds

At most one opportunity is proposed per complete interval, at complete start +50 ms. Skip it if acquisition/resolution is still running or insufficient allowance remains before the unchanged next complete deadline. No catch-up and no rebasing. Check the deadline between native operations; an in-flight syscall cannot be preempted, so fixed deadlines are not a guarantee of achieved cadence.

Each opportunity enumerates using the existing same-user scope and checks new PID numbers relative to the last complete listing. Discovery is independent of filters, ownership and prominence, with a rotating start position to avoid systematically favouring low PIDs. No deferred-candidate queue is retained. PID differences cannot discover all reuse.

With one opportunity and a buffer emptied at each complete scan, step one is discovery-only: there is no repeated newborn follow-up within that interval and no targeted read of census members or the inspector's selection.

The allowance covers enumeration, identity/UID verification, parent context, optional bounded prompt capture and retained bytes/records. Select work before reading; count candidates left unread and readings dropped at capacity. The held buffer and any frozen context share explicit logical limits; overflow before admission reduces coverage visibly rather than stopping collection.

Numeric attempt/time allowances and the concrete cap require a bounded deterministic configuration before implementation is enabled, and separate approval before native measurement. Existing accounting limits continue to govern admitted data; this is not a process-wide heap guarantee.

Pause, close and run/scope change clear held evidence and scheduling state; accepted history follows existing lifecycle rules. Disabled mode creates no supplemental reader work or held-reading state. Recording remains off, with no files or cumulative history.

## Coverage and interface contract

Every unit records enabled/disabled state (and mixed enabled/disabled units when merged), opportunities taken/skipped, candidates read/failed/left unread, carried observations admitted, held readings superseded/dropped/discarded, and complete-scan lateness while supplemental work was in progress. Counts sum and timing maxima survive unit merges. Complete-scan gaps, overruns, failed-read statistics and census counts exclude supplemental attempts. Scan-distance missing-read intervals remain distinct from native failed-read counts.

The TUI, and the Mac app once its trial control exists, shows a structured “Between-scan reads” row in coverage details, with counts rather than prose, only for units where the capability was enabled for at least part of the unit; a permanent disabled row would be noise where the capability cannot be enabled.

JSONL always reports the enabled/disabled state. A compact warning appears when more than half of eligible opportunities were skipped while inspection was enabled; other material coverage warnings remain visible. JSONL exposes the same unit statistics and actual reading timestamps.

Older units retain their coverage mode so an increase in measured CPU after inspection begins is not presented as proof of increased workload.

## Validation contract

Deterministic guards must establish conservation against an independent cumulative-counter oracle, unique contributions, unchanged census/enrichment behavior, exact parent identities and bounded state across failures, PID reuse, exec, pause, pressure and cancellation. Removing discard-on-census-success, parent-start validation or census membership filtering must fail a guard. Disabled mode must produce identical snapshots and JSONL on the existing deterministic traces, apart from the disabled coverage state.

The admission table is a parameterized guard over every `NativeCounterStatus`. Missing-read checks must distinguish the ledger's count of intervals spanning missing scans from the independent complete-scan failure observations.

For identical complete observations, superseded held readings must not change that interval's ordinary contribution or census projection. Over a trace without counter resets, eviction or invalid readings, extra admitted endpoints must not reduce lifetime-total accepted CPU; later contributions may become smaller because an earlier carried endpoint already accounted for part of them. Do not require byte-identical later windows after a carried admission.

Reset/exclusion/eviction cases require their own explicit oracle rather than an unconditional monotonicity claim.

### Native evidence and proposed trial criteria

The [bounded two-pair retry](../research/cpu-accounting.md#bounded-inspection-comparison-retry--2026-10-26) measured local benefit for 50 ms workers, persistent shorter-worker loss and enabled cost above the absolute target; native acceptance remains open.

Any further separately authorized comparison should use paired inspection-off/on blocks, duration-specific owned-worker ground truth, exact-session/unresolved/wrong-owner CPU, complete cadence, supplemental skips/lateness, stage costs and collector-plus-helper CPU. The cold reviewer proposed these trial criteria. They are **not approved**, do not authorize a run, and do not replace sustained-load acceptance.

| Measure | Proposed criterion |
| --- | --- |
| Trial size | Five paired blocks. |
| Capture gain for the 50 ms class | At least ten percentage points. |
| Complete-scan p99 | No more than 5 ms worse than control. |
| Additional collector-plus-helper CPU | At most three percentage points. |
| Total collector-plus-helper CPU | At most 15%. |
| Supplemental skip rate | At most 50%. |

Stop on wrong ownership, duplicate CPU or conservation failure. Compare against control because baseline saturation already misses cadence acceptance; report absolute gaps and overruns regardless. Additional graphs are optional.

## Excluded and unresolved

Excluded: partial accounting batches, independent ledgers, separate census/accounting endpoints, “since census” UI, selected-process requests, candidate queues, background supplemental reads, ancestry walks beyond the checked parent, privileged/SPI backends, final-exit recovery claims, new full-command capture, slower baseline sampling and filter-based measurement. A 50 ms complete cadence during inspection would avoid held readings but roughly double acquisition cost against the 15% target; the [assessment](../research/cpu-accounting.md#local-feasibility-assessment--2026-10-26) records the basis.

This discovery-only step does not directly shorten the exit tail of workers already observed at a complete scan. Moving resolution off acquisition is a competing hypothesis to evaluate from stage timings, not an authorized redesign. General transparent coverage, sustained performance, heap and physical UI acceptance remain open. The approval covers only this amended default-off deterministic implementation; native trials need a separate bounded request.

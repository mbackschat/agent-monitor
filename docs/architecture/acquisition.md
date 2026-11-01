# Acquisition and adaptive sampling

The collector schedules native observations independently of metadata enrichment and display delivery. Fixed 100 ms acquisition is the default; adaptive sampling and supplemental inspection have separate controls, evidence and limits.

[Architecture overview](../architecture.md) · [All architecture guides](README.md)

## In this guide

- [Independent acquisition](#independent-acquisition)
- [Adaptive acquisition](#adaptive-acquisition)
- [Supplemental inspection observations](#supplemental-inspection-observations)

## Independent acquisition

### Worker ownership and shutdown

Live text/JSONL, TUI and native collection share one serial `AgentMonitor acquisition` cycle for native reads, bounded prompt evidence, counter ingestion and in-memory attribution/accounting. Slow native metadata uses a separate dedicated worker. A dedicated `AgentMonitor publication` worker seals closed units, admits recent history, aggregates display windows and creates history snapshots. Acquisition does not enter the history store or wait on its UI-shared lock.

There is no raw-scan FIFO or resolution backlog. The native acquisition thread owns its absolute start-to-start deadlines. Interval changes and cancellation signal its wait directly; there is no per-scan Swift task submission or task-group timer race. A preallocated bounded ring transfers closed units in constant bookkeeping work; a separate async bridge admits and merges them in the publication channel. Neither history work nor actor admission runs on the acquisition thread. Injected clocks implement the same synchronous deadline/wake boundary, so deterministic backlog, overload and drain tests exercise the production loop. Swift tasks coordinate the bridge and consumers; synchronous native work runs off the cooperative executor. Collection currently requests `userInitiated` QoS, a provisional policy rather than a real-time guarantee. Finite diagnosis retains its separate finite-window service.

Requested thread QoS does not establish effective scheduling priority: the launch context and macOS task resource policy can constrain it. The collector does not reclassify its host process or override an inherited background/utility policy. Acceptance therefore distinguishes ordinary CLI/TUI launch, a diagnostic application-policy launch and the native app, and records requested QoS alongside effective thread priorities. `taskpolicy -a` changes process policy at launch; its results cannot stand in for ordinary CLI/TUI or closed-panel Mac acceptance. See the [profile protocol](../../Tools/CPUAccountingProbe/README.md#live-pipeline-profile) and Apple’s [requested/effective policy distinction](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task_policy.c).

### Deadlines and timing gaps

Acquisition requests a start-to-start period, 100 ms by default. Native reads and in-memory work can stretch that period under load; the collector never runs overlapping or catch-up scans. Each report window records accepted scan count, timed-period count, maximum start-to-start gap and the number of periods exceeding 1.5 times their requested duration. These aggregate over every scan and merge by sum/max, so an on-time final scan cannot hide a prior gap. Mac/TUI coverage details and JSONL expose the window summary; overruns have a compact visible warning. Persistent sampling explanations live behind native coverage disclosure or terminal details, rather than repeating below every table; actionable coverage warnings remain visible. Polling still misses never-observed workers and final exit CPU.

### Prompt evidence capture

Prompt capture uses bounded attempts, elapsed time and reserved argument bytes per scan, with per-lifetime/executable discovery state. Discovery eviction shares the counter ledger’s scan-order queue: only the oldest tied identities are sorted, and stale references are bounded by periodic pruning. Long-running churn therefore does not repeatedly sort the whole discovery cache; eviction still preserves the same re-capture eligibility. `KERN_PROCARGS2` reads with budgets up to 64 KiB, including default prompt capture, query size first: an argument area larger than the allowance is explicitly truncated and is never parsed. Larger read budgets, including background enrichment, first try a 64 KiB buffer. Only a result shorter than that buffer is parsed directly: XNU returns the full supplied capacity for a truncated tail.

A filled buffer falls back to the size-query/read/post-size-check path, which rejects oversize arguments and growth beyond the allocation. For ordinary targets whose environment is included, this removes two size-query syscalls, not two argument copies: XNU skips the stack copy for size-only queries. Restricted targets whose environment is omitted can copy during those queries.

Arguments exceeding 64 KiB incur an additional initial read before fallback. Refresh frequency is unchanged; the [argument reader](../../Sources/AgentMonitorCore/NativeProcessArguments.swift) owns the shared check. Native identity/path checks bracket access.

The short-read path omits the post-read size query, so a same-path exec growing arguments during the kernel read can escape that former race check; the size-checked path was not atomic either. Unchanged-path exec remains an observation limitation. Captured evidence stays at its actual read time.

Successful no-marker reads have a separate captured status and are forwarded for metadata reuse rather than reported as unavailable. A process can overwrite its argument area without exec, so empty reads retain existing markers.

Executable path changes, name changes and observed kernel-peak footprint resets clear metadata and markers; delayed pre-boundary evidence cannot restore them. An exec missed by polling can therefore retain an earlier marker, an explicit attribution limitation.

Metadata refresh uses its own worker and timestamped results. Stable metadata batches are due one second after their previous request time; read completion timestamps qualify evidence freshness, not the next refresh deadline. Slow workers may coalesce requests instead of catching up. New lifetimes and polling-visible execution changes are eligible immediately. Only replaceable refresh requests coalesce; accepted counter observations do not. Cancellation cannot forcibly interrupt an in-flight native syscall. Collector-owned descendants remain measured and identified for adaptive-sampling exclusions. There is no provider-listing worker or request path.

### Metadata reads and recognition cache

Native metadata prepares one adapter-owned runtime observation plan per read, sharing its fresh invocation decision between terminal eligibility and descriptor requests.

Path-only executable recognition is reused in a reader-owned, synchronized FIFO cache capped at 256 entries and 64 KiB of executable-key UTF-8 bytes; these logical limits are not a whole-process heap ceiling. The collection’s immutable adapter registry owns recognition and evidence interpretation. Only nonempty absolute paths are cached, including negative claims; oversized and relative paths use fresh recognition. A canonically equivalent path with different UTF-8 bytes bypasses the cached entry without replacing its stored spelling or byte charge.

The registry also prepares the immutable environment-key union, its UTF-8 spellings and each adapter’s allowlist once. Every parse still scans fresh argument bytes and validates fresh values; this retains declarations, never arguments or environment values. Invocation narrowing, descriptor reads and evidence interpretation happen outside the cache lock on every metadata observation.

Arguments, environment variables, process identities, descriptor results and ownership evidence are not cached here. Both native lifetime/path checks still bracket metadata reads; the cache introduces no filesystem persistence.

### Attribution storage admission

The retained attribution graph has an independent reservation using the pipeline’s record/text limits, covering retained ancestors, metadata, cached resolution context and indices even when visible ancestry is short.

Mutation-time charges are checked after ingest and evidence application, before enrichment admission or window append. Cached resolutions are optional derived data: when evidence growth exhausts the combined reservation, discard the resolution cache before validating required evidence.

Each cache miss checks its prospective retained charge, subtracting any stale entry it replaces; if it cannot fit, return the complete uncached resolution without retaining it. Cache pressure therefore increases recomputation instead of terminating collection or reducing attribution detail.

This permits one candidate resolution as scratch beyond the accepted graph reservation; emitted findings and downstream windows have separate storage costs. Ingest and evidence batches are checked after mutation, so their rejected-batch scratch is not covered by this reservation.

Exhausting required evidence storage terminates the run with an explicit attribution-stage error naming the rejected scan, drains previously accepted CPU, and discards later scans; it is not a skipped scan followed by continued monitoring.

Required ancestry is never silently discarded. This bounds accepted retained graph state, not the simultaneous incoming batch, enrichment worker state or process-wide heap.

The [population/scratch ownership audit](../research/menu-bar-load-cost.md#population-and-scratch-ownership-follow-up--2026-10-26) identifies the additional allocations outside those reservations.

### Pipeline storage bounds

Open accounting units, the closed-unit ingress ring, pending publication units and pending reports each use logical caps of 65,536 retained records and 16 MiB UTF-8 text. The ingress ring also caps its unit count at 128. Its consumer releases a slot before merging; in-flight transfer and transactional merge copies are additional bounded transient storage. If the bridge itself cannot keep up, ingress rejects a unit explicitly and drains already accepted units. Recent history, prompt discovery and ledger state have their own bounds; these are not a measured process-wide heap ceiling. Capacity pressure first reduces older detail under the [pressure-disclosure contract](display-windows.md#pressure-disclosure). A genuinely unrepresentable current population or required crossing context still produces an explicit stage/scan failure rather than fabricated totals. Final-build cost, long-run retention and short-worker coverage remain acceptance work in [PLAN.md](../../PLAN.md#resource-accounting-priority).

## Adaptive acquisition

`SamplingSession` owns one controller on the existing acquisition thread. Mac and TUI opt into adaptation explicitly; initial settings are **off**, minimum and visible maximum 100 ms, closed-panel multiplier one, and a 60 s rolling window. Ordinary text/JSONL retain fixed acquisition. Display refresh, provider/metadata freshness, accounting and recording are independent. The [prototype findings](../research/cpu-accounting.md#adaptive-sampling-offline-prototype--2026-10-27) establish modeled scan savings, not native CPU savings or approval of slower defaults; [remaining policy decisions](../proposals/resource-accounting.md#adaptive-acquisition) stay separate.

| Setting | Meaning and valid range |
| --- | --- |
| Mode | Adaptive sampling, or **Use maximum interval**. Off continues collection at the context maximum. |
| Minimum | Shared across contexts; at least 0.1 s and no greater than the visible maximum. |
| Visible maximum | Existing `--interval`, native presets and TUI faster/slower steps; 0.1–60 s. |
| Closed-panel multiplier | Mac only; finite and at least one, with visible maximum × multiplier no greater than 60 s. Applies in both modes. |
| Activity window | 1–300 s; defaults to 60 s. Activity does not reset the window. |

Settings are validated together. Invalid direct edits are rejected atomically and menus/steps skip invalid combinations. Native settings stay in memory until quit. TUI exposes `--adaptive-sampling` / `--no-adaptive-sampling`, `--sampling-minimum` and `--sampling-window`, without new in-app keys or a multiplier control. Minimum/window options do not enable adaptation implicitly. With adaptation off, `--interval 1` means fixed 1 s in TUI; with it on, 1 s is the maximum. A configured Mac multiplier of 2.5 makes a 5 s selection permit 12.5 s when closed, including in maximum-interval mode.

### Eligible adaptation signals

Evaluate before display filtering across the measured same-user population. Exclude explicit collector exclusions, verified out-of-scope PIDs, the monitor and collector-owned helpers through retained exact ancestry. Proven helper membership survives ancestor departure within the existing graph retention; a reused PID does not inherit it. Unknown helper ancestry remains eligible.

Completed own metadata and the retained resolution chain must establish no agent candidate before a lifetime is excluded. A negative parent alone cannot exclude a pending child or a child with its own agent markers. Queued and unavailable refreshes retain a valid completed negative; detected execution or changed resolver inputs invalidate it, and malformed/ambiguous evidence remains eligible. Pending, point, uncertain and supported agent evidence all qualify for CPU activity.

A complete scan contributes newly accepted eligible CPU, eligible arrivals, observed departures and read uncertainty. Startup establishes the existing population without arrival events. Listed-but-unverified episodes count once, and later verification does not recount the same episode; a verified replacement does. Admitted supplemental lifetimes count at their admitting scan unless already counted. Completed own negatives suppress lifecycle events only when available at that observation; later metadata cannot erase historical control events. Absence is not proof of exit.

### Rolling controller

Retain at most 3,002 control aggregates: all-eligible CPU, young-worker CPU, arrivals, event flags and enclosing support times. A contribution is young if its verified birth lies within the activity window at its counter observation; unknown birth qualifies conservatively. Freeze classification when admitted. Young evidence can therefore remain influential for another window after the worker ages out. Cumulative accounting continues for workers of every age; the controller keeps no additional per-worker archive.

### Enclosing support for lookbacks

For lookback H, select aggregates closing in `(now − H, now]`, always including the latest one. The denominator is the enclosing span from the earliest opening to now, including the preceding listing and earlier recovered CPU endpoints. It can exceed H: 25 ms CPU gathered over 12.5 s is 2 ms/s, and two 625 ms intervals occupy 1.25 s in a nominal one-second lookback. Charge accepted CPU once, without guessed proration. A settings reset cannot shorten CPU support; relaxation elapsed time starts at the settings boundary independently.

Normalize rolling young-worker CPU between 1 and 20 ms CPU/s, and arrivals between 2 and 20 per minute, clamping each score to 0–1. The larger score selects `baseTarget = maximum − score × (maximum − minimum)`. Shorten the base immediately. Lengthen it by at most `(maximum − minimum) × elapsed / window` per acquisition, capped at the target. These thresholds are policy candidates from the prototype, not measured workload distributions.

Request the minimum while any eligible arrival/departure remains in the one-second event lookback, recent all-eligible CPU exceeds its rolling mean by at least 20 ms/s, or recent absolute CPU reaches 100 ms/s. Both CPU rates use enclosing support. The absolute guard keeps continuously busy older workers fast after their rolling mean catches up. First valid counters after missing reads add a one-second recovery override. Brief overrides do not reset the independent base.

Unavailable counters on a currently listed eligible lifetime request the minimum and freeze the base. Retain history but give no relaxation credit for held time. Valid counters, verified replacement or absence from a successful scoped listing retire the blocker; final unmeasured CPU stays unknown. Persistent read failures can keep the minimum indefinitely; the prototype's persistent-failure relaxation is not enabled. **Complete-listing failure retains the existing fatal collection contract:** drain accepted accounting and surface the error. No retry loop or fabricated empty census is introduced.

### Modes and deadlines

Startup/enabling adaptation starts at the minimum with fresh control history, without resetting process counters. Opening the Mac panel sets the base to minimum but retains history; closing changes only the context maximum. Visible maximum/multiplier edits clamp the base and keep history. Minimum/window/mode changes restart control history. Grouping, thresholds and presentation pause do not reset it. Static icon mode still stops collection while closed and starts a new acquisition baseline when reopened.

Enabled experimental discovery with active run-local inspection permission holds the minimum in either sampling mode; neither flag alone does so. Adaptive history continues while permitted. Releasing permission resumes the contemporaneous base or fixed context maximum. Discovery's read/admission algorithm is unchanged.

### Settings wakeups and effective deadlines

Activity is evaluated after scans; it cannot wake acquisition before observation. UI changes wake the existing wait. An earlier deadline becomes `max(now, lastStart + newInterval)`; a deadline already due cannot be deferred or erased by a later setting. Reads remain serial and cannot be interrupted, with no catch-up scans. `requestedPeriodSeconds` retains the actual policy request, while `effectivePeriodSeconds` records the deadline baseline used for that period's overrun test. A 1 s request shortened to 100 ms at 500 ms has a 500 ms effective baseline; it does not invent a 500 ms policy request.

### Adaptive coverage reporting

Shared coverage details and JSONL retain requested-period extrema, current/base intervals, mode/bounds, CPU/arrival rates and their support spans, applied policy changes, override activation counts and time under each override. Counts/durations sum on coalescing and expire with their owning recent units. Maximum achieved gap appears with maximum requested period; overruns exceed 1.5 times the effective deadline baseline. Repeated scans under the same override are duration, not repeated activations. Fixed collection emits its fixed requested range without adaptive overrides. Coverage fields do not alter totals or make historical memory current.

### Adaptive evidence limits

Slower polling can miss the first burst or repeated sparse jobs before any trigger is seen. Low observed rates are not proof of inactivity. New idle sessions, unresolved churn and sufficiently large aggregate heartbeats can keep fast sampling. Older eligible workers with modest steady CPU may relax; their counters retain intervening readable work, but final tails and memory age grow. Completed-negative long-lived workers have no CPU trigger. These limitations remain visible and constrain [default acceptance](../proposals/resource-accounting.md#adaptive-acquisition). No per-process scheduling, memory trigger, extra probe scans, host-load subtraction or automatic recording is added.

## Supplemental inspection observations

The [approved inspection proposal](../proposals/inspection-observations.md) is implemented behind `MonitoringConfiguration.inspectionObservations`, default `false`. TUI supplies a run-local `LiveInspection` permission when `--inspection-observations` is explicitly selected; pause suspends it. Mac collection supplies no permission or enable control. Ordinary text/JSONL collection has no inspection session. Disabled collection performs no supplemental enumeration or reads and creates no held buffer. Recording remains off; all evidence below is bounded in-memory state.

### Discovery budget and candidate rotation

On the same acquisition worker, one discovery opportunity is eligible at complete-scan start +50 ms. Acquisition/resolution must finish before that slot; there is no catch-up. Work ends at the earlier of slot +10 ms and next complete deadline −5 ms. Each native operation checks that allowance, including enumeration, worker identity/path/counters, parent identity and checked CWD; an in-flight call cannot be preempted. Limits are 16 candidate attempts, 132 native operations, and 16 held readings sharing 512 logical records and 64 KiB of UTF-8 context. These are logical limits, not a whole-process heap ceiling. The start position rotates, census members are not targeted, and no candidate queue survives the opportunity. Optional extra argument capture is omitted; ownership comes from verified preceding-census context and existing adapter recognition.

### Admission at the next census

Only the next complete scan admits held readings. A successful same-lifetime read supersedes the held counters and memory completely. Absence, a whole-process ESRCH, or a successfully verified replacement identity permits one historical carried observation with its actual timestamp. A readable identity with unavailable resource counters, permission/short/other failures, an unproven mismatch or a different UID drops it. Per-operation path/resource failures cannot establish disappearance. Carried readings share the next complete sequence but never become listing anchors, current memory or current population. They can collapse under ordinary pressure while conserving admitted CPU and sampled maxima. Recent records explicitly retain census membership; final sequence alone is insufficient.

The checked parent identity and worker identity use BSD start microseconds in the same domain. Only an exact preceding-census node with parent start no later than worker start may supply context. A one-node resolver overlay freezes the row without entering the live graph, consuming enrichment or triggering listings. A later census cannot supply a newer owner for the held endpoint. Parent departure does not erase already frozen evidence. Polling can still miss exec/reparenting, and the candidate's CPU remains unresolved when prior context cannot establish ownership.

### Inspection coverage and shutdown

`inspectionCoverage` is present in every JSONL report and accounting window: disabled/enabled/mixed mode, opportunities, enumeration failures, candidate outcomes, carried/superseded/dropped/discarded readings and maximum complete-deadline lateness while supplemental work was in progress. Counts sum and maxima survive unit/report coalescing and whole-unit history eviction. Complete-scan timing, read coverage, endpoints and CPU denominators exclude supplemental attempts. TUI coverage details alone add the between-scan row when any retained interval was enabled; Mac rows and controls remain unchanged. Pause/close/run replacement discard unadmitted evidence. Cancellation preserves a fixed-size `LiveInspection.terminalCoverage` projection, including when the last accepted unit was already delivered; no duplicate CPU report or synthetic endpoint is emitted. TUI joins its owned collection task before reporting nonzero terminal discards at exit; SwiftTUI cancellation alone does not join task cleanup.

Deterministic guards cover admission, census-only memory/population, frozen parent context, bounded discovery, missing reads, counter reset, PID reuse and cumulative-counter conservation. The [bounded native comparison](../research/cpu-accounting.md#bounded-inspection-comparison-retry--2026-10-26) measured improved 50 ms-worker capture and no skipped opportunities, but persistent short-worker loss and enabled cost above the exploratory target. It does not close short-worker or sustained-load shipping gates. Further native trials require separate authorization.

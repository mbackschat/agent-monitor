# Resource accounting across process lifetimes

Status: **approved**, 2026-10-24. First-delivery implementation authorized on 2026-10-24: fixed-cadence independent acquisition, retained accounting and point-evidence attribution; optional capabilities remain separately gated. Design for CPU-01; priority and acceptance expectations belong in [CLAUDE.md](../../CLAUDE.md#product-priority) and [resource visibility](../architecture.md#resource-visibility-requirements). The [retained-counter foundation](../architecture.md#retained-counter-accounting) and [independent acquisition](../architecture.md#independent-acquisition) are implemented. One-second accounting units with independent display windows, frozen point-candidate contributions and conservation-preserving report coalescing are implemented; historical ancestry support and acceptance measurements remain open; adaptive sampling is not implemented. The [second-review assessment](../research/cpu-accounting.md#second-review-assessment--2026-10-23) and [first-review assessment](../research/cpu-accounting.md#external-review-assessment--2026-10-23) records evidence, disagreements and unresolved experiments.

## Recommendation

Accounting serves the [product question](../product.md): identify the agents, sessions and processes consuming CPU or memory. Reliable totals must be interpretable in that context, not merely correct counters. Normal collection retains bounded rolling state in memory; it does not enable the separate default-off recorder.

The implemented [resource overview and recent activity contract](../architecture.md#contributor-overview-and-recent-activity) captures the user's subsequent 2026-10-24 requirements for Main contributors, session/worker-family navigation and retained recent statistics across Mac and TUI. It is a separately approved extension; its defaults, historical-memory additions and exploration UI are not part of this proposal's original approved first delivery.

The addendum's capacity revision proposes immutable labels and compact closed units for the initial live recent-history view, deferring retroactive updates to that view. This is an approved scoped delivery choice, not implementation of or removal of the broader evidence-revision contract below. Recording must still retain authoritative revisions under its own contract; compact live summaries are not a substitute for the raw observations needed to support them.

Require independent acquisition at a fixed, selectable cadence, prompt bounded evidence capture, automatic background attribution and retained interval measurements. The smallest useful scope is counter acquisition with retained point-in-time launch-origin labels; interval-supported attribution is a separate capability gated on generation access and adapter semantics. This establishes a measurable baseline before enabling adaptation. Keep global adaptation as a proposed, validation-gated option, preserving the user's requested direction. Scheduler tracing is a separate optional investigation because its conservation tests failed. Deeper inspection may be on demand; identifying responsible agents must not depend on opening a row.

## Required contract

### Acquisition and resolution

| Responsibility | Required behavior |
| --- | --- |
| Counter acquisition | Enumerate all in-scope lifetimes, capture counters and host observations, preserve identity checks and monotonic times, and record scan start/end plus each process's read time. Filters and unresolved ownership cannot exclude discovery. |
| Prompt evidence | Resolve observed parent links to exact lifetime identities. On discovery or a detected execution change, attempt a small allowlisted marker/invocation read inline under an explicit per-scan work budget. Overflow is queued with its discovery time and a late/not-captured status. Marker/invocation reads are explicitly acquisition work, including their latency in achieved-period p99/max. The budget bounds attempts/bytes and checks elapsed work between calls; it cannot interrupt a stalled syscall. A stalled read remains visible as acquisition lag, not a claimed deadline guarantee. |
| Background resolution | Interpret captured evidence through adapters, read mutable descriptor/socket/cwd observations, and refresh provider listings automatically. Provider commands and descriptor/socket/cwd enumeration run only on background executors; they never run inline on the acquisition thread. The explicitly listed native counter and marker/invocation reads remain acquisition work. Publish immutable, versioned resolution results tied to original evidence and contribution identities. |
| Presentation | Refresh independently, show separately qualified point and interval-supported ownership beside measurements and retain historical contributors. Pausing a view does not pause acquisition. Historical-only rows cannot initiate actions. |

Use a dedicated serial acquisition thread with an explicit, reported QoS; do not run synchronous native acquisition or blocking provider commands on Swift's cooperative executor. Background blocking work and recording use separately bounded execution resources. QoS is not a real-time guarantee or CPU-core assignment. Select QoS and cadence from owned-load measurements, including achieved p50/p99/max periods under saturation, rather than assuming a requested timer interval is achieved. No overlapping scans or unbounded catch-up work. This design chooses bounded-attempt inline marker capture, not a simultaneous promise that all evidence reads are non-blocking. If measured marker-read tails fail the acceptance bounds, revisit the evidence-thread alternative with measured handoff loss; do not claim the present design passed.

Structural ancestry is the preferred evidence for churned descendants when verified ancestors provide an unambiguous association. A shared runtime or an unresolved parent does not establish session ownership. Parent ordering uses native monotonic birth observations when available; a wall-clock comparison alone cannot verify an ancestry edge after a clock adjustment. Missing parent birth/evidence remains unknown. Retain observed edges with their times; a later live graph cannot rewrite an earlier path.

### Evidence validity and execution changes

| Evidence class | Cache and validity contract |
| --- | --- |
| Execution-bound candidates | Captured launch markers and invocation/executable observations may be reused as interval-supported facts only within a verified execution epoch and the adapter's stated semantics. Cached point labels remain usable with original timestamps, age and uncertainty; they cannot be promoted merely because they were cached. A path, image UUID, process name or unchanged footprint peak does not prove that no same-path exec occurred. Environment/argument observations are not automatically immutable merely because no exec was detected. |
| Point observations | Registry bindings, descriptors, sockets and cwd carry observation times, refresh policies and unavailable states. A refresh deadline is a cost/freshness policy, not proof of continuous validity between observations. |
| Historical support | An interval-supported fact cites evidence covering the contribution's entire measured interval. Extended coverage requires a documented provider guarantee or verified continuity; otherwise retain point observations and interval uncertainty. |

A reliable supported-OS execution-generation mechanism remains a feasibility gate for caching across scans. Fresh task-name-port audit tokens detected same-path exec in [20 owned-child trials](../research/cpu-accounting.md#controlled-same-path-exec-follow-up), while retained ports failed after exec. Adopt this as the leading candidate; arbitrary target access, scan-scale cost and generation/counter read-race handling remain gates. Path/name/UUID changes or a falling kernel footprint peak may invalidate a cache but cannot certify stability. Without a verified generation or continuity guarantee, refresh candidate evidence and expose the unobserved transition risk; do not reuse old markers as certain historical ownership. CPU counter continuity and attribution-epoch continuity are separate questions.

The interval-support rule for an execution-bound claim requires all of the following: each counter endpoint and its supporting evidence are bracketed by freshly acquired audit-token observations; verified lifetime/UID matches throughout; both brackets agree on the same generation; and the adapter declares, with retained evidence for its semantics, that this particular claim cannot change within that verified epoch. Fresh acquisition is required at both sides of each bracket; a cached task port is insufficient. Preserve read order/times, reject mismatches or unreadable brackets for interval support, and release acquired rights. Generation uniqueness/exec-change semantics for the target class and observation span must first be validated. A matching generation is necessary for this rule, not sufficient by itself.

Each attribution adapter owns a versioned declaration of the support scope of its claims, including whether its marker is immutable within an exec, what native/provider guarantees that relies on, and tests/source provenance. Hosts supply native observations; the sampler cannot invent provider immutability. No current adapter declares this guarantee, so absence of a validated declaration defaults to point evidence. Mutable registry membership is not made interval-valid by equal generation or equal session values at two endpoints. Derived claims inherit the weakest support of the evidence and ancestry links actually needed for that claim.

For example, observing session A at t=60 and B at t=120 does not establish that A owned 60–120, or that a contribution spanning 70–110 belonged exclusively to either. The transition time is unknown; other unobserved owners are not excluded. Preserve these observations and report uncertain ownership until evidence actually covers the contribution. Even equal endpoint observations do not prove continuity without a supporting contract.

Support is evaluated **per attribution level**, not for the entire `Attribution` object at once: provider, exact runtime, exact provider/session identity, terminal and ancestry can have different evidence strength. For example, provider/runtime may be interval-supported while session ownership has only a point observation or conflicting candidates. Uncertain session membership must not erase supported provider/runtime accounting.

```swift
struct MeasuredInterval: Sendable {
    let start: Double
    let end: Double
}

enum AttributionFact<Value: Sendable>: Sendable {
    case pending
    case point(value: Value, observedAt: Double, evidenceIDs: [UUID])
    case supported(value: Value, interval: MeasuredInterval, evidenceIDs: [UUID])
    case uncertain(candidates: [Value], evidenceIDs: [UUID])
    case unavailable
}
```

Apply this distinction independently at each level, preserving provider-qualified session identities. Candidates are not necessarily exhaustive. Evidence and fact revisions are retained with the contribution; resolved ownership is never recomputed from the current registry/graph. Contradicting evidence may revoke support into uncertainty, with the prior revision preserved. Greater specificity requires new evidence for the same measured interval. Observation time, supported interval and resolution time are distinct.

### Useful point evidence without invented certainty

At contribution closure, freeze the available launch-origin label and the original times/IDs of the observations behind it, not the resolver's current time. A cached label retains its actual age and execution uncertainty. If no label has arrived, keep it pending; later evidence adds a recorded revision rather than silently replacing the original label. Initial implementation retains today's point-label semantics and does not require unvalidated generation-based caching or interval support to show a process under its observed candidate session.

A single session candidate appears inside that session under a separately labeled **point-evidence candidate** subtotal, showing evidence time/age and uncovered interval when relevant. Keep **interval-supported CPU** distinct; do not silently merge the two into a claimed supported session total. Multiple/contradicted candidates appear once in an uncertain-contributor area with links to alternatives, never counted in several session subtotals. A contribution with no candidate remains visible as unresolved. Count each contribution once in each population total; nesting provider/runtime/session rows cannot add another copy. CPU units, report-window eligibility and recovered-across-gap exclusions are unchanged by attribution strength.

This is a fallback in evidence strength, not a reason to hide a known single candidate as generic unknown or to call it the statistically most likely owner. A point observation does not prove historical ownership even if it matches at both endpoints. Text, JSONL, TUI and the Mac app expose the distinction consistently.

### CPU conservation and report windows

Retain the last valid cumulative counter and observation ID per exact lifetime and compatible counter generation across temporary read failures. Compare it with the next valid read even when intervening scans failed. Record those gaps; a recovered delta supplies total CPU over its endpoints, not its distribution inside the gap. Decreasing/reset counters, uncertain counter continuity, baseline eviction or a reused PID break the baseline with a reason. Retention is bounded; eviction cannot silently become measured zero. Recovery of final CPU after exit remains unresolved, and [reaped-child counters](../decisions/exited-descendant-cpu.md) remain excluded.

For a first valid counter after failed observations, locate the retained listing immediately preceding that lifetime's verified monotonic birth. A synthetic zero baseline is permitted only when birth follows the acquisition run's initial listing, the counter is known to accumulate from birth, and the lifetime has never already supplied a valid baseline or accepted CPU in the retained accounting domain. Failed BSD/resource/identity reads do not by themselves make a lifetime pre-existing. Retain listing history and the first-accounted/baseline state long enough to make this decision; if the necessary history is evicted, report baseline unavailable rather than add the full cumulative counter again. PID reuse is a new exact lifetime, not evidence about the old one.

For example, L0=10, birth=10.5, a failed read at L1=11 and a first valid read at L2=12 recover cumulative CPU from a zero at L0. The opening is not L1: that would incorrectly assign pre-L1 CPU to a later window. A process born before the acquisition baseline is ineligible, even if all its early reads failed. This rule supplies an enclosing interval with zero before birth, not a claim about when within the lifetime CPU was spent. Capture start/resume boundaries remain separate exclusions for recording replay.

```swift
enum CPUOpeningReference: Sendable {
    case observation(id: UUID)
    case newbornZero(runID: UUID, listingSequence: UInt64, verifiedBirth: Double)
}
```

An accepted delta is identified by its opening reference and closing observation ID and counted once. A newborn zero refers to an actual retained pre-birth listing ID, not an invented process observation. Persist the eligibility/birth evidence needed to replay it. Logical report membership uses scan indices: a report contains closing observations in `(baselineScan, finalScan]`. A delta whose opening observation or synthetic listing reference predates the baseline scan is emitted separately as recovered CPU-seconds with its real interval and excluded from that report's rate. Do not prorate it or attach it to the newest session. A wider analysis window may include it once if its opening reference and closing observation are within that window.

For ordinary deltas, the common rate denominator is the enclosing monotonic observation window, from the baseline scan's listing time to the final scan's end. This encloses the constituent read intervals; expose those intervals and scan spread. Consecutive windows can overlap by a scan duration because collection is not atomic. They are not exact nonoverlapping wall-time partitions, and their durations/rates must not be summed. Conservation is tested on unique accepted deltas, including the distinct newborn-zero opening form. When coalescing reports, merge scan ranges and recompute membership, denominator and deduplicated contributions from their endpoints; do not drop older contributions or add percentages.

Window CPU is explicitly observed CPU per enclosing window, not complete system occupancy. Mark missing/uncertain measurements, baseline exclusions and separately recovered CPU. Session totals ignore display filters. Host occupancy, current-user measurements, known agents, monitor/helpers and unresolved ownership remain distinct populations; differences do not classify load.

### Coverage and memory

Native outcomes retain the operation, listed PID, verified identity if available, return length/status and immediately captured errno on failure. Distinguish permission denied, lookup unavailable/ESRCH, short reads, identity mismatch, counter unavailable and other failures. Readable out-of-scope users are separate from read failures. ESRCH alone does not prove normal exit or distinguish a reaped worker from every other unavailable state. Counts describe observed failures, not processes never listed. Raw outcomes must be available to recording and controlled probes.

Current footprint always carries its observation time and availability. Independently sampled values are observed aggregates with scan spread, not exact simultaneous memory. Kernel footprint peaks remain separate and may reset on exec. Historical process values must not inflate current totals. Delayed ownership cannot safely reconstruct a session peak from today's membership or from a shared ancestor label. A historical session peak is optional until retained per-scan observations and interval-supported attribution can establish it.

Bound contribution/evidence storage and report queue pressure explicitly. Superseded display snapshots may be coalesced only by the conservation rule above. Lost observations or evidence produce affected-interval gaps; they cannot silently become zero load. A slow resolver cannot stall acquisition or create unbounded memory use.

### Acceptance evidence

Fix allowed coverage/attribution regressions before running comparisons. Use repeated owned workloads, initially at least 100 workers per duration group with randomized start phase, and report uncertainty across runs rather than treating this count as a statistical guarantee. Include nested descendants, same-path exec, session changes, first-read and repeated-read failure injection, quiet and saturated hosts, and delayed/failing fake providers/consumers.

Retain per-worker listing/read timestamps and outcomes so never-listed, listed-but-unreadable, baseline exclusions and final-tail loss can be distinguished. Compare retained CPU with independent `wait4` ledgers by duration group, including total and tail loss. Derive a coverage expectation from actual lifetimes, scan timing and listing-to-read delay; a worker's requested CPU duration is not its wall-clock lifetime. Report cadence p50/p99/max, monitor/helper CPU, stage costs and bounded memory. Guard newborn recovery after one/multiple failed reads, pre-existing lifetimes, PID reuse, evicted baselines and capture resume. Verify mixed-strength provider/runtime/session claims and single-candidate subtotals without duplication. The existing four-worker groups and aggregate prototype results do not establish these properties.

## Optional

### Adaptive acquisition

This design changes the requested interval of the whole collector to reduce cost during low activity. The user reports commonly leaving Agent Monitor running for long periods with little relevant activity. Support that use case with idle agent sessions present as well; useful savings must not require all agents to disappear. The rolling controller below replaces the earlier reset-on-every-increment proposal and remains under review. It is not implemented or covered by first-delivery implementation authorization. Display refresh, metadata/provider freshness, scope, accounting and attribution retain their separate contracts.

#### Settings and limits

Mac and TUI share the controls below except the Mac-only closed-panel multiplier. The target values are policy candidates, not validated defaults. Until slower defaults receive the acceptance described below, initial settings use minimum = visible maximum = 100 ms and multiplier = one; adaptation may be enabled but requests fixed 100 ms. Mac options remain in memory until quit; this design adds no persistence.

| Setting | Type | Target | Contract |
| --- | --- | --- | --- |
| Adaptive sampling | Boolean | Enabled | Off means **Use maximum interval**, not stop sampling. |
| Minimum interval | Duration | 100 ms | Shared by all contexts. |
| Visible maximum interval | Duration | 250 ms | The existing interval control; applies to the open Mac panel and TUI. |
| Closed-panel maximum multiplier | Finite scalar | 2.5 | Mac only; multiplies the visible maximum in both adaptive and maximum-interval mode. |
| Rolling activity window | Duration | 60 s | Recent evidence contributing to the load estimate; activity never restarts this window. |

The target ranges are 100–250 ms for the open Mac panel and TUI, and 100–625 ms for the closed Mac panel. There is no independently configured closed-panel minimum or maximum. Require 0.1 s ≤ minimum ≤ visible maximum ≤ 60 s, a rolling window between 1 and 300 s, and a finite multiplier ≥ one whose derived maximum is also ≤60 s. Reject invalid combinations together; do not silently clamp or introduce sub-100 ms polling. The window cap bounds retained control history. Fixed 100 ms remains selectable by setting both intervals to 100 ms and the multiplier to one.

The existing `--interval` name, its 0.1–60 s range, TUI faster/slower steps and native presets (including 15 s) remain. In TUI/native adaptive mode this control sets the visible maximum, not the current requested interval. An explicit interval overrides that setting's default. For example, `agent-monitor --tui --interval 1` with adaptation enabled requests 100 ms initially and relaxes toward 1 s; with adaptation disabled it requests 1 s. Controls skip steps invalid under the configured minimum or Mac multiplier; explicit invalid settings fail validation. CLI text/JSONL retain their existing fixed-interval meaning and defaults.

On Mac, selecting a 5 s visible maximum with multiplier 2.5 permits 12.5 s while closed, including when adaptation is disabled. This intentionally supersedes the current promise that closing preserves the selected cadence. With adaptation disabled, drop the existing initial 250 ms cap and use the applicable maximum from startup; with adaptation enabled, startup uses the minimum. Implementation must update the selected-cadence wording in [resource history](../architecture.md#resource-history), startup behavior in the [native app contract](../architecture.md#native-menu-bar-app), `--interval` help, the [README option table](../../README.md) and [usage](../usage.md) together. These documents continue describing shipped behavior until that implementation.

**Rationale:** sharing the minimum preserves the ability to return to 100 ms during background activity. Multiplying both bounds would impose a 250 ms background floor even during a build. The larger closed-panel maximum expresses a deliberate cost/coverage tradeoff when the user is not inspecting the panel; 2.5 is a configurable policy choice, not a measured CPU-cost ratio. Disabling adaptation has the user's requested maximum-interval meaning, which must be explicit in the control label.

#### Rolling activity and fast response

Evaluate evidence before display filtering within the measured scope (same-user by default). Scope requires the scoped enumeration contract or verified UID; an arbitrary listed PID alone does not establish membership. Known out-of-scope activity is excluded. Exclude the collector and its owned helper descendants using the existing exact-lifetime, retained-ancestry rule in [independent acquisition](../architecture.md#independent-acquisition), exemplified by [diagnosis helper classification](../../Sources/AgentMonitorCore/CPUDiagnosisWindow.swift). Retain proven helper ownership across ancestor departure within existing retention limits; neither a name nor a reused PID can inherit it. Unproven helper ancestry cannot suppress potentially unrelated work. Monitor/helper cost remains separately measured.

Each complete acquisition supplies a timestamped aggregate of:

- **Eligible CPU:** newly accepted CPU contributions on in-scope non-monitor lifetimes, unless completed resolution establishes no agent candidate. Pending, point, uncertain and supported evidence all qualify. Queued/coalesced metadata is pending, not a completed negative result. Small positive increments add their quantity; they do not reset a timer.
- **Arrivals:** newly listed in-scope PID episodes or verified replacement lifetimes. Count an unresolved arrival once; later verifying that same arrival is not a second event. An admitted supplemental lifetime counts at its admitting complete scan if not already counted. Startup establishes the existing population without counting it as arrivals. The highest PID is not a creation counter.
- **Departures and uncertainty:** newly observed absence/replacement of a tracked lifetime, failed complete listings, and unavailable counters required for eligible CPU. Absence is a transition, not proof of exit. Repeated absence/unreadability is not repeated churn. An in-scope unreadable arrival still counts; known out-of-scope failures do not.

Keep these acquisition aggregates over the trailing rolling window, not a raw process log or a timer measuring time since the last event. Retain at most one aggregate per complete acquisition, bounded by the configured window and minimum interval; the 300 s window cap and 100 ms minimum admit at most 3,002 aggregates including boundary records. CPU is charged once when its contribution becomes available, including recovery after missing reads. This is an evidence-arrival rate for control, not a reconstruction of when the CPU executed. Do not prorate a contribution across guessed execution times or rewrite accounting. Recovered older CPU can conservatively keep sampling faster. Eligibility is frozen when the contribution enters the controller; later attribution does not erase historical control evidence.

The initial calibration candidates are explicit below. They are reviewable policy assumptions, not measurements or newly exposed advanced controls; validation may require revising them before slower defaults are adopted.

| Control quantity | Low-activity bound | Busy bound | Meaning |
| --- | --- | --- | --- |
| Rolling eligible CPU rate | 1 ms CPU-time/s | 20 ms CPU-time/s | Aggregate execution time, not performance-core capacity or a display threshold. |
| Rolling arrival rate | 2 arrivals/min | 20 arrivals/min | In-scope, non-monitor arrivals; no session resolution required. |
| Fast-response lookback | — | 1 s | A short window for CPU bursts and lifecycle transitions. |

At acquisition completion time `t`, use observations in `(t − H, t]`. Divide summed CPU/counts by `min(H, t − controllerHistoryStart)`; this start is the current control-history baseline, including after enabling or changing settings during a long-running collection. Use actual represented time rather than filling an unobserved minute with zeros. The first control baseline supplies no rate. With `H` equal to the configured rolling window, derive the base target:

```text
cpuRate: Double = eligibleCPUSeconds / observedWindowSeconds
arrivalRate: Double = arrivalCount / observedWindowSeconds
cpuScore: Double = clamp((cpuRate − 0.001) / (0.020 − 0.001), 0, 1)
arrivalScore: Double = clamp((arrivalRate − 2/60) / (20/60 − 2/60), 0, 1)
activityScore: Double = max(cpuScore, arrivalScore)
baseTarget: Duration = contextMaximum − activityScore × (contextMaximum − minimum)
```

Both rate fractions use real-number arithmetic. At or below both low bounds the target is the maximum; at or above either busy bound it is the minimum; intermediate activity gives an intermediate target. Shorten the base interval immediately when its target decreases. Lengthen it by at most `(contextMaximum − minimum) × elapsedSincePreviousAcquisition / rollingWindow` per complete acquisition, capped at the target. This bounds upward movement if old evidence expires together. Maintain that base progression independently of temporary fast overrides.

Independently compute eligible CPU rate over the 1 s lookback. Request the minimum while that rate reaches 20 ms CPU-time/s, or while an arrival or departure transition remains in that lookback. A one-off lifecycle event therefore buys a short observation period, not another minute at fast sampling. After the event ages out, return to the contemporaneous base interval; do not restart its progression. Persistent lifecycle churn can sustain the override and is an explicit cost of protecting short workers.

While complete-listing evidence or required counters for a currently listed eligible lifetime are unavailable, hold the minimum and prohibit upward base progression. A successful complete listing restores listing evidence. A valid counter read, verified replacement or absence from a successful scoped listing retires the corresponding live counter-blocking condition; unresolved final CPU remains disclosed and is not converted to zero. Absence does not assert exit. Once no blocker remains, begin upward progression from the minimum with the retained rolling history. Missing evidence cannot become low activity merely by aging out. Baseline establishment and first-counter exclusions are distinct from a native read failure. Only completed negative resolution or proven scope/helper exclusion permits treating an already-listed unreadable process as unrelated; missing identity or pending attribution does not.

**Rationale:** tiny periodic CPU increments are quantitatively different from sustained work. A modeled 1 ms heartbeat every five seconds contributes 0.2 ms CPU-time/s over a full minute, below the proposed low bound, and never restarts the window. Its transient rate during startup is evaluated using actual elapsed time; there is no lifetime-long guarantee that it cannot briefly trigger fast response. A rolling mean alone can dilute a new burst, so recent CPU and lifecycle evidence can temporarily force the minimum without discarding long-window state. Arrival rate prevents unclassified churn from appearing quiet; pending CPU prevents attribution backlogs from suppressing activity. The low and busy bounds create a continuous response, not separate enter/exit hysteresis thresholds. The rate limit supplies gradual relaxation without a reset-on-heartbeat mechanism.

#### Mode and deadline precedence

Startup or enabling adaptation starts fresh control history at the current acquisition boundary and sets the base interval to the minimum; enabling never resets process counters or accounting baselines. Opening the Mac panel resets the base interval to the minimum while retaining valid history; closing preserves it and changes only the context maximum. Clamp the base interval to new context bounds before applying the normal rule. Changing adaptive acquisition settings restarts the controller at the minimum with fresh control history, without clearing accounting or changing process baselines. Grouping and display-filter changes do not reset it. Presentation pause does not stop acquisition or activity detection.

When experimental discovery is enabled **and** its run-local inspection permission is active, request the minimum in either adaptive or maximum-interval mode. Permission alone does not activate a disabled discovery feature. Keep updating valid control history; on leaving inspection resume the current base interval if adaptive, otherwise the context maximum. The discovery algorithm, limits and census-membership rules remain unchanged. Coverage details identify this override.

Otherwise, adaptation-off requests the applicable maximum, including at startup; activity and uncertainty do not silently re-enable adaptation. In adaptive mode, uncertainty and fast-response overrides take precedence over the base interval. All overrides and rate bounds apply only when collection is running.

Activity is evaluated after complete acquisitions and cannot wake collection before it is observed. UI events can advance a pending deadline to `max(now, lastStart + newInterval)`. Once a deadline is due, do not defer the scan or erase its timing baseline. An in-flight read cannot be interrupted; there are no overlapping scans or catch-up bursts.

#### Lifecycle and visibility

Presentation pause does not stop acquisition or activity detection. Static icon mode retains its current lifecycle: closed-panel collection is off, and reopening starts a fresh acquisition baseline. Adaptive sampling does not add background collection to that mode. TUI uses the visible range without attempting to infer terminal-window visibility and does not expose the Mac multiplier. Advanced controls expose the mode and configured bounds together with the existing interval controls.

Coverage details show adaptive versus maximum-interval mode, the current requested and base intervals, applicable bounds, rolling CPU/arrival rates and active overrides. Retained windows record requested-interval ranges, policy changes, time under each override and per-reason activation counts; entering an override counts once, remaining there is duration rather than repeated activations. Counts/durations sum on merge instead of exposing a flickering latest reason. Pair maximum achieved gap with maximum requested interval. For each start-to-start period, retain the effective deadline after any UI change: overrun means the achieved gap exceeds 1.5× `(effectiveDeadline − lastStart)`, never 1.5× a later setting or the window's maximum. Once a deadline has elapsed, later policy changes cannot erase its measurement baseline or defer the due scan. Preserve existing count/sum/max aggregation. Display refresh remains independent. Policy changes cannot discard accepted CPU, redefine totals through filters, or manufacture ownership or final-exit measurements.

#### Limits and evidence required

The first burst after low activity can be partly or wholly missed before any trigger is observed. Sparse short jobs can repeatedly fit between scans and never trigger acceleration; their identity-discovery loss may remain large even when their share of total CPU is small. Low measured rates establish little observed evidence, not absence of work. Many individually small heartbeats can exceed the aggregate CPU bounds. Same-user arrivals/departures trigger even when resolution finds no agent candidate, so browser or other background churn can sustain fast overrides despite quiet agents; their CPU exclusion does not suppress lifecycle signals. Report that override duty explicitly, not as a claimed saving. Long-lived workers whose completed resolution finds no agent candidate have no CPU trigger; their intervening cumulative CPU remains recoverable while readable, but their final tail and memory age can grow with the slower cadence. Requested periods are not scheduling guarantees, so 625 ms is not a guaranteed bound on actual tails.

Correctness gates prohibit wrong ownership, duplicate CPU, discarded accepted contributions and falsely current historical memory. They do **not** require slower sampling to discover everything fixed 100 ms discovers: the former zero-additional-loss gate would reject the intended tradeoff by construction. Before changing initial defaults, present per-duration/per-scenario identity retention and accepted CPU against fixed 100 ms, including sparse jobs and each visibility context, together with scan-count savings. Use common baseline boundaries and a horizon that includes all modeled departures and final admissions. The user must accept an explicit coverage-loss budget and the measured savings before the 250/625 ms targets become defaults; that budget is unresolved, not silently zero or unlimited. Until then, initial settings remain equivalent to fixed 100 ms. Do not average short-worker losses away using sustained CPU or treat passing accounting conservation as approval of slower defaults.

Compare adaptive acquisition with both fixed 100 ms and fixed context maximum. In modeled low-activity periods, including low-amplitude heartbeats with agents present, it must reduce scan count versus the minimum and reach the maximum after the base ramp when both rolling scores are zero and no override applies. In modeled detectable bursts it must request the minimum on the first qualifying observation. Report coverage against both fixed baselines: phase alignment can make an individual lifetime worse even at a faster mean sampling rate, so per-lifetime dominance over fixed maximum is not an unconditional correctness claim. Report scan count and time at each requested interval as offline cost proxies, not native CPU measurements. Separate accepted CPU, never-read CPU and final tails.

The [offline lifecycle fixture](../../Tests/AgentMonitorCoreTests/WorkloadCoverageTests.swift) is a foundation, not sufficient coverage as written. Extend its production `MonitoringSession` loop beyond the rolling window (at least 180 s for defaults), with pending/negative/point/uncertain/supported attribution, failed listings/reads, out-of-scope PIDs, retained helper ancestry and nonzero scan durations. Include low and high aggregate heartbeats, long-lived agents resuming CPU, sustained low CPU, sparse/dense bursts (including 50, 200, 500 and 1,000 ms workers), same-user completed-negative churn, a fake provider's short-lived child, staggered providers, PID reuse and all settings/visibility/static/inspection transitions. Guard window expiry, exact threshold boundaries, partial startup/reset windows, recovery deltas crossing the lookback boundary, retirement of uncertainty after absence, one-arrival-one-count, the aggregate cap, and the independence of base relaxation from a brief override. A modeled 1 ms heartbeat every five seconds must not continually restart relaxation; a single lifecycle event must not erase a minute of history. The policy sees only observations its own schedule obtains. Independent synthetic ground truth supplies the coverage oracle.

Before committing to production settings/UI, use the offline controller prototype to establish useful behavior in these modeled low-activity scenarios. Actual idle-agent CPU and churn distributions still need calibration before slower defaults are adopted. An available authorized recording can approximate executable/ancestry activity and time-at-interval, but has no session attribution, is quantized to its acquisition grid and omits unseen workers; it cannot replace the closed-loop oracle. Aggregate-only summaries cannot reconstruct this timing. A small aggregate-only diagnostic of trigger rates and proposed time-at-interval is an alternative to another large raw recording, but any live collection needs a separate explicit request. [ADAPT-01](../../PLAN.md#resource-accounting-priority) tracks this evidence gap. Native cost/cadence and closed-panel/App Nap claims also require separately authorized measurement; the user's reported long low-activity usage establishes the intended use case, not a measured idle distribution or CPU saving.

Excluded from this adaptive design: per-process rates, shortest-observed-age estimation, host-load subtraction, memory-driven activation, periodic extra probe scans, separate hysteresis thresholds, new intensive modes, changes to experimental discovery's read/admission algorithm, automatic recording and changes to CLI text/JSONL acquisition defaults.

### Other optional capabilities

- Bounded scheduler tracing, only after supported capture/decoding, conservation, lifecycle joins and loss detection pass separate gates. The existing `xctrace` experiment is not a reliable backend and is not a requirement for independent native collection.
- Historical per-session observed memory peaks, retaining original per-process scan values and defensible ownership. Exact ancestry anchors alone cannot prove session continuity. Maximum observed process kernel peaks may be retained as separately labeled historical observations, with verified exec boundaries where available.
- Separate per-process sampling rates, only after proving meaningful CPU-window and memory-age semantics against global collection.

## Dependent diagnostic recording

The [recording proposal](diagnostic-recording.md) consumes raw observations, failure records and versioned attribution evidence after this acquisition contract exists. It shares CPU acceptance rules and preserves recorded attribution revisions as authoritative historical labels, while exposing retention/pause gaps. Recording or compression cannot hold acquisition.

## Excluded

Purely on-demand basic attribution, automatic installation of privileged services, changing system security, unrestricted transcripts/environment collection, guessed shared-runtime ownership, arbitrary CPU proration and automatic actions on user workloads. No tracing result establishes an exact memory peak.

## Material feasibility gates

Counter acquisition with point labels is the first specified scope; it still needs implementation and controlled acceptance measurements. Execution-generation access, bracketing cost/races and adapter evidence-continuity declarations gate interval-supported attribution, not basic point-label visibility. Inline-read latency, fixed cadence/QoS under contention and baseline retention bounds remain unvalidated. Polling can miss lifetimes entirely and cannot recover final counters reliably after reaping. Implementation authorization does not close these gates; retained experiments and explicit uncertainty are required.

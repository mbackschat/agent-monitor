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

This agreed design changes the requested interval of the whole collector to reduce cost during observed quiet periods. It is not implemented and remains outside this proposal's first-delivery implementation authorization. The existing fixed-cadence behavior remains current until implementation is requested. Display refresh, metadata/provider freshness, process scope, accounting and attribution retain their separate contracts.

#### Settings and limits

Mac and TUI share the controls below except the Mac-only closed-panel multiplier. The target values are policy candidates, not validated defaults. Before the default-change gate below passes, initial settings use minimum = visible maximum = 100 ms and multiplier = one; adaptation may be enabled but requests fixed 100 ms. Mac options remain in memory until quit; this design adds no persistence.

| Setting | Type | Target | Contract |
| --- | --- | --- | --- |
| Adaptive sampling | Boolean | Enabled | Off means **Use maximum interval**, not stop sampling. |
| Minimum interval | Duration | 100 ms | Shared by all contexts. |
| Visible maximum interval | Duration | 250 ms | The existing interval control; applies to the open Mac panel and TUI. |
| Closed-panel maximum multiplier | Finite scalar | 2.5 | Mac only; multiplies the visible maximum in both adaptive and maximum-interval mode. |
| Quiet window | Duration | 60 s | Time without observed activity needed to reach the maximum. |

The target ranges are 100–250 ms for the open Mac panel and TUI, and 100–625 ms for the closed Mac panel. There is no independently configured closed-panel minimum or maximum. Require 0.1 s ≤ minimum ≤ visible maximum ≤ 60 s, a positive finite quiet window, and a finite multiplier ≥ one whose derived maximum is also ≤60 s. Reject invalid combinations together; do not silently clamp or introduce sub-100 ms polling. Fixed 100 ms remains selectable by setting both intervals to 100 ms and the multiplier to one.

The existing `--interval` name, its 0.1–60 s range, TUI faster/slower steps and native presets (including 15 s) remain. In TUI/native adaptive mode this control sets the visible maximum, not the current requested interval. An explicit interval overrides that setting's default. For example, `agent-monitor --tui --interval 1` with adaptation enabled requests 100 ms initially and relaxes toward 1 s; with adaptation disabled it requests 1 s. Controls skip steps invalid under the configured minimum or Mac multiplier; explicit invalid settings fail validation. CLI text/JSONL retain their existing fixed-interval meaning and defaults.

On Mac, selecting a 5 s visible maximum with multiplier 2.5 permits 12.5 s while closed, including when adaptation is disabled. This intentionally supersedes the current promise that closing preserves the selected cadence. With adaptation disabled, drop the existing initial 250 ms cap and use the applicable maximum from startup; with adaptation enabled, startup uses the minimum. Implementation must update the selected-cadence wording in [resource history](../architecture.md#resource-history), startup behavior in the [native app contract](../architecture.md#native-menu-bar-app), `--interval` help, the [README option table](../../README.md) and [usage](../usage.md) together. These documents continue describing shipped behavior until that implementation.

**Rationale:** sharing the minimum preserves the ability to return to 100 ms during background activity. Multiplying both bounds would impose a 250 ms background floor even during a build. The larger closed-panel maximum expresses a deliberate cost/coverage tradeoff when the user is not inspecting the panel; 2.5 is a configurable policy choice, not a measured CPU-cost ratio. Disabling adaptation has the user's requested maximum-interval meaning, which must be explicit in the control label.

#### Activity and interval selection

Activity is any of the following, evaluated before display filtering and restricted to the measured process scope (same-user by default). Scope requires the scoped enumeration contract or verified UID; an arbitrary listed PID alone does not establish membership. Known out-of-scope arrivals, departures and CPU do not trigger adaptation. Scope uncertainty remains explicit rather than becoming an agent or lifetime claim.

- A newly listed in-scope PID or newly verified in-scope lifetime, including detected PID reuse. New arrivals trigger before ownership is resolved; the highest PID value is not a creation counter. A supplemental lifetime admitted by the next complete scan also triggers at that admitting scan.
- A tracked lifetime becoming absent from the complete listing or being replaced by a verified different lifetime. This is a transition signal, not an assertion that absence proves exit.
- A positive accepted CPU increment on any in-scope non-monitor lifetime unless completed resolution establishes no agent candidate. Pending, point, uncertain and supported evidence all count, including provider-known work with no exact session. A queued/coalesced resolution request is pending, not a completed negative result. Zero is quiet only when it is a valid measurement.

Exclude the collector and its owned helper descendants using the existing exact-lifetime, retained-ancestry rule in [independent acquisition](../architecture.md#independent-acquisition), exemplified by [diagnosis helper classification](../../Sources/AgentMonitorCore/CPUDiagnosisWindow.swift). Proven helper ownership survives ancestor departure within the existing retention limits; names and PID reuse cannot establish or inherit that exclusion. Unproven ancestry must not suppress a potentially unrelated arrival. Retain monitor/helper cost separately. Startup establishes the initial population rather than treating every existing process as a new arrival. Failed complete listings or unavailable counters needed for eligible CPU triggers reset the quiet timer and hold the minimum; they cannot be interpreted as zero activity. A newly listed but unreadable in-scope process still triggers as an arrival. Repeated unreadability of an unrelated, already-listed PID is not repeatedly counted as a new process. Later attribution cannot retroactively justify an earlier quiet period.

On startup, enabling adaptation or opening the Mac panel, set the requested interval to the minimum and reset the quiet timer. Each activity signal immediately does the same. Otherwise, derive the next requested interval from monotonic time:

```text
quietFraction: Double = clamp(secondsSinceActivity / quietWindowSeconds, 0, 1)
interval: Duration = minimum + quietFraction × (contextMaximum − minimum)
```

Evaluate activity after each complete acquisition; it cannot wake the collector before that observation. UI events (opening, enabling adaptation or changing adaptive acquisition settings) can advance a pending deadline to `max(now, lastStart + newInterval)`. An in-flight read is not interrupted; there are no overlapping scans or catch-up bursts. Closing the Mac panel preserves the quiet timer and changes only the applicable maximum. Changing adaptive acquisition settings while adaptation is enabled restarts at the newly configured minimum; grouping and display-filter changes do not reset it. With adaptation disabled, startup, visibility and adaptive-setting changes use the applicable maximum directly, except for the inspection override below.

When experimental discovery is enabled **and** its run-local inspection permission is active, hold the minimum in either mode. Permission alone does not activate an otherwise disabled discovery feature. Count admitted supplemental lifetimes as arrivals, preserve complete-census membership rules, and expose the override as the effective policy reason. On leaving inspection, restart the quiet timer at the minimum if adaptation is enabled; otherwise return to the context maximum. This prevents a coverage-oriented opt-in from silently reducing discovery opportunities per second; the discovery algorithm and admission limits are unchanged.

**Rationale:** observed process age is not completed lifetime, and slower polling hides short workers, so the fastest observed worker is a biased control signal. Counting pending/uncertain work prevents attribution backlogs from becoming quiet signals; retaining helper ancestry prevents monitor-generated activity from continually resetting the timer. Immediate acceleration and gradual relaxation avoid separate switching thresholds or dwell timers. Any positive eligible CPU increment is deliberately conservative: agent heartbeats may keep collection at the minimum, leaving savings mainly during agent-free periods. Useful savings while agents are idle are unestablished. Consider an activity threshold only after observations establish this problem; no threshold is selected here.

#### Lifecycle and visibility

Presentation pause does not stop acquisition or activity detection. Static icon mode retains its current lifecycle: closed-panel collection is off, and reopening starts a fresh acquisition baseline. Adaptive sampling does not add background collection to that mode. TUI uses the visible range without attempting to infer terminal-window visibility and does not expose the Mac multiplier. Advanced controls expose the mode and configured bounds together with the existing interval controls.

Coverage details show adaptive versus maximum-interval mode, the current requested interval, applicable bounds and inspection override. Retained windows record requested-interval ranges, policy changes and per-reason reset counts; counts sum when windows merge instead of exposing a flickering latest reason. Pair maximum achieved gap with maximum requested interval. For each start-to-start period, retain the effective deadline after any UI change: overrun means the achieved gap exceeds 1.5× `(effectiveDeadline − lastStart)`, never 1.5× a later setting or the window's maximum. Once a deadline has elapsed, later policy changes cannot erase its measurement baseline or defer the due scan. Preserve existing count/sum/max aggregation. Display refresh remains independent. Policy changes cannot discard accepted CPU, redefine totals through filters, or manufacture ownership or final-exit measurements.

#### Limits and evidence required

The first burst after a quiet period can be partly or wholly missed before any trigger is observed. Sparse short jobs can repeatedly fit between scans and never trigger acceleration; their identity-discovery loss may remain large even when their share of total CPU is small. A quiet timer establishes absence of observed triggers, not absence of work. Long-lived workers whose completed resolution finds no agent candidate, such as reparented Gradle/Bazel daemons, have no CPU trigger: cumulative counters recover intervening CPU while they remain readable, but final-tail CPU can span the slow interval times their parallelism, and memory readings become older. Longer gaps also lose memory peaks. Requested periods are not scheduling guarantees, so 625 ms is a policy limit rather than a guaranteed bound on actual tails.

The default-change gate permits **zero additional identity loss and zero additional accepted-CPU loss** against fixed 100 ms, separately for each duration group, activity scenario, visibility context and start-phase case. Every exact identity discovered by the baseline must be discovered adaptively; require `adaptiveCPU + 1e-9 CPU-seconds ≥ baselineCPU` per case, allowing floating-point tolerance rather than a loss budget. Use identical baseline boundaries and a common horizon that includes all modeled worker departures and final admissions. Do not average short-worker regressions away using sustained CPU. This conservative gate follows the existing coverage priority; the agreed willingness to explore slowing does not establish a numerical loss allowance. Sparse short-work cases are expected to prevent the 250/625 ms targets from passing. Retain fixed-100 ms initial settings unless evidence passes or the user explicitly approves a revised, quantified per-group loss budget. No target default is implicitly accepted by implementation or a passing conservation test.

Compare adaptive acquisition with both fixed 100 ms and fixed context maximum. In controlled scenarios containing quiet periods and subsequent detectable activity, adaptation must reduce scan count versus the minimum and improve retained CPU/discovery versus the maximum, without degrading either coverage metric versus that maximum. Equality is expected where no adaptation trigger is observable. Report scan count and time at each requested interval as offline cost proxies; they are not native CPU measurements. Independently check accepted CPU, never-read CPU, final tails, attribution, conservation and current versus historical memory.

The [offline lifecycle fixture](../../Tests/AgentMonitorCoreTests/WorkloadCoverageTests.swift) is a foundation, not sufficient coverage as written. Extend its production `MonitoringSession` loop beyond the quiet window (at least 180 seconds for the default), with injected pending/negative/point/uncertain/supported attribution, failed listings and resource reads, out-of-scope PIDs, retained helper ancestry and nonzero scan durations. Include a fake provider helper whose child exits quickly, two staggered providers, sparse and dense bursts with varied phases and duration groups (including 50, 200, 500 and 1,000 ms), long-lived workers resuming CPU, idle heartbeats, PID reuse, and every settings/visibility/static/inspection transition. The policy must react to observations it actually obtains, not to future or skipped synthetic events. Independent synthetic ground truth supplies the coverage oracle.

Before implementation, assess whether positive-CPU triggers allow useful relaxation with agents present. Replay an available authorized recording as an explicitly approximate executable/ancestry model and report time-at-interval; it has no session attribution, is quantized to its acquisition grid and cannot reveal workers it originally missed. It cannot establish the true coverage loss or replace the closed-loop oracle. Aggregate-only reports lack ordered per-scan increments and ancestry and cannot satisfy this prerequisite; [ADAPT-01](../../PLAN.md#resource-accounting-priority) tracks data availability. Do not reconstruct timing from aggregate CPU totals or claim this prerequisite passed. Native cost/cadence and closed-panel/App Nap claims require separately authorized measurements with explicit acceptance criteria; this proposal authorizes no live trials.

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

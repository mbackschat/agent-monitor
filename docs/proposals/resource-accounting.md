# Resource accounting across process lifetimes

Status: **approved**, 2026-10-24. First delivery was authorized on that date: fixed-cadence independent acquisition, retained accounting and point-evidence attribution. Optional capabilities remain separately gated.

## Delivery and acceptance

This is the design for CPU-01. Priority and acceptance expectations belong in [CLAUDE.md](../../CLAUDE.md#product-priority) and [resource visibility](../architecture.md#resource-visibility-requirements).

| Capability | Current state |
| --- | --- |
| [Retained-counter foundation](../architecture.md#retained-counter-accounting) and [independent acquisition](../architecture.md#independent-acquisition) | Implemented. |
| One-second accounting units and independent display windows | Implemented, including frozen point-candidate contributions and conservation-preserving report coalescing. |
| Historical ancestry support and accounting acceptance measurements | Open. Implementation does not close the validation gates. |
| [Adaptive acquisition and controls](../architecture.md#adaptive-acquisition) | Implemented, default-off. Calibration, numeric loss-budget acceptance and native validation remain open under [ADAPT-01](../../PLAN.md#resource-accounting-priority). |

The [second-review assessment](../research/cpu-accounting.md#second-review-assessment--2026-10-23) and [first-review assessment](../research/cpu-accounting.md#external-review-assessment--2026-10-23) record evidence, disagreements and unresolved experiments.

## Recommendation

Accounting serves the [product question](../product.md): identify the agents, sessions and processes consuming CPU or memory. Reliable totals must be interpretable in that context, not merely correct counters. Normal collection retains bounded rolling state in memory; it does not enable the separate default-off recorder.

The implemented [resource overview and recent activity contract](../architecture.md#contributor-overview-and-recent-activity) captures the user's subsequent 2026-10-24 requirements for Main contributors, session/worker-family navigation and retained recent statistics across Mac and TUI. It is a separately approved extension; its defaults, historical-memory additions and exploration UI are not part of this proposal's original approved first delivery.

The addendum's capacity revision proposes immutable labels and compact closed units for the initial live recent-history view, deferring retroactive updates to that view. This is an approved scoped delivery choice, not implementation of or removal of the broader evidence-revision contract below. Recording must still retain authoritative revisions under its own contract; compact live summaries are not a substitute for the raw observations needed to support them.

Require independent acquisition at a fixed, selectable cadence, prompt bounded evidence capture, automatic background attribution and retained interval measurements. The smallest useful scope is counter acquisition with retained point-in-time launch-origin labels; interval-supported attribution is a separate capability gated on generation access and adapter semantics. This establishes a measurable baseline before enabling adaptation. The subsequently implemented global adaptation remains default-off; changing its defaults is validation-gated. Scheduler tracing is a separate optional investigation because its conservation tests failed. Deeper inspection may be on demand; identifying responsible agents must not depend on opening a row.

## Required contract

### Acquisition and resolution

| Responsibility | Required behavior |
| --- | --- |
| Counter acquisition | Enumerate all in-scope lifetimes, capture counters and host observations, preserve identity checks and monotonic times, and record scan start/end plus each process's read time. Filters and unresolved ownership cannot exclude discovery. |
| Prompt evidence | Resolve observed parent links to exact lifetime identities. On discovery or a detected execution change, attempt a small allowlisted marker/invocation read inline under an explicit per-scan work budget. Overflow is queued with its discovery time and a late/not-captured status. Marker/invocation reads are explicitly acquisition work, including their latency in achieved-period p99/max. The budget bounds attempts/bytes and checks elapsed work between calls; it cannot interrupt a stalled syscall. A stalled read remains visible as acquisition lag, not a claimed deadline guarantee. |
| Background resolution | Interpret captured evidence through adapters and refresh mutable descriptor/socket/cwd observations on background executors, never inline on the acquisition thread. The later [offline runtime contract](../architecture.md#offline-runtime) excludes provider listings and commands; attribution uses native observations. The explicitly listed native counter and marker/invocation reads remain acquisition work. Publish immutable, versioned resolution results tied to original evidence and contribution identities. |
| Presentation | Refresh independently, show separately qualified point and interval-supported ownership beside measurements and retain historical contributors. Pausing a view does not pause acquisition. Historical-only rows cannot initiate actions. |

#### Thread ownership and timing

Use a dedicated serial acquisition thread with an explicit, reported QoS; do not run synchronous native acquisition or blocking native enrichment on Swift's cooperative executor. Background blocking work and recording use separately bounded execution resources. QoS is not a real-time guarantee or CPU-core assignment. Select QoS and cadence from owned-load measurements, including achieved p50/p99/max periods under saturation, rather than assuming a requested timer interval is achieved.

No overlapping scans or unbounded catch-up work. This design chooses bounded-attempt inline marker capture, not a simultaneous promise that all evidence reads are non-blocking. If measured marker-read tails fail the acceptance bounds, revisit the evidence-thread alternative with measured handoff loss; do not claim the present design passed.

#### Historical ancestry

Structural ancestry is the preferred evidence for churned descendants when verified ancestors provide an unambiguous association. A shared runtime or an unresolved parent does not establish session ownership. Parent ordering uses native monotonic birth observations when available; a wall-clock comparison alone cannot verify an ancestry edge after a clock adjustment. Missing parent birth/evidence remains unknown. Retain observed edges with their times; a later live graph cannot rewrite an earlier path.

### Evidence validity and execution changes

| Evidence class | Cache and validity contract |
| --- | --- |
| Execution-bound candidates | Captured launch markers and invocation/executable observations may be reused as interval-supported facts only within a verified execution epoch and the adapter's stated semantics. Cached point labels remain usable with original timestamps, age and uncertainty; they cannot be promoted merely because they were cached. A path, image UUID, process name or unchanged footprint peak does not prove that no same-path exec occurred. Environment/argument observations are not automatically immutable merely because no exec was detected. |
| Point observations | Registry bindings, descriptors, sockets and cwd carry observation times, refresh policies and unavailable states. A refresh deadline is a cost/freshness policy, not proof of continuous validity between observations. |
| Historical support | An interval-supported fact cites evidence covering the contribution's entire measured interval. Extended coverage requires a documented provider guarantee or verified continuity; otherwise retain point observations and interval uncertainty. |

#### Execution-generation feasibility

A reliable supported-OS execution-generation mechanism remains a feasibility gate for caching across scans. Fresh task-name-port audit tokens detected same-path exec in [20 owned-child trials](../research/cpu-accounting.md#controlled-same-path-exec-follow-up), while retained ports failed after exec. Adopt this as the leading candidate; arbitrary target access, scan-scale cost and generation/counter read-race handling remain gates. Path/name/UUID changes or a falling kernel footprint peak may invalidate a cache but cannot certify stability.

Without a verified generation or continuity guarantee, refresh candidate evidence and expose the unobserved transition risk; do not reuse old markers as certain historical ownership. CPU counter continuity and attribution-epoch continuity are separate questions.

#### Conditions for interval support

An execution-bound claim requires all four conditions:

1. Freshly acquired audit-token observations bracket each counter endpoint and its supporting evidence.
2. Verified lifetime and UID match throughout.
3. Both brackets agree on the same generation.
4. The adapter declares that this claim cannot change within that verified epoch, with retained evidence supporting that declaration.

Fresh acquisition is required at both sides of each bracket; a cached task port is insufficient. Preserve read order/times, reject mismatches or unreadable brackets for interval support, and release acquired rights. Generation uniqueness/exec-change semantics for the target class and observation span must first be validated. A matching generation is necessary for this rule, not sufficient by itself.

Each attribution adapter owns a versioned declaration of the support scope of its claims, including whether its marker is immutable within an exec, what native/provider guarantees that relies on, and tests/source provenance. Hosts supply native observations; the sampler cannot invent provider immutability. No current adapter declares this guarantee, so absence of a validated declaration defaults to point evidence. Mutable registry membership is not made interval-valid by equal generation or equal session values at two endpoints. Derived claims inherit the weakest support of the evidence and ancestry links actually needed for that claim.

For example, observing session A at t=60 and B at t=120 does not establish that A owned 60–120, or that a contribution spanning 70–110 belonged exclusively to either. The transition time is unknown; other unobserved owners are not excluded. Preserve these observations and report uncertain ownership until evidence actually covers the contribution. Even equal endpoint observations do not prove continuity without a supporting contract.

#### Support at each attribution level

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

A single session candidate appears inside that session under a separately labeled **point-evidence candidate** subtotal, showing evidence time/age and uncovered interval when relevant. Keep **interval-supported CPU** distinct; do not silently merge the two into a claimed supported session total. Multiple/contradicted candidates appear once in an uncertain-contributor area with links to alternatives, never counted in several session subtotals.

A contribution with no candidate remains visible as unresolved. Count each contribution once in each population total; nesting provider/runtime/session rows cannot add another copy. CPU units, report-window eligibility and recovered-across-gap exclusions are unchanged by attribution strength.

This is a fallback in evidence strength, not a reason to hide a known single candidate as generic unknown or to call it the statistically most likely owner. A point observation does not prove historical ownership even if it matches at both endpoints. Text, JSONL, TUI and the Mac app expose the distinction consistently.

### CPU conservation and report windows

Retain the last valid cumulative counter and observation ID per exact lifetime and compatible counter generation across temporary read failures. Compare it with the next valid read even when intervening scans failed. Record those gaps; a recovered delta supplies total CPU over its endpoints, not its distribution inside the gap. Decreasing/reset counters, uncertain counter continuity, baseline eviction or a reused PID break the baseline with a reason. Retention is bounded; eviction cannot silently become measured zero. Recovery of final CPU after exit remains unresolved, and [reaped-child counters](../decisions/exited-descendant-cpu.md) remain excluded.

#### First-read recovery

For a first valid counter after failed observations, locate the retained listing immediately preceding that lifetime's verified monotonic birth. A synthetic zero baseline is permitted only when birth follows the acquisition run's initial listing, the counter is known to accumulate from birth, and the lifetime has never already supplied a valid baseline or accepted CPU in the retained accounting domain. Failed BSD/resource/identity reads do not by themselves make a lifetime pre-existing.

Retain listing history and the first-accounted/baseline state long enough to make this decision; if the necessary history is evicted, report baseline unavailable rather than add the full cumulative counter again. PID reuse is a new exact lifetime, not evidence about the old one.

For example, L0=10, birth=10.5, a failed read at L1=11 and a first valid read at L2=12 recover cumulative CPU from a zero at L0. The opening is not L1: that would incorrectly assign pre-L1 CPU to a later window. A process born before the acquisition baseline is ineligible, even if all its early reads failed. This rule supplies an enclosing interval with zero before birth, not a claim about when within the lifetime CPU was spent. Capture start/resume boundaries remain separate exclusions for recording replay.

```swift
enum CPUOpeningReference: Sendable {
    case observation(id: UUID)
    case newbornZero(runID: UUID, listingSequence: UInt64, verifiedBirth: Double)
}
```

#### Unique contributions and window membership

An accepted delta is identified by its opening reference and closing observation ID and counted once. A newborn zero refers to an actual retained pre-birth listing ID, not an invented process observation. Persist the eligibility/birth evidence needed to replay it.

Logical report membership uses scan indices: a report contains closing observations in `(baselineScan, finalScan]`. A delta whose opening observation or synthetic listing reference predates the baseline scan is emitted separately as recovered CPU-seconds with its real interval and excluded from that report's rate. Do not prorate it or attach it to the newest session. A wider analysis window may include it once if its opening reference and closing observation are within that window.

#### Rate denominator and coalescing

For ordinary deltas, the common rate denominator is the enclosing monotonic observation window, from the baseline scan's listing time to the final scan's end. This encloses the constituent read intervals; expose those intervals and scan spread. Consecutive windows can overlap by a scan duration because collection is not atomic. They are not exact nonoverlapping wall-time partitions, and their durations/rates must not be summed.

Conservation is tested on unique accepted deltas, including the distinct newborn-zero opening form. When coalescing reports, merge scan ranges and recompute membership, denominator and deduplicated contributions from their endpoints; do not drop older contributions or add percentages.

Window CPU is explicitly observed CPU per enclosing window, not complete system occupancy. Mark missing/uncertain measurements, baseline exclusions and separately recovered CPU. Session totals ignore display filters. Host occupancy, current-user measurements, known agents, monitor/helpers and unresolved ownership remain distinct populations; differences do not classify load.

### Coverage and memory

#### Native failures

Native outcomes retain the operation, listed PID, verified identity if available, return length/status and immediately captured errno on failure. Distinguish permission denied, lookup unavailable/ESRCH, short reads, identity mismatch, counter unavailable and other failures. Readable out-of-scope users are separate from read failures. ESRCH alone does not prove normal exit or distinguish a reaped worker from every other unavailable state. Counts describe observed failures, not processes never listed. Raw outcomes must be available to recording and controlled probes.

#### Memory observations

Current footprint always carries its observation time and availability. Independently sampled values are observed aggregates with scan spread, not exact simultaneous memory. Kernel footprint peaks remain separate and may reset on exec. Historical process values must not inflate current totals. Delayed ownership cannot safely reconstruct a session peak from today's membership or from a shared ancestor label. A historical session peak is optional until retained per-scan observations and interval-supported attribution can establish it.

#### Retention and pressure

Bound contribution/evidence storage and report queue pressure explicitly. Superseded display snapshots may be coalesced only by the conservation rule above. Lost observations or evidence produce affected-interval gaps; they cannot silently become zero load. A slow resolver cannot stall acquisition or create unbounded memory use.

### Acceptance evidence

Fix allowed coverage/attribution regressions before running comparisons. Use repeated owned workloads, initially at least 100 workers per duration group with randomized start phase, and report uncertainty across runs rather than treating this count as a statistical guarantee. Include nested descendants, same-path exec, session changes, first-read and repeated-read failure injection, quiet and saturated hosts, and delayed/failing fake providers/consumers.

Retain per-worker listing/read timestamps and outcomes so never-listed, listed-but-unreadable, baseline exclusions and final-tail loss can be distinguished. Compare retained CPU with independent `wait4` ledgers by duration group, including total and tail loss. Derive a coverage expectation from actual lifetimes, scan timing and listing-to-read delay; a worker's requested CPU duration is not its wall-clock lifetime.

Report cadence p50/p99/max, monitor/helper CPU, stage costs and bounded memory.

Guard newborn recovery after one/multiple failed reads, pre-existing lifetimes, PID reuse, evicted baselines and capture resume. Verify mixed-strength provider/runtime/session claims and single-candidate subtotals without duplication. The existing four-worker groups and aggregate prototype results do not establish these properties.

## Optional

### Adaptive acquisition

The default-off controller and Mac/TUI controls are implemented under the [adaptive acquisition contract](../architecture.md#adaptive-acquisition). The user's long periods with little relevant activity motivated the feature. The [offline prototype](../research/cpu-accounting.md#adaptive-sampling-offline-prototype--2026-10-27) establishes synthetic scan savings and preserves material coverage counterexamples; native CPU savings remain unmeasured.

#### Defaults and acceptance

| Setting | Current | Proposed, unapproved |
| --- | --- | --- |
| Adaptive acquisition | Off | Enabled |
| Shared minimum | 100 ms | 100 ms |
| Visible/TUI maximum | 100 ms | 250 ms |
| Mac closed multiplier | One | 2.5 (625 ms maximum) |

Before changing them, present a duration-group × scenario × visibility matrix with separate numeric loss budgets for discovered identities and accepted CPU against fixed 100 ms, plus scan-count/native-cost savings. Also compare fixed context maxima. Use common boundaries, report absolute values for zero denominators, and retain per-lifetime losses separately from gains. The user must accept the losses and savings; no numeric budget is implied by accounting conservation or a favorable net total.

Actual idle-agent CPU/churn distributions still need calibration. Existing aggregate summaries cannot reconstruct acquisition timing, ancestry or unseen workers. Any live diagnostic or native cost/cadence/App Nap measurement needs a separate explicit request; another large raw recording is not required if a small authorized aggregate diagnostic can answer the calibration question. The initial prototype thresholds remain provisional, and phase sensitivity prevents selecting a winning threshold from one synthetic schedule.

#### Unreadability policy

Persistent unreadability relaxation remains an optional, unadopted policy. The retained prototype compares the required hold with a disclosed state after at least three identical resource-read failures spanning five seconds, with successful same-user exact-lifetime verification on each scan. That candidate continues ordinary reads and preserves unknown CPU/memory while ceasing to force the minimum. Changed identity, execution/ownership, failure kind or valid counters cancel it; unverified PIDs and whole-listing failures are ineligible. Its modeled scan savings do not prove real failures will remain permanent. Production keeps the conservative hold and existing fatal-listing behavior.

[ADAPT-01](../../PLAN.md#resource-accounting-priority) owns remaining calibration/default acceptance and user-run native checks. The implemented controller's rationale, settings and invariants live in architecture; this section retains only unresolved policy.

### Other optional capabilities

- Bounded scheduler tracing, only after supported capture/decoding, conservation, lifecycle joins and loss detection pass separate gates. The existing `xctrace` experiment is not a reliable backend and is not a requirement for independent native collection.
- Historical per-session observed memory peaks, retaining original per-process scan values and defensible ownership. Exact ancestry anchors alone cannot prove session continuity. Maximum observed process kernel peaks may be retained as separately labeled historical observations, with verified exec boundaries where available.
- Separate per-process sampling rates, only after proving meaningful CPU-window and memory-age semantics against global collection.

## Dependent diagnostic recording

The [recording proposal](diagnostic-recording.md) consumes raw observations, failure records and versioned attribution evidence after this acquisition contract exists. It shares CPU acceptance rules and preserves recorded attribution revisions as authoritative historical labels, while exposing retention/pause gaps. Recording or compression cannot hold acquisition.

## Excluded

Purely on-demand basic attribution, automatic installation of privileged services, changing system security, unrestricted transcripts/environment collection, guessed shared-runtime ownership, arbitrary CPU proration and automatic actions on user workloads. No tracing result establishes an exact memory peak.

## Material feasibility gates

Counter acquisition with point labels is implemented as the first delivery; controlled acceptance measurements remain open. Execution-generation access, bracketing cost/races and adapter evidence-continuity declarations gate interval-supported attribution, not basic point-label visibility. Inline-read latency, fixed cadence/QoS under contention and baseline retention bounds remain unvalidated. Polling can miss lifetimes entirely and cannot recover final counters reliably after reaping. Implementation authorization does not close these gates; retained experiments and explicit uncertainty are required.

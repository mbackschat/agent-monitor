# Resource accounting across process lifetimes

Status: **unapproved**, 2026-10-23. Design for CPU-01; priority and acceptance expectations belong in [CLAUDE.md](../../CLAUDE.md#product-priority) and [resource visibility](../architecture.md#resource-visibility-requirements). Independent acquisition, historical attribution and adaptive sampling are not implemented. The [review assessment](../research/cpu-accounting.md#external-review-assessment--2026-10-23) records evidence, disagreements and unresolved experiments.

## Recommendation

Require independent acquisition at a fixed, selectable cadence, prompt bounded evidence capture, automatic background attribution and retained interval measurements. This establishes a measurable baseline before enabling adaptation. Keep global adaptation as a proposed, validation-gated option, preserving the user's requested direction. Scheduler tracing is a separate optional investigation because its conservation tests failed. Deeper inspection may be on demand; identifying responsible agents must not depend on opening a row.

## Required contract

### Acquisition and resolution

| Responsibility | Required behavior |
| --- | --- |
| Counter acquisition | Enumerate all in-scope lifetimes, capture counters and host observations, preserve identity checks and monotonic times, and record scan start/end plus each process's read time. Filters and unresolved ownership cannot exclude discovery. |
| Prompt evidence | Resolve observed parent links to exact lifetime identities. On discovery or a detected execution change, attempt a small allowlisted marker/invocation read inline under an explicit per-scan work budget. Overflow is queued with its discovery time and a late/not-captured status. A stalled metadata read must remain visible as acquisition lag; a work budget is not a syscall deadline. |
| Background resolution | Interpret captured evidence through adapters, read mutable descriptor/socket/cwd observations, and refresh provider listings automatically. Blocking operations cannot hold the acquisition executor. Publish immutable, versioned resolution results tied to original evidence and contribution identities. |
| Presentation | Refresh independently, show pending/uncertain ownership beside measurements and retain historical contributors. Pausing a view does not pause acquisition. Historical-only rows cannot initiate actions. |

Use a dedicated serial acquisition thread with an explicit, reported QoS; do not run synchronous native acquisition or blocking provider commands on Swift's cooperative executor. Background blocking work and recording use separately bounded execution resources. QoS is not a real-time guarantee or CPU-core assignment. Select QoS and cadence from owned-load measurements, including achieved p50/p99/max periods under saturation, rather than assuming a requested timer interval is achieved. No overlapping scans or unbounded catch-up work.

Structural ancestry is the preferred evidence for churned descendants when verified ancestors provide an unambiguous association. A shared runtime or an unresolved parent does not establish session ownership. Parent ordering uses native monotonic birth observations when available; a wall-clock comparison alone cannot verify an ancestry edge after a clock adjustment. Missing parent birth/evidence remains unknown. Retain observed edges with their times; a later live graph cannot rewrite an earlier path.

### Evidence validity and execution changes

| Evidence class | Cache and validity contract |
| --- | --- |
| Execution-bound candidates | Captured launch markers and invocation/executable observations may be cached only within a verified execution epoch and the adapter's stated semantics. A path, image UUID, process name or unchanged footprint peak does not prove that no same-path exec occurred. Environment/argument observations are not automatically immutable merely because no exec was detected. |
| Point observations | Registry bindings, descriptors, sockets and cwd carry observation times, refresh policies and unavailable states. A refresh deadline is a cost/freshness policy, not proof of continuous validity between observations. |
| Historical support | A resolved contribution cites evidence supporting its entire measured interval. Extended coverage requires a documented provider guarantee or verified continuity; otherwise retain point observations and interval uncertainty. |

A reliable supported-OS execution-generation mechanism remains a feasibility gate for caching across scans. Fresh task-name-port audit tokens detected same-path exec in [20 owned-child trials](../research/cpu-accounting.md#controlled-same-path-exec-follow-up), while retained ports failed after exec. Adopt this as the leading candidate; arbitrary target access, scan-scale cost and generation/counter read-race handling remain gates. Path/name/UUID changes or a falling kernel footprint peak may invalidate a cache but cannot certify stability. Without a verified generation or continuity guarantee, refresh candidate evidence and expose the unobserved transition risk; do not reuse old markers as certain historical ownership. CPU counter continuity and attribution-epoch continuity are separate questions.

For example, observing session A at t=60 and B at t=120 does not establish that A owned 60–120, or that a contribution spanning 70–110 belonged exclusively to either. The transition time is unknown; other unobserved owners are not excluded. Preserve these observations and report uncertain ownership until evidence actually covers the contribution. Even equal endpoint observations do not prove continuity without a supporting contract.

A minimal distinction, using existing `Attribution`:

```swift
struct MeasuredInterval: Sendable {
    let start: Double
    let end: Double
}

enum EvidenceCoverage: Sendable {
    case point(at: Double)
    case supported(interval: MeasuredInterval, basisEvidenceIDs: [UUID])
}

enum ContributionResolution: Sendable {
    case pending
    case supported(Attribution, evidenceIDs: [UUID])
    case uncertain(candidates: [Attribution], evidenceIDs: [UUID])
    case unavailable
}
```

Candidates are not necessarily exhaustive. Evidence and resolution revisions are retained with the contribution; resolved ownership is never recomputed from the current registry/graph. Contradicting evidence may revoke a specific resolution into uncertainty, with the previous revision preserved. Greater specificity is allowed only when the new evidence supports that same interval. Observation time, supported interval and resolution time are distinct.

### CPU conservation and report windows

Retain the last valid cumulative counter and observation ID per exact lifetime and compatible counter generation across temporary read failures. Compare it with the next valid read even when intervening scans failed. Record those gaps; a recovered delta supplies total CPU over its endpoints, not its distribution inside the gap. Decreasing/reset counters, uncertain counter continuity, baseline eviction or a reused PID break the baseline with a reason. Retention is bounded; eviction cannot silently become measured zero. Recovery of final CPU after exit remains unresolved, and [reaped-child counters](../decisions/exited-descendant-cpu.md) remain excluded.

An accepted delta is identified by its two original observation IDs and counted once. Logical report membership uses scan indices: a report contains closing observations in `(baselineScan, finalScan]`. A delta whose opening observation predates the baseline scan is emitted separately as recovered CPU-seconds with its real interval and excluded from that report's rate. Do not prorate it or attach it to the newest session. A wider analysis window may include it once if both endpoints are within that window.

For ordinary deltas, the common rate denominator is the enclosing monotonic observation window, from the baseline scan's listing time to the final scan's end. This encloses the constituent read intervals; expose those intervals and scan spread. Consecutive windows can overlap by a scan duration because collection is not atomic. They are not exact nonoverlapping wall-time partitions, and their durations/rates must not be summed. Conservation is tested on unique accepted deltas. When coalescing reports, merge scan ranges and recompute membership, denominator and deduplicated contributions from their endpoints; do not drop older contributions or add percentages.

Window CPU is explicitly observed CPU per enclosing window, not complete system occupancy. Mark missing/uncertain measurements, baseline exclusions and separately recovered CPU. Session totals ignore display filters. Host occupancy, current-user measurements, known agents, monitor/helpers and unresolved ownership remain distinct populations; differences do not classify load.

### Coverage and memory

Native outcomes retain the operation, listed PID, verified identity if available, return length/status and immediately captured errno on failure. Distinguish permission denied, lookup unavailable/ESRCH, short reads, identity mismatch, counter unavailable and other failures. Readable out-of-scope users are separate from read failures. ESRCH alone does not prove normal exit or distinguish a reaped worker from every other unavailable state. Counts describe observed failures, not processes never listed. Raw outcomes must be available to recording and controlled probes.

Current footprint always carries its observation time and availability. Independently sampled values are observed aggregates with scan spread, not exact simultaneous memory. Kernel footprint peaks remain separate and may reset on exec. Historical process values must not inflate current totals. Delayed ownership cannot safely reconstruct a session peak from today's membership or from a shared ancestor label. A historical session peak is optional until retained per-scan observations and interval-supported attribution can establish it.

Bound contribution/evidence storage and report queue pressure explicitly. Superseded display snapshots may be coalesced only by the conservation rule above. Lost observations or evidence produce affected-interval gaps; they cannot silently become zero load. A slow resolver cannot stall acquisition or create unbounded memory use.

### Acceptance evidence

Fix allowed coverage/attribution regressions before running comparisons. Use repeated owned workloads, initially at least 100 workers per duration group with randomized start phase, and report uncertainty across runs rather than treating this count as a statistical guarantee. Include nested descendants, same-path exec, session changes, read-failure injection, quiet and saturated hosts, and delayed/failing fake providers/consumers.

Retain per-worker listing/read timestamps and outcomes so never-listed, listed-but-unreadable, baseline exclusions and final-tail loss can be distinguished. Compare retained CPU with independent `wait4` ledgers by duration group, including total and tail loss. Derive a coverage expectation from actual lifetimes, scan timing and listing-to-read delay; a worker's requested CPU duration is not its wall-clock lifetime. Report cadence p50/p99/max, monitor/helper CPU, stage costs and bounded memory. The existing four-worker groups and aggregate prototype results do not establish these properties.

## Optional

### Adaptive acquisition

The user's proposed adaptation remains a candidate after fixed-cadence measurements. Adapt the whole collector before considering individual process rates. Accelerate on non-monitor churn, process/host activity and memory changes; slow gradually only with fresh agreeing quiet signals, with separate thresholds/dwell times and periodic fast observations. Missing signals are not quiet. Do not drive adaptation solely from measured agent CPU.

Exclude the exact monitor/helper lifetimes from activation signals, while recording their cost separately. Comparable-window host-minus-monitor occupancy may be a control input after its tick resolution, sampling skew and helper coverage are validated; it is never an attribution result. Unidentified descendants and unrelated host load can still sustain acceleration. Expose rate-change reasons and achieved timing. The highest visible PID is not an established creation counter or missed-process bound.

Require coverage comparisons against fixed fast collection across burst phases and durations, plus idle cost and self-trigger tests. No numeric adaptive thresholds are selected. A fixed fastest **validated** cadence is selectable; back-to-back scans are a bounded experiment, not an always-on default. A time-bounded intensive mode may be offered with measured cost visible. Monitoring overhead is a tradeoff to measure, not automatically a prohibited workload action. Adaptation is not mathematically proven always worse, but may miss a burst before detecting its trigger.

### Other optional capabilities

- Bounded scheduler tracing, only after supported capture/decoding, conservation, lifecycle joins and loss detection pass separate gates. The existing `xctrace` experiment is not a reliable backend and is not a requirement for independent native collection.
- Historical per-session observed memory peaks, retaining original per-process scan values and defensible ownership. Exact ancestry anchors alone cannot prove session continuity. Maximum observed process kernel peaks may be retained as separately labeled historical observations, with verified exec boundaries where available.
- Separate per-process sampling rates, only after proving meaningful CPU-window and memory-age semantics against global collection.

## Dependent diagnostic recording

The [recording proposal](diagnostic-recording.md) consumes raw observations, failure records and versioned attribution evidence after this acquisition contract exists. It shares the acceptance rules and exposes retention/pause gaps. Recording or compression cannot hold acquisition.

## Excluded

Purely on-demand basic attribution, automatic installation of privileged services, changing system security, unrestricted transcripts/environment collection, guessed shared-runtime ownership, arbitrary CPU proration and automatic actions on user workloads. No tracing result establishes an exact memory peak.

## Material feasibility gates

Execution-generation access, evidence continuity, blocking-read latency, fixed cadence/QoS under contention and baseline retention bounds remain unvalidated. Polling can miss lifetimes entirely and cannot recover final counters reliably after reaping. Documentation corrections do not close these gates or authorize implementation; retained experiments and explicit uncertainty are required.

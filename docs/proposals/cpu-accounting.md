# Count newborn CPU and show host load

Status: **unapproved proposal**, 2026-10-16, narrowed after external review the same day. It does not authorize implementation or change current behavior, which remains defined by the [architecture](../architecture.md) and [usage guide](../usage.md). Evidence and probe limits are in [CPU accounting coverage](../research/cpu-accounting.md), including the [review follow-up](../research/cpu-accounting.md#review-follow-up--2026-10-16). The [agent-friendly CLI proposal](agent-friendly-cli.md) waits on this decision and should reuse its accounting.

Today CPU is reported only for a lifetime observed in two consecutive samples. A process born between samples therefore has no CPU value for the interval it was born in, even though all of its CPU fell inside that interval. Agent work often spawns short-lived children such as compilers and test runners; how much CPU this omission hides on real workloads is unmeasured. Separately, no view shows how busy the whole machine is beside the processes it measures.

Contract after this change: **a readable current-user lifetime has a CPU value for every interval in which it was observed, including the interval it was born in. CPU of lifetimes never observed, or consumed after their last observation, remains uncounted and is not implied by any total. Host occupancy is reported beside measured process CPU and is never decomposed into causes.**

## Required

### R1 — First-interval CPU for newborn lifetimes

All times below are Mach absolute time, which is monotonic, shared by all processes and excludes sleep; the reader already timestamps samples with it.

- `L(k)`: listing time of snapshot `k`, recorded immediately before `proc_listpids`. New per-snapshot field.
- `t(p,k)`: sample time of lifetime `p` in snapshot `k`, as today.
- `b(p)`: birth time from `ri_proc_start_abstime`.
- `C(p,k)`: cumulative user+system CPU, as today.

| Case | CPU of `p` in snapshot `k` |
| --- | --- |
| Observed in `k−1` | `100 × (C(p,k) − C(p,k−1)) / (t(p,k) − t(p,k−1))`, unchanged. |
| First observed in `k` and `b(p) > L(k−1)` | `100 × C(p,k) / (t(p,k) − L(k−1))`: zero before birth, averaged over the measured interval since the previous listing. |
| First observed in `k` and `b(p) ≤ L(k−1)` | No value. It existed at the previous listing but was not observed, for example after a read failure. |
| First snapshot | No value. |

A newborn's window starts at the previous listing, while an existing lifetime's window starts at its own previous sample within `[L(k−1), end of scan k−1]`. A newborn's denominator can therefore exceed a comparable existing lifetime's by at most the previous scan's duration, slightly understating it; the snapshot records that duration so the skew is stated, not hidden. `exec` keeps the lifetime's start time and cumulative CPU, so it continues as an observed lifetime.

### R2 — Host and measured context

Each snapshot carries host occupancy over the interval between consecutive listings, read from `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` summed over logical CPUs. `host_statistics` is not used, because third-party callers receive cached counters at short intervals. Occupancy is `(user + system + nice ticks) / all ticks × logical CPUs × 100`: unweighted logical-CPU occupancy in the existing one-core unit, not equivalent computing capacity on performance/efficiency hardware.

Host occupancy is unavailable for an interval when the call fails, the total tick delta is zero, any counter decreases (including 32-bit wrap) or the logical CPU count changes. It is also unavailable on the first snapshot. Unavailable is shown as “No data”, never as 0%.

```swift
public struct CPUAccounting: Equatable, Sendable {
    /// Unweighted logical-CPU occupancy between consecutive listings; nil when unavailable.
    public let hostBusyPercent: Double?
    public let logicalCPUCount: Int
    /// Sum over listed current-user lifetimes with a CPU value, including R1 newborns.
    /// Excludes the monitor's own process, which is never listed.
    public let measuredUserPercent: Double
    /// Listed current-user lifetimes without a CPU value; nonzero means the sum is partial.
    public let unmeasuredLifetimeCount: Int
    /// Duration of the previous scan, the bound on R1's newborn window skew.
    public let previousScanSeconds: Double?
}
```

The two figures are shown side by side. Their difference is not presented, because missed current-user work, scan skew and tick resolution enter it alongside system and other-user load.

### Surfaces

| Surface | Change |
| --- | --- |
| Process rows, sorting, thresholds | R1 values; departed processes still have no rows. |
| Text report, TUI and native panel headers; native status menu and accessibility text | `CPU: host 211% of 800% · your measured processes 169% (3 without data)` |
| JSONL | Schema version 3 adds a report-level `cpuAccounting` object; findings keep their flat shape. |
| History, native status icon, session-group totals | Unchanged. |

Illustrative fragment of a version 3 report; the existing required envelope fields are omitted here:

```json
{"schemaVersion":3,"cpuAccounting":{"hostBusyPercent":210.9,"logicalCPUCount":8,"measuredUserPercent":169.1,"unmeasuredLifetimeCount":3,"previousScanSeconds":0.041}}
```

## Decisions for review

1. **Normalize newborn CPU by the measured interval since the previous listing.** Normalizing by process age would rank brief processes higher than their contribution to the interval; normalizing by the configured wait would overstate newborns whenever collection runs late. Values stay comparable within the stated scan skew; a sufficiently parallel burst can still legitimately outrank sustained work.
2. **Limit visible changes to R1 values in existing rows and one host-context line.** History, the icon and session totals keep their documented contracts, which follow sampled findings and the all-agent summary.
3. **Bump JSONL to version 3.** The version 2 schema sets `additionalProperties: false` at report level, so the new object would break strict validators. R1 alone stays valid under version 2, because unavailable CPU is omitted rather than emitted as null.

## Deferred: CPU of exited descendants

Recovering work that ends between samples from `ri_child_user_time`/`ri_child_system_time` is deferred. [Review evidence](../research/cpu-accounting.md#review-follow-up--2026-10-16) shows that automatic reaping (`SIGCHLD` ignored) doubles these counters, and that crediting only direct children recounts observed CPU when an intermediate process collects a grandchild and exits. Moving credit to ancestors alone does not fix this.

Reconsider only with both of the following:
- validated counter semantics, including automatic reaping, across supported OS builds;
- a conservation model covering scan ordering, temporary read failures, baseline exclusions (CPU consumed before monitoring began), reparenting and ancestor departure.

Any recovered CPU must stay distinct from live measurements and be labeled by when it was accounted, not when it ran. A narrower alternative to investigate first is reading the final counters of zombies already identified by the reader.

## Excluded alternatives

| Alternative | Reason |
| --- | --- |
| Shorter sampling intervals | Raises collection cost and still misses lifetimes shorter than the interval. |
| kqueue `EVFILT_PROC` exit tracking | Requires registering every lifetime and racing each exit to read final counters; it belongs with the deferred exited-work decision, not R1 or R2. |
| Endpoint Security or a privileged helper | Needs entitlement or root; out of the same-user scope. |
| Per-process attribution of other users' or system load | Not readable without privilege; R2 shows host occupancy instead. |
| Performance/efficiency core weighting | Changes the one-core unit used everywhere. |
| CPU diagnosis command | Separate [agent-friendly CLI proposal](agent-friendly-cli.md), revised after this decision. |

## Risks and acceptance

- Lifetimes born and exited between listings, and every lifetime's final partial interval, stay uncounted; the contract states this instead of implying completeness.
- A newborn missed at its first listing because of a read failure gets no value later, which is preferable to a value spanning an unknown window.
- Sleep/wake behavior of birth times, sample times and host ticks together is [unresolved](../research/cpu-accounting.md#unresolved-empirical-questions); host occupancy must become unavailable rather than wrong when counters are inconsistent.

Acceptance requires deterministic `Monitor` tests with synthetic samples for each R1 case: newborn after the previous listing, birth before it but unobserved, first snapshot, `exec` continuity and PID reuse. Host-counter tests with a fake source must cover failure, zero delta, decrease, wrap and CPU-count change. A reader integration test with disposable owned processes that burn fixed CPU must report a newborn's first interval within a stated tolerance. JSONL version 3 schema tests, updated help/usage/architecture and a regenerated README preview complete the change.

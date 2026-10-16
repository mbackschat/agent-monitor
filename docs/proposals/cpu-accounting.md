# Count CPU that sampling currently misses

Status: **unapproved proposal**, 2026-10-16. It does not authorize implementation or change current behavior, which remains defined by the [architecture](../architecture.md) and [usage guide](../usage.md). Evidence and probe limits are in [CPU accounting coverage](../research/cpu-accounting.md). The [agent-friendly CLI proposal](agent-friendly-cli.md) waits on this decision and should reuse its accounting.

Agent load arrives largely through short-lived children such as compilers and test runners. Today CPU is counted only for a lifetime seen in two consecutive samples, so a newborn's first interval, every process's final partial interval and anything shorter than one interval are missing from rows, totals, history and the icon. At the TUI/native five-second and closed-panel fifteen-second cadences this systematically under-reports agent work; the magnitude on real workloads is unmeasured. Separately, no view can say whether the observed load is most of the machine's load or a small part of it.

The invariant this proposal establishes: **every CPU-second a readable current-user lifetime consumes in an interval is counted once in that interval's totals, or in a later interval when the kernel only reports it after reaping; load outside that population is quantified, not silently absent.**

## Required

### R1 — First-interval CPU for newborn lifetimes

When a lifetime's kernel start time (`ri_proc_start_abstime`, the sampling clock) follows the previous snapshot's sample time, its CPU is its entire cumulative CPU divided by the report interval. The existing value contract therefore stays true: “CPU is averaged between snapshots”, counting zero before the process started. A first-ever snapshot, or a lifetime started before the previous snapshot but not observed then, still has no CPU value.

### R2 — CPU of exited descendants

Each live lifetime contributes the growth of its reaped-children counters, minus CPU already counted for those children while they were observed:

```text
exited(interval) = max(0, Δ(ri_child_user_time + ri_child_system_time) − credit)
credit          += last observed (self + child) CPU of each direct child that departed
credit          −= the amount consumed above
```

Credit carries forward, because the kernel adds a child's time only once it is reaped, and is dropped when the parent lifetime departs. Exited CPU belongs to the reaping lifetime's resolved attribution. It is never added to that process's own CPU value, because rows are action targets and their CPU must remain the process's own.

### R3 — Host and population context

Each snapshot carries the host's busy share over the same interval (from `HOST_CPU_LOAD_INFO` ticks, multiplied by the logical CPU count so 100% remains one occupied core) and current-user totals. The monitor's own process counts toward the current-user total but is never listed. Host load minus current-user load is presented as unattributed load: system services, other users and anything the current user cannot read. It is never presented as a specific cause.

```swift
public struct CPUAccounting: Equatable, Sendable {
    /// Busy share of all logical CPUs over the report interval; nil when the host counter failed.
    public let hostBusyPercent: Double?
    public let logicalCPUCount: Int
    /// Measured current-user lifetimes, including newborn first intervals (R1).
    public let currentUserPercent: Double
    /// Reaped current-user descendants not observed while running (R2).
    public let exitedDescendantPercent: Double
}

// AgentLoadSummary gains the agent-associated share of R2:
public let exitedDescendantCPUPercent: Double
```

### Surfaces

| Surface | Change |
| --- | --- |
| Process rows, sorting, thresholds | R1 values only; no exited CPU, no rows for departed processes. |
| Text report header | `CPU: host 211% of 800% · your processes 181% incl. 12% exited` |
| TUI header and native panel header, status menu and accessibility text | Same line plus `agents 42% incl. 3% exited` from the latest all-agent summary these views already collect at most every 15 seconds. |
| History CPU metric | Agent live CPU plus agent exited-descendant CPU. |
| JSONL | Schema version 3 adds a report-level `cpuAccounting` object; findings keep their flat shape. Text and JSONL still do not collect the all-agent summary. |
| Native status icon and session-group totals | Unchanged; they keep following displayed findings. |

```json
{"schemaVersion":3,"cpuAccounting":{"hostBusyPercent":210.9,"logicalCPUCount":8,"currentUserPercent":169.1,"exitedDescendantPercent":12.4},"findings":[]}
```

## Decisions for review

1. **Normalize newborn CPU by the report interval, not by process age.** Interval share keeps the help text true, keeps rows comparable and additive, and keeps a 0.2-second burst from outranking sustained load. Age-normalized rates would read higher for brief processes but break all three.
2. **Show exited CPU only in totals, context lines, history and JSONL.** Rows must stay attributable to one actionable process; the icon and session totals keep their documented “displayed findings” contracts. Adding exited CPU to session-group headers is the one plausible extension and is excluded until requested.
3. **Bump JSONL to version 3.** The v2 schema sets `additionalProperties: false`, so an added field breaks strict validators; newborn CPU values also change from null to numbers.
4. **Include exited agent CPU in history.** History exists to show agent load over time; leaving reaped work out preserves today's under-reporting where it matters most.

## Excluded and rejected alternatives

| Alternative | Reason |
| --- | --- |
| Shorter sampling intervals | Raises collection cost and still misses lifetimes shorter than the interval. |
| kqueue `EVFILT_PROC` exit tracking | Requires registering every lifetime and racing its exit to read counters; reaped-children counters already deliver the totals. |
| Endpoint Security or a privileged helper | Needs entitlement or root; out of the same-user scope. |
| Per-process attribution of other users' or system load | Not readable without privilege; R3 quantifies it instead. |
| Performance/efficiency core weighting | Changes the one-core unit used everywhere; not needed to close the gap. |
| CPU diagnosis command | Separate [agent-friendly CLI proposal](agent-friendly-cli.md), revised after this decision. |

## Risks and acceptance

- **Double counting** is the main correctness risk. A child reparented between its last sample and exit is reaped elsewhere; its credit then stays with the old parent and can suppress that parent's later exited CPU, never inflate it. Credit must key on exact lifetimes, so PID reuse cannot transfer it.
- **Unrecoverable work remains**: orphans reaped by `launchd`, descendants whose reaping ancestor also exits before the next sample, and other users' processes. These fall into unattributed host load.
- **A shared runtime as reaper** contributes to agent totals but cannot divide exited CPU between its logical sessions.
- **Clock and resolution**: start times and samples share the Mach clock; behavior across sleep/wake and host-tick resolution at short intervals are [unresolved](../research/cpu-accounting.md#unresolved-empirical-questions).

Acceptance requires deterministic `Monitor` tests with synthetic samples for: newborn first interval, baseline-only nil, observed-then-reaped without double counting, delayed reaping carried through credit, reparenting, PID reuse and parent departure. A reader integration test with disposable owned processes that burn fixed CPU must recover their exited CPU within a stated tolerance. JSONL v3 schema tests, updated help/usage/architecture, and a regenerated README preview complete the change. Live agent workload magnitude remains a measurement to report, not a gate.

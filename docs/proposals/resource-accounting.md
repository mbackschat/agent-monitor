# Resource accounting across process lifetimes

Status: **unapproved**, 2026-10-23. Design for closing the remaining CPU-01 accounting gaps; the user's priority is recorded in [CLAUDE.md](../../CLAUDE.md#product-priority) and [the resource requirements](../architecture.md#resource-visibility-requirements). This proposal does not claim that a tracing backend or independent collector is implemented.

## Recommendation

Use frequent native observations for everyday visibility and bounded scheduler tracing for CPU investigations that must capture short-lived workers. Keep resource acquisition independent of presentation and provider queries. The [controlled probes](../research/cpu-accounting.md#controlled-exit-and-scheduler-probes--2026-10-23) show why both capabilities matter: repeated metadata work limits native cadence, every tested polling configuration missed the 10 ms group, and System Trace matched one exit ledger but overcounted a second trial by 146%, requiring explicit event/lifetime completeness validation. Increasing the live timer alone is an interim improvement.

## Required contract

- **Conserved intervals:** reports aggregate accepted CPU-seconds over one stated monotonic interval, including contributors that disappear before publication. Session/process percentages use that common denominator. Retain lifetime and attribution evidence with each contribution; a later PID reuse, exec or provider-session change cannot relabel earlier work. Unknown transition boundaries remain uncertain.
- **Independent observation:** display refresh, slow rendering and provider queries cannot suspend native counter acquisition. Record achieved scan timing, lag and any discarded observations explicitly. Requested cadence is never presented as a guaranteed observation period. Bound storage without silently losing CPU or pretending an overrun is zero load.
- **Process and session evidence:** preserve exact PID/start identities, observed ancestry and adapter-owned metadata while they exist. Session totals ignore display filters. Unresolved work remains inspectable, and host occupancy, measured current-user CPU, known agent CPU and unknown ownership remain separate populations. A host remainder is not a classification.
- **Memory:** show latest physical footprint only for current observations; retain timestamped historical values separately. Observed simultaneous footprint peaks are distinct from current memory and from sums of individual process peaks. The implemented per-process kernel footprint peak can reset on exec and provides neither a report-window timestamp nor a concurrent session peak. Missing measurements are unknown, not zero; exited workers contribute historical CPU without inflating current memory.
- **Historical inspection:** TUI, text/JSONL and the Mac app expose contributors from the report interval even if absent at its end. Historical-only rows cannot initiate process/session actions. Pausing freezes the displayed interval and evidence while acquisition continues. Resume does not replay an unbounded queue of old views.
- **Bounded tracing:** an explicitly invoked scheduler investigation reports its capture interval, process coverage, unavailable attribution and detected trace loss. It must reject unsupported decoding or incomplete capture rather than silently substituting polling. Join process lifecycle evidence with native attribution; scheduler CPU alone cannot identify a coding-agent session. Tracing must not depend on holding user processes stopped or changing their reaping behavior.

A minimal measurement distinction, using existing `ProcessIdentity` and `Attribution` types:

```swift
enum ObservedPresence: Sendable { case current, noLongerObserved }

struct FootprintObservation: Sendable {
    let bytes: UInt64
    let monotonicSeconds: Double
}

struct IntervalContribution: Sendable {
    let process: ProcessIdentity
    let cpuSeconds: Double?
    let presence: ObservedPresence
    let latestFootprint: FootprintObservation?
    let attribution: Attribution
    let attributionObservedAt: Double
}
```

`noLongerObserved` does not prove exit. `latestFootprint` on such a contributor is historical only. The containing report supplies the interval boundaries, known coverage failures and attribution qualifications; unavailable CPU must not be inferred as zero. This is a proposed contract, not a new wire schema.

## Optional

- A lighter scheduler-only recording configuration, if measured conservation and lifecycle evidence satisfy independent per-duration CPU oracles, including the failed trace case. The stock System Trace template's temporary storage and finalization cost are unsuitable for continuous use.
- A user-selected slower collection interval or static menu icon. These choices must expose their coverage consequences and must not change the meaning of totals.

## Excluded

Automatic installation of a privileged service, Endpoint Security entitlement provisioning, disabling system security, unrestricted transcript/environment collection, assigning shared-runtime CPU to an arbitrary session, and automatic changes to user workloads are outside this design. Hardware instruction tracing is not required; the M1 test machine cannot capture Apple's M4 Processor Trace.

## Material feasibility risks

- System Trace matched the first controlled ledger but failed the second; the current prototype does not provide reliable conservation or prove lossless event delivery, arbitrary lifetime reconstruction, early-attachment completeness or exact agent-session joins. These are acceptance gates, not bookkeeping details.
- Private ktrace interfaces have ownership/privilege constraints; a supported distribution path and bounded capture lifecycle are unresolved. The tested `xctrace` path requires Xcode and may require host permissions unavailable to a packaged app.
- Sampling cannot establish how many processes ran entirely between observations. An honest native result may remain partial even with no recorded read errors. CPU conservation must be checked per worker-duration group against independent ledgers, not only as an aggregate dominated by long workers.
- No CPU trace result establishes exact memory peaks. Accurate lifetime CPU and useful current/observed-peak memory need separate validation.

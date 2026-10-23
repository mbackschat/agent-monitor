# Resource accounting across process lifetimes

Status: **unapproved**, 2026-10-23. Design for closing the remaining CPU-01 accounting gaps; the user's priority is recorded in [CLAUDE.md](../../CLAUDE.md#product-priority) and [the resource requirements](../architecture.md#resource-visibility-requirements). This proposal does not claim that a tracing backend or independent collector is implemented.

## Recommendation

Separate frequent native acquisition, automatic background attribution and presentation. Add adaptive acquisition that prioritizes coverage, with a fixed fastest supported mode for investigations. Only deeper inspection should be on demand; identifying responsible agents must not depend on opening a row. Bounded scheduler tracing remains a separate candidate for CPU that polling cannot capture, subject to its conservation gates. The [controlled probes](../research/cpu-accounting.md#controlled-exit-and-scheduler-probes--2026-10-23) show why both capabilities matter: repeated metadata work limits native cadence, every tested polling configuration missed the 10 ms group, and System Trace matched one exit ledger but overcounted a second trial by 146%, requiring explicit event/lifetime completeness validation. Increasing the live timer alone is an interim improvement. The [follow-up analysis](../research/cpu-accounting.md#independent-acquisition-and-adaptation--2026-10-23) distinguishes evidence for this split from the untested adaptive policy.

## Required contract

- **Conserved intervals:** reports aggregate accepted CPU-seconds over one stated monotonic interval, including contributors that disappear before publication. Session/process percentages use that common denominator. Retain lifetime and attribution evidence with each contribution; a later PID reuse, exec or provider-session change cannot relabel earlier work. Unknown transition boundaries remain uncertain.
- **Independent observation:** acquisition, evidence capture/resolution and presentation have independent progress. Their responsibilities and overload behavior are specified below; UI pause and slow provider queries cannot suspend native acquisition.
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

enum ContributionResolution: Sendable {
    case pending
    case observed(Attribution, atMonotonicSeconds: Double)
    case unavailable
}

struct IntervalContribution: Sendable {
    let process: ProcessIdentity
    let cpuSeconds: Double?
    let observedFrom: Double
    let observedThrough: Double
    let presence: ObservedPresence
    let latestFootprint: FootprintObservation?
    let resolution: ContributionResolution
}
```

`noLongerObserved` does not prove exit. `latestFootprint` on such a contributor is historical only. The containing report supplies the interval boundaries, known coverage failures and attribution qualifications; unavailable CPU must not be inferred as zero. Resolution may improve without changing measured CPU. `pending` and `unavailable` must remain distinguishable from a resolved nonagent; the existing attribution value retains unknown/ambiguous claims. This is a proposed contract, not a new wire schema.

## Acquisition and resolution

| Responsibility | Required behavior |
| --- | --- |
| Fast acquisition | Capture monotonic resource counters, current/kernel-peak footprint, exact same-user lifetime identity and observed parent/executable context. Preserve identity verification around native reads. Discover new lifetimes independently of attribution or visible rows; filters and unresolved ownership never exclude a process from discovery. |
| Prompt evidence capture | Give new lifetimes and observed executable/ancestry changes priority for bounded, allowlisted attribution observations while the process exists. Capture raw evidence with identity and observation time; adapters continue to own recognition and interpretation. This work progresses separately from counter scans. Failure or late capture stays explicit. |
| Background resolution | Automatically interpret captured evidence, resolve provider sessions and refresh bindings. Cache by lifetime and evidence validity, not PID alone. Provider calls, descriptor/socket inspection and other expensive resolution cannot hold the acquisition path. Only requested deeper inspection waits for user interest. |
| Presentation | Consume retained interval measurements at an independent refresh rate. Show measured CPU with ownership pending/unavailable until evidence supports attribution. Report interval, achieved collection timing and coverage failures accompany the result in every presentation. |

Deferring interpretation is safe only for evidence already retained. A worker that exits before capture may never be attributable; an exit event does not guarantee readable final counters. Captured parent PID alone does not establish the parent's exact lifetime. Preserve uncertainty when parent identity, exec boundaries or shared-runtime/session transitions were not observed. Later evidence must not retroactively assign an entire earlier interval to whichever session is current now. Refresh long-lived bindings as well as new processes: unchanged PID/executable does not prove unchanged session ownership.

Retain CPU contributions and the evidence needed to interpret them after a process disappears. Bound raw samples, pending evidence and resolved history explicitly. Superseded presentation snapshots may be coalesced; CPU contributions or distinct attribution evidence may not be silently replaced by the newest item. Report affected intervals and evidence loss when capacity is exceeded. A slow resolver must neither block collection nor cause unbounded memory growth. An overload is a coverage failure, not permission to report zero or claim a complete total.

Use actual monotonic observation boundaries for CPU deltas. Report windows must account for a delta's covered interval; changing cadence cannot assign a whole cross-boundary delta to the newest report or imply exact proportional allocation without evidence. Memory retains sample times and age; values measured at different times cannot be advertised as an exact simultaneous snapshot. These constraints favor one collection cadence initially.

## Adaptive acquisition

Adapt the whole native acquisition cycle first. Discovery and host observations remain independent of resolver/display cadence; no process becomes exempt because it was previously idle, unresolved or outside agent scope. Keep the slowest allowed cycle bounded and make fixed fastest supported collection available. Numeric intervals, thresholds and dwell times remain undecided until measured; the current 100 ms requested wait is neither a proposed adaptive bound nor a demonstrated safe floor.

| Condition | Required policy |
| --- | --- |
| Collector startup, recovery after interruption or missing/stale activity signals | Begin or remain in fast collection; absence of observations is not evidence of quiet. |
| New/disappearing lifetimes, rising process/host CPU, or observed memory growth/peak change | Accelerate promptly and hold the faster rate long enough to observe the burst. Unresolved processes participate in these signals. |
| Sustained host-versus-observed CPU discrepancy | Treat comparable-window divergence as an investigation signal, never as agent attribution. Account for different populations, counter resolution and scan skew; divergence alone need not disappear at the fastest rate. |
| Sustained quiet | Slow gradually only when fresh host, churn and resource observations agree. Use separate acceleration/deceleration conditions and a quiet dwell period to prevent oscillation. Periodic fast observations check for activity missed at the slower cadence; they cannot recover a burst already missed. |
| Scan overruns or resolver backlog | Expose achieved cadence, scan duration, lag and gaps. Avoid overlapping scans or catch-up storms. Resolver pressure cannot silently reduce collection coverage; an unattainable target remains visible. |

The policy must expose its mode, requested and achieved cadence and reason for rate changes. Host busy time includes the monitor; report monitor cost separately and test whether its own collection work sustains acceleration. Do not subtract unlike measurement windows or label the remainder as agent load. CPU quietness alone cannot justify ignoring memory changes.

Acceptance requires comparison with fixed fast collection and independent owned-worker CPU ledgers across duration groups, abrupt quiet-to-busy transitions, bursts between scans, memory-only activity and sustained churn. Compare observation/attribution coverage, transition latency, achieved cadence, monitor CPU and bounded memory. Inject slow/failing resolution, PID reuse, exec/session changes and capacity exhaustion; retained attribution must not drift and acquisition must keep progressing. State the acceptable coverage regression before evaluating results; lower overhead cannot compensate for losing a short-worker group. Adaptive collection remains unvalidated until these checks pass, and even passing them does not make polling lossless.

## Dependent diagnostic recording

The [bounded recording proposal](diagnostic-recording.md) consumes independent measurements and captured/resolved context after this acquisition contract exists. It specifies opt-in runtime start/pause/resume, independently readable 50 MB chunks, lossless compression and a configurable 250 MB compressed store. Recording and compression must not block acquisition; saved data preserves attribution timing, pauses and coverage gaps.

## Optional

- A lighter scheduler-only recording configuration, if measured conservation and lifecycle evidence satisfy independent per-duration CPU oracles, including the failed trace case. The stock System Trace template's temporary storage and finalization cost are unsuitable for continuous use.
- Separate rates for individual processes, only if they improve measured coverage and preserve meaningful CPU windows and memory age. Prior low CPU is insufficient evidence that a process can safely be sampled less often.
- A user-selected slower collection interval or static menu icon. These choices must expose their coverage consequences and must not change the meaning of totals.

## Excluded

Purely on-demand agent attribution, automatic workload suspension to preserve evidence, arbitrary CPU attribution across unobserved transitions, automatic installation of a privileged service, Endpoint Security entitlement provisioning, disabling system security, unrestricted transcript/environment collection, assigning shared-runtime CPU to an arbitrary session, and automatic changes to user workloads are outside this design. Hardware instruction tracing is not required; the M1 test machine cannot capture Apple's M4 Processor Trace.

## Material feasibility risks

- System Trace matched the first controlled ledger but failed the second; the current prototype does not provide reliable conservation or prove lossless event delivery, arbitrary lifetime reconstruction, early-attachment completeness or exact agent-session joins. These are acceptance gates, not bookkeeping details.
- Private ktrace interfaces have ownership/privilege constraints; a supported distribution path and bounded capture lifecycle are unresolved. The tested `xctrace` path requires Xcode and may require host permissions unavailable to a packaged app.
- Sampling cannot establish how many processes ran entirely between observations. An honest native result may remain partial even with no recorded read errors. CPU conservation must be checked per worker-duration group against independent ledgers, not only as an aggregate dominated by long workers.
- Prompt evidence capture can still lose a race with exit or exec. Independent workers share CPU/memory bandwidth, so asynchronous separation alone does not establish sampling deadlines. Adaptive polling can miss both a burst and its trigger; global host activity can instead keep it permanently fast.
- No CPU trace result establishes exact memory peaks. Accurate lifetime CPU and useful current/observed-peak memory need separate validation.

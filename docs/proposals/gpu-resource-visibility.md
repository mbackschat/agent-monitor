# GPU resource visibility

Status: **unapproved**, 2026-10-29. The user authorized feasibility research and this proposal, not production collection or UI support. Implementation requires acceptance of this design and resolution of its feasibility gates.

## Purpose and boundary

Extend the [resource responsibility question](../product.md) to GPU work: identify the observed process and, when verified, its agent/session and workload directory. Host activity provides context but cannot substitute for contributor accountability. The [source review and M1 probe](../research/gpu-accounting.md) demonstrate unprivileged registry access while leaving telemetry stability, counter continuity and metric semantics unresolved.

The recommended candidate is direct, read-only IOKit registry access with explicit capability checks. Public traversal APIs do not make `AppUsage` or `PerformanceStatistics` a documented stable telemetry contract. Adopting those driver-defined properties requires an explicit compatibility-policy decision; this proposal does not override the [rejection of privileged and unstable tracing dependencies](../decisions/privileged-resource-tracing.md). If that dependency is unacceptable, keep GPU support unavailable until a supported route is established.

## Required

### Metric meaning and availability

Keep device activity and process accounting separate. Device activity is the driver's reported device percentage, with its source and freshness disclosed; it is not the sum of contributor readings. Process accounting may expose **observed driver-reported GPU time** in seconds only after its unit and interpretation are validated. A rate, if admitted, is GPU-time seconds per measured wall second, not percentage of total GPU capacity. Do not divide by GPU-core count, clamp a process rate to 100%, infer capacity share or subtract it from the host graph.

The first observation establishes a baseline; pre-observation counters are not current-interval work or a known process-lifetime total. Zero requires a supported, valid interval. Missing properties, failed identity reads, malformed numbers, baseline/reset intervals, ambiguous record continuity and lost observations remain unavailable or partial with an explicit cause. A missing GPU client does not prove that its process is idle. Known exclusions can be counted, but they cannot quantify never-observed work.

### Identity, continuity and attribution

Bind observations to the device/client registry identity and a verified process lifetime, never PID alone. A creator PID plus two equal process-birth reads is insufficient evidence against a stale creator reference or shared-client ownership; establish the relationship and its lifecycle limits before admitting contributions. The [source follow-up](../research/gpu-accounting.md#creator-identity-and-aggregate-continuity-follow-up--2026-10-29) shows that the generic creator string can change when a shared client is opened again, without establishing that AGX shares those clients. Validate numeric type, units and checked arithmetic. Counter decreases, ownership changes, unsupported schemas and uncertain accounting continuity cannot produce a rate.

Do not match repeated API records by array position or assume equal array length and increasing values prove continuity. Stable record IDs are unnecessary if a validated, continuous cumulative client total preserves distinct additive charges through record changes; ordinary record permutation does not invalidate that total. Establish retained retired work, insertion/reset semantics and comparable snapshots before admitting such aggregation. Single-record clients require the same accounting justification. Keep client baselines separate so a departing client's counter cannot cancel another's increment. Missing final increments and never-observed clients remain coverage gaps; retain previously validated contributions when clients disappear, without treating their last rate as current activity.

Apply existing exact-lifetime attribution to validated intervals. Group only compatible observations over the same accounting window; preserve unassigned/shared work and attribution uncertainty. Do not infer agent/session ownership from CWD, memory size, host load or temporal coincidence. Display filters cannot redefine measured totals, and later ownership evidence cannot silently reassign earlier work. Partial session observations must remain visibly partial rather than advertise complete GPU load.

### Runtime and presentation contract

Collection remains local, unprivileged and offline, with bounded in-memory state and no automatic process-data recording. Establish finite retention/capacity bounds, acquisition timing and failure behavior before implementation acceptance; GPU collection must not stall CPU/memory acquisition. Unavailable capability is a normal result, not a reason to invoke privileged helpers or silently replace measurements with estimates.

Mac and TUI consume the same metric and coverage definitions. Preserve the [accepted contributor ledger](../architecture.md#constrained-overview-presentation), keeping agent/session, executable and CWD visible when comparing GPU work. Expose units and material gaps beside the relevant values; detailed evidence belongs in inspection/help. Device and contributor charts must not imply a shared percentage denominator. Concrete controls and chart scales require a separate review after metric semantics are settled; this proposal authorizes no alternative overview layout.

## Optional

Graphics-tagged memory may be considered after separate access and accounting validation. Label the particular ledger balance rather than “GPU memory” or “VRAM”; never add it to existing process footprint or treat the Metal recommended working set as dedicated capacity. Frequency, temperature and power are outside the initial resource-accountability scope.

## Excluded

- Production collection or UI changes under the current research authorization.
- Root helpers, private-framework bindings, private entitlements, security changes or compulsory workload instrumentation/relaunch.
- Fabricated process shares, whole-process memory relabelled as GPU memory, host-minus-agent remainder arithmetic and claims of complete lifetime/exit accounting.
- Cloud/remote GPU monitoring, Neural Engine accounting, cross-platform backends and new process actions.
- New workload generators, saturation/churn experiments or live-workload manipulation without separate explicit authorization.

## Feasibility gates and recommendation

| Gate | Evidence needed before implementation acceptance |
| --- | --- |
| Interface policy | Accept or reject the narrowly scoped dependency on driver-defined GPU properties. Public IOKit access alone does not settle this decision. Recommend evaluating this candidate while retaining the current no-root/no-private-framework boundary. |
| Metric semantics | Establish units, driver charging meaning, reporting freshness and overlapping-work behavior on the target system. Another maintainer’s calibration is supporting evidence, not local proof. |
| Identity and continuity | Establish process/client lifetime binding and multi-record addition/replacement behavior, including same-length replacement, resets, disappearing clients and PID reuse. If unresolved, do not ship session rates; merely labelling substantially missing busy work as partial does not meet the product priority. |
| Coverage and cost | Define the admitted population, known gaps and failure states; validate short-client/exit limitations and sustained reader cost without compromising existing CPU/memory accounting. The 12-read probe is not this acceptance test. |
| Shared presentation | Validate Mac/TUI labels, comparison, unknown/partial states and retention against the same measured semantics; never portray device activity and process time rate as interchangeable. |

Proceed with the candidate only after the interface decision and evidence above support an honest contributor measurement. The current evidence supports continued investigation, not production enablement. GPU-01 in [PLAN](../../PLAN.md#deferred-features) owns these unresolved gates.

### Proposed bounded calibration

Authorization is pending; this experiment has not run. A CPU-only observer supervises one disposable, unprivileged Metal worker and retains only that worker's verified lifetime/client observations in bounded memory. Three serial batches run on queue A, queue B while A remains idle, and A after releasing application references to B. Each batch stops at 128 completed submissions or 200 ms of valid accumulated Metal elapsed time; the final finite submission can overshoot that timing target. The absolute submission cap is 384. Total explicit data-buffer lengths are at most 64 KiB; this does not bound Metal/compiler/framework allocations. The fixed kernel uses 4,096 threads with 256 bounded arithmetic iterations per thread. Setup remains inside the watchdog but outside measured batches.

Verify command completion, absence of command errors and output. Accept timing only when timestamps are finite, positive and ordered; missing timing does not relax the submission cap. Compare timestamp overlap rather than assuming summed duration equals its union. Observe registry changes before/after device and queue creation, before B's first work, after batches and after B's command/encoder/queue references and autoreleased objects are released. Reference release does not guarantee driver destruction. Bracket immediate/50/200 ms delayed readings with actual observation times and finish with a one-second no-submit cooldown.

An outer 20-second watchdog stops only the owned worker; it cannot cancel already-submitted GPU work. Use public Metal/IOKit only, with no existing-process actions, providers, private APIs, privileges, concurrent saturation or process/PID churn. Persist only aggregate findings and source/environment provenance. Compare raw increments with completed-command and wall elapsed times without forcing equality or fitting a universal conversion factor. The result can falsify queue-to-record mapping, retention and freshness assumptions; it cannot prove absolute units, arbitrary overlap accounting, complete exit coverage or reliable late attachment to other processes. Supported-version identity checks remain a separate scoped step if this calibration supports continuing.

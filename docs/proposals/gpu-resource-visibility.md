# GPU resource visibility

Status: **unapproved**, 2026-10-29. The user authorized feasibility research and this proposal, not production collection or UI support. Implementation requires acceptance of this design and resolution of its feasibility gates.

## Purpose and boundary

Extend the [resource responsibility question](../product.md) to GPU work: identify the observed process and, when verified, its agent/session and workload directory. Host activity provides context but cannot substitute for contributor accountability. The [source review and M1 probes](../research/gpu-accounting.md) demonstrate unprivileged registry access. The [bounded Metal calibration](../research/gpu-accounting.md#bounded-metal-calibration-falsifies-client-total-retention--2026-10-29) rejects treating the live `AppUsage` sum as retained history; consecutive guarded replay nevertheless preserves every observed increment in that coordinated fixture. A defensible observed-work contract, telemetry stability and metric semantics remain unresolved.

Direct, read-only IOKit registry access remains an observation candidate with explicit capability checks and retained accepted contributions. Public traversal APIs do not make `AppUsage` or `PerformanceStatistics` a documented stable telemetry contract. Adopting those driver-defined properties requires an explicit compatibility-policy decision; this proposal does not override the [rejection of privileged and unstable tracing dependencies](../decisions/privileged-resource-tracing.md). If that dependency is unacceptable, keep GPU support unavailable until a supported route is established.

## Required

### Metric meaning and availability

Keep device activity and process accounting separate. Device activity is the driver's reported device percentage, with its source and freshness disclosed; it is not the sum of contributor readings. Process accounting may expose **observed driver-reported GPU time** in seconds only after its unit and interpretation are validated. A rate, if admitted, is GPU-time seconds per measured wall second, not percentage of total GPU capacity. Do not divide by GPU-core count, clamp a process rate to 100%, infer capacity share or subtract it from the host graph.

The first observation establishes a baseline; pre-observation counters are not current-interval work or a known process-lifetime total. Zero requires a supported, valid interval. Missing properties, failed identity reads, malformed numbers, baseline/reset intervals, ambiguous record continuity and lost observations remain unavailable or partial with an explicit cause. A missing GPU client does not prove that its process is idle. Known exclusions can be counted, but they cannot quantify never-observed work.

### Identity, continuity and attribution

Bind observations to the device/client registry identity and a verified process lifetime, never PID alone. A creator PID plus two equal process-birth reads is insufficient evidence against a stale creator reference or shared-client ownership; establish the relationship and its lifecycle limits before admitting contributions. The [source follow-up](../research/gpu-accounting.md#creator-identity-and-aggregate-continuity-follow-up--2026-10-29) shows that the generic creator string can change when a shared client is opened again, without establishing that AGX shares those clients. Validate numeric type, units and checked arithmetic. Ownership changes and unsupported schemas invalidate baselines. A falling total must not be clamped into a valid zero interval; a justified matching model may retain supported survivor increments while explicitly excluding unresolved contributions.

Do not match repeated API records by array position or assume equal array length and increasing values prove continuity. Keep baselines separate for each client and verified ownership/accounting domain; never match records across those boundaries or let one client's retirement cancel another's increment. Keep accepted interval contributions separately from the live counter population; neither retiring records nor declining aggregates may erase acquired work. The current `AppUsage` sum is not a continuously retained counter, but that does not reject guarded interval accounting or justified record matching. Stable record IDs or producer source are not prerequisites if a supported-version empirical contract establishes the admitted behavior. Any claimed conservative matching result needs an explicit history model whose assumptions include the real transition; the [minimum-delta analysis](../research/gpu-accounting.md#minimum-delta-matching-needs-an-explicit-history-model) identifies why monotonicity and absence of duplicate views alone are insufficient. Missing final increments and never-observed clients remain coverage gaps, and retained history must not become stale current activity.

Apply existing exact-lifetime attribution to validated intervals. Group only compatible observations over the same accounting window; preserve unassigned/shared work and attribution uncertainty. Do not infer agent/session ownership from CWD, memory size, host load or temporal coincidence. Display filters cannot redefine measured totals, and later ownership evidence cannot silently reassign earlier work. Use an observed-work contract proportionate to CPU accounting: preserve acquired contributions and disclose material gaps rather than promise complete lifetime totals. Evaluate missed work against real queue lifetimes and explicit loss budgets; a partial label alone does not excuse substantial undercounting of busy work, and this coordinated fixture establishes neither those lifetimes nor acceptable losses.

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
| Identity and continuity | Establish process/client lifetime binding and the admitted record-matching/reset rules, preserving accepted increments across retirement. Validate the explicit model offline and characterize its real-driver assumptions empirically within separately authorized scope; suitable stable IDs are helpful but not mandatory. Same-count replacement remains hypothetical in this fixture. |
| Coverage and cost | Define the admitted population, known gaps and failure states; validate short-client/exit limitations and sustained reader cost without compromising existing CPU/memory accounting. The 12-read probe is not this acceptance test. |
| Shared presentation | Validate Mac/TUI labels, comparison, unknown/partial states and retention against the same measured semantics; never portray device activity and process time rate as interchangeable. |

Proceed with the candidate only after the interface decision and evidence above support an honest contributor measurement. The current evidence supports continued investigation, not production enablement. GPU-01 in [PLAN](../../PLAN.md#deferred-features) owns these unresolved gates.

### Research direction after calibration

The user authorized the bounded experiment separately, and it completed on 2026-10-29: one owned worker, 384 serial verified commands, a 16 KiB explicit data buffer and a 20-second watchdog that did not trigger. The [method, result and exact sources](../research/gpu-accounting.md#bounded-metal-calibration-falsifies-client-total-retention--2026-10-29) retain the evidence. No production collection or UI change was authorized or made.

The [review reconciliation](../research/gpu-accounting.md#review-reconciliation-and-task-counter-source-check--2026-10-29) separates unseen queue lifetimes from aggregate cancellation and shows that dense guarded replay retains all observed contributions. Research should now specify and test a bounded retained-contribution/per-record matching model offline, including newly visible pre-baseline history, before proposing another empirical test. Raw units and charging remain unresolved; Metal elapsed timing is a comparison, not an assumed equivalent oracle.

A later, separately authorized experiment could retain sanitized counter/timestamp tuples during survivor growth and retirement, and include a self-task `TASK_POWER_INFO_V2` diagnostic. The source check predicts a zero task field on its older arm64 implementation, so this is not a promised replacement; external name-port access, charging and completeness are separate questions. Host activity remains context rather than a substitute for contributor accounting. No additional native workload or production scope is authorized here.

# Codex session registry integration

Status: **deferred**, 2026-10-16. No integration is authorized; the contract below states conditions for reconsideration, not an approved design. Based on the completed [ATTR-02 investigation](../research/codex-terminal-attribution.md#session-listing-investigation--2026-10-16).

## Decision

Defer a Codex registry adapter. Codex 0.163.0 offers endpoint-scoped loaded-thread IDs, but no runtime PID in that response, and explicitly returns null OS PIDs for background terminals. Adding periodic listing would introduce connection effects without resolving marker-less workloads in a shared runtime. Keep the existing marker, ancestry and writer-descriptor evidence and its ambiguity semantics.

## Consequences of deferral

Marker-less workloads below shared Codex runtimes remain ambiguous: their CPU and memory are measured, but they cannot be grouped under an exact thread. Identifying the responsible task can require manual inspection in Codex. An unresolved workload cannot supply a verified messaging recipient; process-level inspection and verified termination remain available.

Existing marker, ancestry and writer-descriptor attribution continues unchanged. The visibility gap remains until upstream exposes a sufficient native process relation or another independently verified signal establishes ownership. Revisit runtime membership alone only if a concrete case gains an exact binding beyond the current evidence.

## Reconsider when

Two relations must remain distinct:

| Relation | Minimum meaning | Fit with the current monitor |
|---|---|---|
| Runtime to hosted thread | One verified local runtime lifetime plus a thread UUID and current hosting status, with complete membership for that runtime. | The existing `RuntimeSession` facet can represent the PID/session entries after host verification. Several hosted threads must leave the runtime unbound. Endpoint membership alone does not identify the runtime PID. |
| Workload to owning thread | One verified local workload lifetime plus its owning thread UUID and the reporting runtime lifetime; the provider must define which native process the PID names and whether the relation describes launch origin or current ownership. | Requires a separate workload relation. A workload PID must never be placed in `RuntimeSession.runtimePID`, and a protocol `processId` must never be treated as a kernel PID. |

For either relation, the host must verify same-user local process identity using PID, native start time and executable around the observation, reject stale/reused/conflicting identities, and retain uncertainty when completeness or endpoint ownership is unknown. A remote PID cannot identify a local process. An OS PID field without sufficient lifetime evidence does not satisfy this contract.

Provider command/method declarations and response interpretation belong to the Codex attribution adapter; bounded transport, native verification and conflict resolution belong to the host. Collection requires an explicitly supported observation path whose connection effects are acceptable; it must not start a server or session merely to discover ownership. The current [harness boundary](../architecture.md#harness-adapters) remains the ownership rule.

## Optional and excluded

Runtime membership alone could be useful only if a concrete supported case gains an exact single-thread binding beyond writer descriptors; this investigation established no such case. It is not a prerequisite for a future workload relation.

Excluded from reconsideration: implementation, new polling, generic adapter frameworks, transcript inspection, command/cwd/time heuristics, changes to messaging eligibility, and an Agent Monitor JSONL schema change. Any future evidence value or public contract change needs a separate approved design. Disposable sessions and further live initialization experiments require explicit authorization; source and generated-schema inspection can establish whether upstream has first supplied the missing relation.

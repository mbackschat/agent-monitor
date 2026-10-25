# Container resource probes

Status: **unapproved**, 2026-10-24. The user authorized this proposal only. Implementation waits until CPU-01's acquisition/accounting correction is accepted and this proposal is approved.

## Purpose and boundary

Extend the [agent/session resource question](../product.md) to container totals without turning it into generic infrastructure monitoring. Explain agent-launched container work that the host Docker client does not measure. The [live Docker investigation](../research/menu-bar-load-cost.md#docker-workload-attribution-and-nested-resources--2026-10-24) found an idle, exactly attributed client, a busy Lean container and an unattributed shared host VM. The design adds engine-API container totals, separately from [native process accounting](../architecture.md#resource-visibility-requirements). It does not infer ownership from project directories or assign the VM to a single client.

## Required

### Resource observations

Core owns a read-only local engine reader. Engine compatibility is verified through health/version capabilities, rather than inferred from the application name. Docker-compatible engines may be provided by Docker Desktop or Rancher Desktop; containerd is a different backend and excluded. The selected endpoint is explicit; discovery must not connect to arbitrary configured remote contexts. Enforce read-only access with a host-owned request allowlist: GET `/_ping`, `/version`, `/info` for engine identity, `/containers/json`, `/containers/{id}/json`, and `/containers/{id}/stats` with streaming disabled. Reject every other method, endpoint and streaming request; controlled contract tests must verify these rejections.

Container identity includes the engine-reported identity, verified local endpoint, full container ID and creation time. Deduplicate endpoint aliases only when verified to reach the same engine; a collection-run UUID is provenance, not engine identity. If engine identity is unavailable, report that capability gap rather than inventing a stable identity. Each start/restart establishes a separate counter epoch. Engine timestamps identify reported lifecycle events but are not host-monotonic acquisition timestamps. Each response retains host-monotonic request/response bounds; unavailable values remain unavailable.

CPU uses cumulative engine counters and differences between compatible observations in one epoch. The first successful counter establishes the baseline. Pre-baseline accumulated CPU may be shown separately, without a rate or inferred zero opening from engine wall time. Counter decreases, restart, endpoint replacement and unavailable reads carry explicit continuity/coverage semantics. Disappearance does not prove a final CPU observation.

Memory values keep their metric names: engine usage, cache-adjusted usage when its derivation is supported, cgroup current and cgroup peak when supplied. They are not native `footprintBytes`. Preserve reported CPU/memory limits and their source separately from effective VM capacity. Engine PID/task counts are labelled tasks/threads as appropriate, never presented as distinct worker counts.

A minimal typed observation is:

```swift
struct ContainerRunID: Hashable {
    let engineID: String
    let endpoint: String
    let containerID: String
    let createdAt: Date
    let startedAt: Date
}

enum ContainerMemoryMetric: Hashable {
    case engineUsage, cacheAdjustedUsage, cgroupCurrent, cgroupPeak
}

struct ContainerObservation {
    let run: ContainerRunID
    let requestedAt: Double // host-monotonic seconds
    let receivedAt: Double // host-monotonic seconds
    let cumulativeCPUSeconds: Double?
    let memoryBytes: [ContainerMemoryMetric: UInt64]
    let cpuLimitCores: Double?
    let memoryLimitBytes: UInt64?
    let taskCount: Int?
}
```

These are contract examples, not a generic plugin API. Observation coverage separately reports attempts, timeouts, unavailability, partial responses and capacity exclusions. A process/container limit must never silently redefine the displayed population.

### Attribution and privacy

The reader supplies observations; attribution adapters interpret allowlisted provider markers and association evidence. **Discard container environment variables at the host boundary except adapter-allowlisted marker keys.** Do not publish, log, cache or record the full inspect environment or raw response. Apply the same minimization to labels and command metadata: retain only fields required for validated association, and avoid emitting arbitrary command text by default. Messaging credentials are never resource-probe inputs.

An exact association requires a validated explicit binding to the container run, such as an allowlisted session marker or a verified container-ID binding from the attributed client. A corroborated association is a separate evidence kind: an attributed client lifetime and one container must uniquely match the verified engine endpoint, temporal creation evidence, image identity, command and mounts. Record the matched fields and clock uncertainty; if uniqueness or timing cannot be established, retain candidates or unknown ownership. Project path, cwd, image or naming convention alone is insufficient. The live investigation demonstrates feasibility, not a complete corroboration algorithm.

Freeze association evidence when established for a container run. The client's later disappearance does not erase it or establish an exit timestamp. Keep the client's exact lifetime, last observation and any separately confirmed exit evidence distinct. Restart requires new corroboration. A detached client missed by polling leaves its container unattributed unless independent explicit evidence exists. Later evidence does not silently reassign earlier CPU.

### Collection and presentation

The engine reader runs independently of host acquisition, on a seconds-scale cadence with a deadline, one request in flight per engine, cancellation, newest-observation coalescing and bounded container/context storage. Specify and measure those numeric bounds before implementation acceptance. Engine slowness must not delay host scans. Missing snapshots can still yield a later cumulative delta when identity and counter continuity remain valid; lost intermediate attribution or memory peaks stay disclosed.

Mac and TUI share the resulting resource and association projection. A session shows host CPU and associated container CPU as separate components of equal prominence, with evidence strength and freshness in progressive disclosure. The menu-bar agent CPU indicator remains host-only. Container totals belong to the guest accounting domain; the host VM remains separately measured infrastructure with unallocated ownership. Never add guest totals to host totals, subtract guest CPU from host VM CPU, or sum unlike memory metrics. Only verified containment edges may connect those views. No inferred ownership follows from a containment edge.

## Optional

Additional engine-supplied memory metrics and historical peaks may be displayed when their definitions and reset epochs are known. They do not require guest execution. Container names and image labels may aid navigation without becoming identity or ownership evidence.

## Excluded

- Container implementation before Track A acceptance and separate proposal approval.
- Exec, attach, shell commands, helper injection, guest process sampling or reliance on programs installed in images.
- Containerd/nerdctl, Kubernetes, remote engine access and a generic plugin runtime.
- Assigning or apportioning shared VM overhead to sessions; cross-domain remainder arithmetic.
- Starting, stopping, changing or messaging containers; reading transcripts or resource-unrelated credentials.
- Unqualified completeness, exact short-worker counts, recovery of missing final exit CPU or unobserved memory peaks.

## Material feasibility questions

Engine restart identity, API counter/reset semantics and cancellation behavior need controlled verification. Corroboration must handle overlapping identical launches, clock uncertainty and endpoint aliases without selecting an owner by order. Large inspect replies require bounded parsing and environment filtering before retention. The resource-reader contract should reuse counter arithmetic only after identity, units and reset rules are compatible; no generic ledger extraction is justified merely by similar numeric fields.

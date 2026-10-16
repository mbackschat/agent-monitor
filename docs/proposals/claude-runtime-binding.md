# Claude runtime-to-session binding

Status: proposed 2026-10-16, not approved for implementation. Evidence is in [Claude runtime attribution research](../research/claude-runtime-attribution.md); the current contract is in [architecture](../architecture.md#attribution-evidence-and-inspection-scope).

## Problem

A native Claude runtime never carries its own session marker, so the `claude` process — often the heaviest Claude row — is reported as `runtimeOnly` and displayed as an unresolved group beside its own session. Bash-tool shells and other Apple platform binaries it starts expose no environment and resolve the same way. Codex runtimes avoid this through writer descriptors; no comparable native Claude signal was found.

## Design

### Required: bind the runtime row

`claude agents --json` is the documented interface for live session state and already verifies messaging recipients. When a displayed heavy finding is a live Claude runtime without session evidence, the monitoring session asks the Claude adapter for the runtime's current session.

- An entry binds only when exactly one listed `pid` equals the runtime PID, its `sessionId` is a valid UUID and its `status` is `busy`, `waiting` or `idle`; otherwise the row stays `runtimeOnly`.
- The listing runs only on demand, never per process. Results are cached per runtime identity (PID and start time) for at most 60 seconds, bounding cost to about one call per minute while unresolved Claude runtimes are displayed (one call measured 0.36 s CPU).
- Failure, timeout, a missing `claude` executable or an unrecognized format leaves today's result unchanged.
- The binding states which session the runtime hosts at the time of the listing, not launch origin, so it gets its own evidence value:

```swift
public enum AttributionEvidence: String, Codable, Sendable {
    case marker, inheritedMarker, writerLock, sessionRegistry, runtimeOnly, ambiguous, unknown
}
```

`sessionRegistry` counts as an exact session for grouping and actions on the runtime row itself. Adding an enum value changes the JSONL wire contract, so it needs an explicit schema-version decision.

### Optional: children without readable environment

A descendant of a bound runtime whose own chain up to that runtime has no readable marker could take the runtime's binding with `sessionRegistry` evidence. A Claude runtime hosts one session at a time, but a shell started before `/clear` or `/resume` would be attributed to the newer session; the research could not establish whether `startedAt` exposes such a switch. Without this option these processes stay unresolved, which is accurate but leaves Bash-tool shells and platform tools outside their session.

### Optional: `CLAUDE_PID` as the detached link

Readable workload environments carry `CLAUDE_PID`, the runtime PID. It could link detached workloads whose inbox socket is absent, under the existing start-time ordering rule against PID reuse.

## Excluded

Reading `~/.claude/sessions`, transcripts or messaging tokens; contacting sessions; using `cwd` for ownership; deriving project labels from the listing's `cwd` (a separate presentation decision).

## Material risks

- The listing is a research preview without a stable format.
- The parser lives in `AgentMonitorActions`; binding in the core requires moving it into the Claude attribution adapter and adding a provider-subprocess observation to the adapter contract, which the sampler does not have today.
- The menu bar app inherits `PATH` only when started through `scripts/menubar.sh run`; otherwise the listing may be unavailable and the binding silently absent.

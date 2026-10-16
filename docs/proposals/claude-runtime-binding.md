# Claude runtime-to-session binding

Status: implemented on 2026-10-16 as the [harness session registry](../architecture.md#harness-session-registries), including binding of marker-less descendants and JSONL schema version 2. Evidence is in [Claude runtime attribution research](../research/claude-runtime-attribution.md). This note retains only the deferred option.

## Deferred: `CLAUDE_PID` as the detached link

Readable workload environments carry `CLAUDE_PID`, the runtime PID. It could link detached workloads whose inbox socket is absent, under the existing start-time ordering rule against PID reuse. No observed detached workload lacked a usable inbox socket, so there is no concrete need yet.

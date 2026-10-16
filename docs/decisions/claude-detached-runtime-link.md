# Claude detached-workload link through `CLAUDE_PID`

Status: **deferred**, 2026-10-16. The implemented runtime-to-session binding is the [harness session registry](../architecture.md#harness-session-registries); this record keeps only the option left out of it.

## Decision

Do not link detached Claude workloads to their runtime through the `CLAUDE_PID` environment variable.

## Reason

Readable workload environments carry `CLAUDE_PID`, the runtime PID. It could link detached workloads whose inbox socket is absent, under the existing start-time ordering rule against PID reuse. No observed detached workload lacked a usable inbox socket, so there is no concrete need.

## Reconsider when

A detached Claude workload is observed without a usable inbox socket. Evidence is in [Claude runtime attribution research](../research/claude-runtime-attribution.md).

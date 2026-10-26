# Privileged resource tracing

Status: **rejected**, 2026-10-26.

## Decision

Do not pursue the inspected root/private-interface exit-tracing path as Agent Monitor's accounting backend. The user rejected both requirements as deployment showstoppers after the [source investigation](../research/cpu-accounting.md#exit-accounting-alternatives-and-workload-evidence--2026-10-26).

## Reason

An accounting mechanism must meet the deployment constraints as well as the coverage requirement. The inspected release-kernel tracing path requires root and unstable interfaces; its source-supported exit counters do not justify adopting those dependencies. Polling-only incomplete accounting remains a separate shipping blocker.

## Reconsider when

New evidence establishes a supported, unprivileged route meeting transparent attachment and attribution requirements, or the user explicitly changes these constraints. Apple Activity Monitor's private entitlements do not establish third-party availability; see the [installed-binary investigation](../research/cpu-accounting.md#activity-monitor-data-path--2026-10-26).

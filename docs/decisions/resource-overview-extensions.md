# Resource overview extensions

Status: **deferred**, 2026-10-24. The approved overview addendum was implemented as the [contributor overview and recent activity contract](../architecture.md#contributor-overview-and-recent-activity). This record retains only its excluded extensions. The user's original input and full reviewed design remain in Git history at `8b597ca`; [research](../research/menu-bar-load-cost.md#population-and-overview-feedback--2026-10-24) records the motivation, corrections and validation limits.

| Extension | Decision and reconsideration condition |
| --- | --- |
| Separate native Explorer / graphical ancestry navigation | Deferred: initial statistics are available in existing Mac/TUI views, but that does not establish usable orientation. The [product contract](../product.md) and UX-01 require a clearer agent/session/process comparison; an Explorer is not a prerequisite. Reconsider a separate window only with a concrete unmet navigation need and separate approval. |
| Historical session memory peak | Gated: compact worker maxima cannot reconstruct simultaneous session footprint. Requires per-scan aggregates, observation-time labels and an explicit evidence/coverage contract. |
| Monotonic distinct totals since start | Deferred: exact cumulative identities require explicit bounded retention/reset semantics. The shipped no-longer-observed counter is rolling and is not confirmed termination. |
| Retroactive live-history revisions | Deferred: labels freeze at unit closure. Reconsider only with owned-workload evidence of material unresolved short-worker CPU due to late evidence, a numeric revision horizon and a revised capacity budget. Recording retains its separate revision contract. |
| Configurable recent range / recording-backed analysis | Deferred: current history targets 60 seconds in memory and resets with run/scope. Persistent recording and analysis remain separately specified in [diagnostic recording](../proposals/diagnostic-recording.md). |
| Executable alias/classification heuristics | Excluded from the initial delivery: basename grouping is an observation, not a claim that binaries or versions are identical. A future mapping needs an explicit evidence contract owned by core. |

Wholly missed lifetimes and final exit CPU remain [active accounting work](../../PLAN.md#resource-accounting-priority), not problems solved by retaining already-observed activity.

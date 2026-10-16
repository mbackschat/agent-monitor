# Count newborn CPU and show host load

Status: **implemented**, 2026-10-16. The accepted R1 newborn CPU and R2 host-context contract now lives in [architecture](../architecture.md#cpu-accounting); [usage](../usage.md#filters-and-measurements) describes the surfaces. Only exited-descendant recovery remains deferred. Evidence and probe limits remain in [CPU accounting coverage](../research/cpu-accounting.md).

## Deferred: CPU of exited descendants

Recovering work that ends between samples from `ri_child_user_time`/`ri_child_system_time` is deferred. [Review evidence](../research/cpu-accounting.md#review-follow-up--2026-10-16) shows that automatic reaping (`SIGCHLD` ignored) doubles these counters, and that crediting only direct children recounts observed CPU when an intermediate process collects a grandchild and exits. Moving credit to ancestors alone does not fix this.

Reconsider only with both of the following:
- validated counter semantics, including automatic reaping, across supported OS builds;
- a conservation model covering scan ordering, temporary read failures, baseline exclusions (CPU consumed before monitoring began), reparenting and ancestor departure.

Any recovered CPU must stay distinct from live measurements and be labeled by when it was accounted, not when it ran. A narrower alternative to investigate first is reading the final counters of zombies already identified by the reader.

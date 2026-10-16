# Recovering CPU of exited descendants

Status: **deferred**, 2026-10-16. The implemented newborn first-interval CPU and host context are in [architecture](../architecture.md#cpu-accounting); this record keeps only the part left out of that change.

## Decision

Do not recover work that ends between samples from `ri_child_user_time`/`ri_child_system_time`.

## Reason

[Review evidence](../research/cpu-accounting.md#review-follow-up--2026-10-16) shows that automatic reaping (`SIGCHLD` ignored) doubles these counters, and that crediting only direct children recounts observed CPU when an intermediate process collects a grandchild and exits. Moving credit to ancestors alone does not fix this.

## Reconsider when

Both of the following exist:

- validated counter semantics, including automatic reaping, across supported OS builds;
- a conservation model covering scan ordering, temporary read failures, baseline exclusions (CPU consumed before monitoring began), reparenting and ancestor departure.

Any recovered CPU must stay distinct from live measurements and be labeled by when it was accounted, not when it ran. A narrower alternative to investigate first is reading the final counters of zombies already identified by the reader.

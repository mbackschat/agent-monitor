# Hardware-informed fixed CPU chart range

Status: **on hold**, 2026-10-29. The user accepted the design direction and requested this write-up. Implementation waits for verified core-type discovery, especially on three-tier CPUs; the current fixed logical-CPU range remains implemented.

## Purpose

Make contributor activity readable without allowing activity to change its scale. The [hardware evidence and limits](../research/native-menu-design.md#hardware-informed-chart-range--2026-10-29) distinguish accumulated CPU time from computing performance. This is a display range, not a claim about which cores are occupied or how much computing power remains.

## Required

- Choose the initial upper bound once from verified hardware topology: 100% × the number of performance and super cores. For the specified configurations, M1's four performance cores give 400%; M6's two super plus four performance cores give 600%. Use actual configuration, not a chip-name lookup or an assumption that the highest performance level contains every non-efficiency core.
- Keep the chosen range fixed across activity, arrivals/departures, sorting, pinning, pause/resume and view changes. All contributor lanes in one interface share it. Hardware discovery must not become activity-driven rescaling.
- Preserve the measured CPU percentages, CPU seconds, totals and equal-width interval semantics. Values above the range receive a visible overflow marker; their actual historical interval values remain inspectable.
- Permit an explicit manual range override, including the full logical-CPU range. A manual choice takes precedence over the hardware default and remains stable during monitoring.
- If the core types cannot be established reliably, use the full logical-CPU range as the documented fallback and allow manual selection. Do not guess a performance/efficiency split.

The minimal range contract is `upperPercent: Double`, finite and positive; 100% always means one CPU-second per elapsed second. Label the displayed range directly, for example “CPU history · 0–600%”.

## Optional

Remember an explicit manual choice between launches. Persistence is not required for the initial implementation.

## Excluded

Activity-driven ceilings, weighted efficiency-core equivalents, inferred per-process core placement, nonlinear axes, and changes to collection or attribution are excluded.

## Feasibility limits

Apple documents numbered performance levels and counts, but ordering alone does not identify every non-efficiency tier. A tested classification contract is required before claiming M6 support. The default remains a readability heuristic, including on chips without efficiency cores; manual selection handles workloads that benefit from a narrower or wider range. Physical Mac menu/keyboard and TUI input behavior require the normal [UX acceptance checks](../development.md#resource-overview-ux-review).

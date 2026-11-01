# Proposals

Open designs under review or awaiting acceptance. Read each proposal’s status and authorization boundary before treating its design as work to implement.

| Status | Meaning |
| --- | --- |
| **Unapproved** | Under review; implementation is not authorized. |
| **Approved** | The stated implementation scope is authorized; unfinished delivery or acceptance gates remain. |
| **On hold** | The status line identifies the dependency or decision blocking progress. |

A proposal’s existence does not authorize implementation. [PLAN.md](../../PLAN.md) tracks open work; [architecture](../architecture.md) owns implemented contracts. Deferred, rejected and superseded outcomes belong in [decisions](../decisions/README.md). Follow the [documentation lifecycle](../development.md#documentation-and-instruction-maintenance) when a design changes status.

The table is generated from each proposal's `Status:` line; do not edit it by hand.

<!-- status-table:begin -->
| Proposal | Status | Since |
| --- | --- | --- |
| [Resource accounting across process lifetimes](resource-accounting.md) | approved | 2026-10-24 |
| [Supplemental observations during inspection](inspection-observations.md) | approved | 2026-10-26 |
| [Bounded diagnostic recordings](diagnostic-recording.md) | unapproved | 2026-10-23 |
| [Container resource probes](container-resource-probes.md) | unapproved | 2026-10-24 |
| [GPU resource visibility](gpu-resource-visibility.md) | unapproved | 2026-10-29 |
| [Proposed agent working model](agent-working-model.md) | unapproved | 2026-10-15 |
| [Bounded, ordered terminal input](bounded-terminal-input.md) | on hold | 2026-10-26 |
<!-- status-table:end -->

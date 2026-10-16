# Proposed agent working model

Status: **unapproved proposal**, 2026-10-15. It does not authorize delegation.

## Status and ownership

This is a proposed allocation of work, not authorization to delegate future tasks. The user's global instructions own the HIGH, MEDIUM, and LOW model selectors and effort settings; resolve the active CLI's mapping there rather than duplicating it here. Unsupported configurations must be reported, not silently substituted.

## Tier roles

| Tier | Suitable work | Why |
|---|---|---|
| HIGH | Attribution and measurement contracts; architecture decisions; difficult correctness investigations; review of process identity, permissions, concurrency, and ambiguous ownership | Errors here produce plausible but incorrect blame. These tasks require reasoning across OS behavior, agent metadata, and product guarantees. |
| MEDIUM | Bounded implementation with red/green TDD; focused primary-source research; provider adapters; CLI behavior against an agreed contract | Clear boundaries and observable acceptance criteria permit independent progress while preserving design consistency. |
| LOW | Source/link inventories; transcription of license facts; mechanical documentation edits; deterministic fixture preparation under an explicit specification | These tasks have narrow scope and readily checked outputs. LOW should collect evidence rather than settle licensing interpretation or architectural uncertainty. |

## Delegation boundaries

When delegation is explicitly authorized, give each agent one bounded question or deliverable, source constraints, a file ownership boundary, and an observable acceptance criterion. Prefer independent research or implementation units; avoid several agents changing the same file or independently inventing the same public contract.

Use the lowest tier that can satisfy the stated oracle. Escalate when evidence conflicts, the contract is unclear, a failure crosses subsystem boundaries, or resolving uncertainty would change product behavior. A tier is a task fit, not a substitute for verification.

## Verification and integration

The coordinating agent checks source provenance, reconciles conflicting findings, and owns integration. HIGH reviews material attribution and accounting changes; it need not review every mechanical edit. MEDIUM implementations require failing tests before fixes and passing behavior-focused checks afterward. LOW output needs deterministic checks or review against its source before adoption.

Every handoff states what changed, the evidence or checks performed, and remaining uncertainty. Keep durable decisions in repository documentation. Follow the [product scope](../../PLAN.md#scope-and-pending-decisions); no worker may turn a research suggestion into a requirement or introduce privileged collection, telemetry, installation, or publishing without authorization.

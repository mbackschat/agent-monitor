---
name: monitor-ui-ux
description: Design and review Agent Monitor's Mac and TUI experience, including UI recommendations, control selection, layout, hierarchy, labels, diagnostics, focus, keyboard navigation and accessibility. Use before advising on or changing these surfaces; not for collection-only work without a user-interface change.
---

# Agent Monitor UI/UX

Use this workflow for advice as well as implementation. SwiftUI structure/performance skills complement it; they do not validate interaction design. This skill is shared by Codex and Claude Code and uses only repository files and the host's available read/test tools.

1. Read the [product information contract](../../docs/product.md) and the [resource overview UX review](../../docs/development.md#resource-overview-ux-review), including the shared checks and the affected Mac or TUI subsection. Read relevant current behavior in [architecture](../../docs/architecture.md) and controls in [usage](../../docs/usage.md). Keep the task anchored to agent → session → CWD → executable → CPU/memory.
2. For reported defects, trace the actual view/state path before proposing a fix. For control recommendations, verify current standard-platform capabilities in the installed SDK or official documentation. Evaluate SwiftUI controls first for Mac content, including hierarchical `Table`; justify an AppKit/custom fallback with a demonstrated requirement. Existing AppKit lifecycle ownership is not a reason to bypass SwiftUI content controls.
3. Check the full interaction: locating the contributor, comparing values, selecting, disclosing children, inspecting details and returning. Distinguish static information, selected rows, keyboard focus and actions. Apply the guide's metric-language and diagnostic-disclosure checks. Assess the other interface for shared semantic benefits, but do not silently expand implementation scope.
4. Match evidence to the claim: source for wiring, deterministic tests for state transitions, inspected renders for appearance and synthetic PTY tests for terminal interaction. Use fake data/providers; do not launch live workloads, contact providers or enable Computer Use. Physical Mac/keyboard/accessibility checks remain user-owned and explicitly pending. Advice-only tasks do not authorize implementation or require a build.
5. Give a concrete recommendation and rationale, including any unresolved platform limitation. On implementation, follow repository TDD and validation rules, update the owning contract and controls, and keep unfinished acceptance in [PLAN](../../PLAN.md). Do not present the existence of this skill or passing automated checks as proof of good UX.

Maintain the decision procedure in the development guide and the product semantics in their owning documents; do not copy them into this skill. When accepted feedback exposes a missing check, update that owner and this routing if necessary. Both host discovery links must continue to resolve to this tracked directory. The [repository license](LICENSE) applies.

# Research index

Research checked on 2026-10-14 for a macOS tool that identifies CPU and memory consumption caused by terminal agent sessions: Codex CLI first, Claude Code afterward. Desktop agent variants remain possible future extensions. Findings describe inspected sources; recommendations are not implementation decisions. No dependencies, skills, hooks, or monitoring services were installed for this research.

## Start here

- [Product vision and requirements](PRODUCT.md): confirmed scope, proposed behavior, and unresolved product decisions.
- [Research assessment](assessment.md): decision-oriented synthesis covering existing alternatives, code reuse, attribution, measurement, and development skills.
- [Proposed agent working model](agent-working-model.md): HIGH, MEDIUM, and LOW responsibilities, escalation, and verification boundaries; does not activate delegation.

## Evidence notes

- [Process termination and session messaging](session-actions.md): proposed TUI actions, installed-provider capabilities, and limits of reaching existing sessions; feasibility only.
- [Messaging an existing Claude Code session](claude-session-messaging.md): installed-CLI and documentation evidence for verifying and reaching a running Claude session from a separate process.
- [Focusing the terminal that hosts a session](terminal-focus.md): per-terminal mechanisms, macOS Automation/activation limits, and a recommended minimal design for bringing a session's window, tab, and pane to the front; feasibility only.
- [Menu bar app as an alternative front end](menubar-app.md): reuse of the presentation and action layers, sandbox and distribution limits, provider CLI lookup, sampling cadence, and blast radius; feasibility only.

- [Terminal UI options](terminal-ui.md): Swift library evaluation and integration evidence for the opt-in live report, disclosure behavior, and the boundary needed for future native presentation.

- [Codex terminal-session attribution](codex-terminal-attribution.md): priority investigation using the installed version's source, root/thread/runtime identities, inherited markers, and specific-session evidence for heavy consumers.
- [Local terminal-process observations](terminal-process-observations.md): anonymized native process observations, synthetic orphan/marker experiments, environment-inspection limits, and an acceptance matrix.
- [Existing solutions and reusable code](existing-solutions.md): direct alternatives, general monitors, implementation evidence, license observations, and reuse limits.
- [macOS process measurement and attribution](macos-process-attribution.md): native APIs, CPU and memory semantics, process identity, permissions, orphaned children, and event collection limits.
- [Development skills and agent integration](development-skills-and-agent-integration.md): skills for Codex and Claude Code, staged tooling recommendations, session metadata, hooks, and public-interface limitations.

- [Sustained-watch measurements](sustained-watch-2026-10-14.json): ten-minute native CPU/physical-footprint trace and process-churn summary; interpretation is in [PoC validation](../poc-validation.md#sustained-optimized-watch-2026-10-14).

- [Claude terminal validation](claude-terminal-validation-2026-10-14.json): real heavy-child observations matched to independent session metadata, runtime lifetime, and terminal evidence; see the [validation explanation](../poc-validation.md#real-terminal-claude-code-validation-2026-10-14).

Each evidence note separates findings, inferences, and gaps. Recheck source revisions and compatibility before copying code or installing tooling. The subsequent Swift PoC and controlled attribution checks are recorded in [PoC validation](../poc-validation.md); [development guidance](../development.md) records the current project-local skill installation status.

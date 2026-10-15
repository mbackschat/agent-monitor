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

Each evidence note separates findings, inferences, and gaps. Recheck source revisions and compatibility before copying code or installing tooling. Current checks, live coverage limits and skill setup belong in the [development guide](../development.md).

## Retained measurements

These observations were collected on Apple Silicon, macOS 27.0.1, Xcode 27 and Swift 6.4 on 2026-10-14. Session IDs and project paths/names are anonymized replacements; measurements and process relationships are retained. They describe the measured binaries and sampling windows, not current performance guarantees.

- [Sustained-watch trace and binary SHA-256](sustained-watch-2026-10-14.json): a 600.817-second headless JSONL run at the default one-second interval delivered 569 reports across 561–604 same-user processes, including 120 deliberately short-lived owned children. Average CPU was 0.805% of one core; physical footprint peaked at 8.37 MB, with warm-up/final-minute medians of 7.72/5.42 MB. No sustained growth appeared in this bounded run. The [harness](../../scripts/verify-sustained.py) uses native physical footprint (not RSS) and user/system Mach ticks converted with `mach_timebase_info`; see [reproduction commands](../development.md#terminal-and-machine-output-checks). This is not a long-duration leak guarantee or a sustained TUI measurement.
- [Claude terminal observations and independent evidence](claude-terminal-validation-2026-10-14.json): a real Java child at 13:15:45 UTC used 34.51% CPU and 85.87 MB footprint; an earlier child used 423.51% CPU. Both mapped to the same session/runtime/TTY. Allowlisted Claude session metadata, a native runtime birth-identity query and an `lsof` stdin-device check independently matched the attribution. Only relevant metadata was inspected, not transcripts. This validated native Claude terminal attribution; no heavy terminal Codex workload was observed.

Short optimized TUI smoke runs on that date used approximately 1.9–4.2% of one core, including startup and rendering. These are historical smoke observations without a retained full trace, not a sustained benchmark; rerun the [terminal check](../../scripts/verify-tui-terminal.py) for a current measurement.

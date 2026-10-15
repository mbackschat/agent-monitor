# Project plan

## Resume point

[v0.2.2](https://github.com/mbackschat/agent-monitor/releases/tag/v0.2.2) is published, including the detached Codex job fix, shared-runtime label and built-in attribution adapters. The original PoC is complete. Release checks and changes are recorded in the [release notes](docs/releases/0.2.2.md); current behavior belongs in the [README](README.md), [usage guide](docs/usage.md) and [architecture](docs/architecture.md).

Keep this file limited to unfinished work, scope decisions and the next action. Remove completed entries once their durable outcome is documented; Git history retains the implementation log. Validation commands and coverage limits belong in the [development guide](docs/development.md#validation-coverage).

## Open follow-ups

- [ ] **MENUBAR-COUNT — Align the icon count with the displayed table.** Use the same filters and snapshot for both the count and CPU bars, including paused inspection, and show a total beside Heavy processes. While open, bars and badge update with the displayed table; while closed, retain the 15-second cadence. History remains all-agent and at most every 15 seconds. Derive icon values from already collected findings without extra native reads.

- [ ] **MENUBAR-KEYS — Match the TUI's single-key browsing controls.** Use `p` for pause/resume, Space for pin/unpin, and the TUI keys for sorting, grouping and history. Add native `y`/Copy PID and selectable PID details for individual processes. Keep text editing, menu tracking and action confirmation isolated from browsing shortcuts; update compact help and documentation.

- [ ] **ACTIONS-03 — Complete manual terminal-focus validation.** Terminal.app tab selection is implemented and was confirmed by the user on 2026-10-15. Next action: check a background window, minimized window, another Space, full screen, monitor and target in the same window, and the first Automation prompt using disposable tabs. Follow the [manual gate](docs/development.md#manual-terminal-focus-check); fake-adapter tests cannot establish macOS activation behavior.
- [ ] **MENUBAR-01 — Validate the native menu bar app.** Try the [menu bar app](docs/usage.md#menu-bar-app) for layout, dismissal/reopening and composing in the popover. Live app Automation/focus and provider messaging need disposable-session validation; measure ten-minute closed-panel CPU/wakeups separately for the live 15-second icon and static mode before making sustained-energy claims. Distribution is deferred until the app is finished; feature expansion remains a separate decision.
- [ ] **MENUBAR-03 — Validate live resizing and native accessibility.** Offscreen checks cover fixed heights across sparse/expanded/paused/action states, user-selected sizes, screen capping, inherited light/dark appearance and menu identity across updates. Check live anchoring while changing the size preset, enlarged group/count/info targets and their VoiceOver meaning, pin hover/focus feedback and repeated ⌘P, right-click/Control-click status-menu opening and return to normal left-click, first-click View options opening and submenu tracking during refreshes, row arrow/Enter navigation with scroll-to-focus, and VoiceOver with synthetic fixtures; [reference findings](docs/research/native-menu-design.md#unresolved-empirical-questions) distinguish source/offscreen evidence from live interaction.
- [ ] **TUI-11 — Correct terminal-cell sizing for wide Unicode names.** The report table measures characters rather than display cells, so wide names can misalign columns. This existing limitation is separate from action-panel sizing. Next action, when selected: reproduce it with a failing layout test before changing width calculation.

Real terminal Codex workload attribution and live Codex child-recipient routing/message delivery remain [coverage gaps](docs/development.md#validation-coverage), not unfinished PoC acceptance gates. Do not manufacture agent work or send messages to existing sessions to close them without specific authorization.

## Scope and pending decisions

The shipped scope includes text/TUI/JSONL reports, session grouping in text and TUI, built-in Codex/Claude attribution, confirmed single-process termination, verified session messaging and terminal focus through both TUI and CLI actions. Preserve the [architecture boundaries](docs/architecture.md) when extending it.

Pending ideas, not yet approved for implementation:

- A compact provider column with sorting and a command-line-only provider filter. Provider recognition must come from attribution adapters; this is separate from the completed extraction.
- Author credit in `--help`.

Production app packaging, desktop/remote/container attribution, broader platform/provider support, notifications, background monitoring services, additional terminal adapters/tmux resolution, optional session metrics and external plugins need separate scope decisions. The native menu bar app is maintained as a source-built feature with shared sampling, grouping and verified actions; its [architecture](docs/architecture.md#native-menu-bar-app) defines 15-second closed-panel sampling for the live icon and no closed-panel sampling for the optional static icon. The [retained proposal](docs/proposals/menubar-app.md) retains deferred product decisions. The [working-model proposal](docs/proposals/agent-working-model.md) does not authorize delegation. Dated source findings belong in the [research index](docs/research/README.md).

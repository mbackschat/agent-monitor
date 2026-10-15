# Project plan

## Resume point

[v0.2.2](https://github.com/mbackschat/agent-monitor/releases/tag/v0.2.2) is published, including the detached Codex job fix, shared-runtime label and built-in attribution adapters. The original PoC is complete. Release checks and changes are recorded in the [release notes](docs/releases/0.2.2.md); current behavior belongs in the [README](README.md), [usage guide](docs/usage.md) and [architecture](docs/architecture.md).

Keep this file limited to unfinished work, scope decisions and the next action. Remove completed entries once their durable outcome is documented; Git history retains the implementation log. Validation commands and coverage limits belong in the [development guide](docs/development.md#validation-coverage).

## Open follow-ups

- [ ] **ACTIONS-03 — Complete manual terminal-focus validation.** Terminal.app tab selection is implemented and was confirmed by the user on 2026-10-15. Next action: check a background window, minimized window, another Space, full screen, monitor and target in the same window, and the first Automation prompt using disposable tabs. Follow the [manual gate](docs/development.md#manual-terminal-focus-check); fake-adapter tests cannot establish macOS activation behavior.
- [ ] **TUI-11 — Correct terminal-cell sizing for wide Unicode names.** The report table measures characters rather than display cells, so wide names can misalign columns. This existing limitation is separate from action-panel sizing. Next action, when selected: reproduce it with a failing layout test before changing width calculation.

Real terminal Codex workload attribution and live Codex child-recipient routing/message delivery remain [coverage gaps](docs/development.md#validation-coverage), not unfinished PoC acceptance gates. Do not manufacture agent work or send messages to existing sessions to close them without specific authorization.

## Scope and pending decisions

The shipped scope includes text/TUI/JSONL reports, session grouping in text and TUI, built-in Codex/Claude attribution, confirmed single-process termination, verified session messaging and terminal focus through both TUI and CLI actions. Preserve the [architecture boundaries](docs/architecture.md) when extending it.

Pending ideas: a compact provider column with sorting and a command-line-only provider filter; author credit in `--help`. Provider recognition must come from attribution adapters. These ideas are not part of the completed adapter extraction.

Native/menu bar UI and app packaging, desktop/remote/container attribution, broader platform/provider support, notifications, background monitoring services, additional terminal adapters/tmux resolution, optional session metrics and external plugins need separate scope decisions. The [menu bar proposal](docs/proposals/menubar-app.md) preserves the user’s closed-popover energy constraint; its implementation remains unapproved. The [working-model proposal](docs/proposals/agent-working-model.md) does not authorize delegation. Dated source findings belong in the [research index](docs/research/README.md).

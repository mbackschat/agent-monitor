# Repository instructions

Agent Monitor maps heavy macOS processes to coding-agent sessions through text, JSONL, TUI and a maintained native menu bar app. `CLAUDE.md` is canonical; preserve the `AGENTS.md` symlink.

## Start and scope

Read [PLAN.md](PLAN.md) when resuming; it owns unfinished work and scope decisions. Process termination, Codex/Claude messaging and adapter-based terminal focus are shipped capabilities, not permission to act on live workloads. Proposals do not authorize implementation. Read-only search and review subagents are allowed; the tier-based delegation of the [working-model proposal](docs/proposals/agent-working-model.md) is not adopted. Keep unrelated product expansion outside the current task.

Before changing a subsystem, read its relevant contract below; do not reread unrelated guides or material already current in this session. If code bypasses its documented ownership, make the smallest authorized extraction before extending it. Surface a material scope conflict rather than building on the bypass. Keep implementation, architecture status and contributor guidance aligned in the same commit.

## Ownership and essential invariants

| Target under `Sources/` | Owns |
| --- | --- |
| `AgentMonitorCore` | Native sampling, lifetimes, attribution and UI-independent snapshots; no UI or Argument Parser dependencies. |
| `AgentMonitor` | CLI arguments and output selection; Argument Parser stays in CLI targets. |
| `AgentMonitorPresentation` | Neutral grouping, selection, disclosure, pins, history and action-review state. |
| `AgentMonitorTUI` | SwiftTUI rendering and terminal input. |
| `AgentMonitorActions` | Verified termination, provider messaging and terminal-focus adapters. |
| `AgentMonitorMenuBar` | AppKit lifecycle and SwiftUI presentation; reuse shared services, never SwiftTUI. |

Harness-specific recognition, marker validation, descriptor/inbox interpretation, runtime classification and listing declarations/parsing belong in [attribution adapters](Sources/AgentMonitorCore/AttributionAdapters/). Hosts own native access, allowlisting and command execution; adapters declare and interpret observations. Never add provider heuristics to the sampler, reader, parser, models or UI. Preserve all recognition claims and uncertainty; adapter order cannot select an owner. Messaging and focus keep separate action adapters.

Use exact process lifetimes, not PID alone. Never infer ownership from cwd or treat a protocol process handle as an OS PID. Session totals cover displayed heavy processes only; grouping preserves provider/session identity and leaves JSONL flat. Project labels use workload directories, never a shared runtime's launch directory. Shared presentation owns sticky disclosure without stale measurements or overriding explicit inspection changes.

Actions require frozen identity, fresh same-user/recipient verification and explicit confirmation where applicable. Acceptance is not delivery or completion; never automatically retry uncertain actions. Never read transcripts or a Claude messaging token. Tests and research probes use fake providers and disposable owned processes, never real harness listings, live messages or signals to user workloads; keep a probe script only when its measurement is retained.

## Read only the contracts relevant to the change

| Change | Required guidance |
| --- | --- |
| Attribution, provider or native observation | [Harness contracts](docs/architecture.md#agent-attribution-adapters), [adapter checks](docs/development.md#changing-attribution-adapters). |
| Grouping, disclosure or snapshot semantics | [Presentation boundaries](docs/architecture.md#boundary-for-multiple-presentations), [shared state](docs/architecture.md#current-implementation). |
| Actions or provider transports | [Action contract](docs/architecture.md#process-and-session-actions), [validation limits](docs/development.md#validation-coverage). |
| Native UI, input or lifecycle | [Native contract](docs/architecture.md#native-menu-bar-app), [headless checks and user smoke test](docs/development.md#menu-bar-app). |
| TUI or resource history | [TUI contract](docs/architecture.md#tui-contract), [history contract](docs/architecture.md#resource-history), [terminal checks](docs/development.md#terminal-and-machine-output-checks). |
| CLI options or JSONL | [Wire/presentation boundary](docs/architecture.md#boundary-for-multiple-presentations), [usage](docs/usage.md). Verify defaults, units and combinations against `Options.swift` and generated `--help`; update the README option table/examples and affected usage, including TUI's different sample default. |
| Research note, proposal or decision record | [Research index](docs/research/README.md), [proposal lifecycle and folder indices](docs/development.md#documentation-and-instruction-maintenance); change statuses with `python3 scripts/docs.py status`. |
| Rendered documentation | [Preview maintenance](docs/development.md#readme-preview), [native image generation](docs/development.md#build-and-coverage-details). |
| Dependencies, skills or packaging | [Dual-host skills](docs/development.md#skills-shared-by-codex-cli-and-claude-code), [release packaging](docs/releasing.md). Pin changes require [third-party notices](THIRD_PARTY_NOTICES.md) from locked sources, including vendored components/fonts; retain notices and licenses in archives. |

Use installed `swiftui-view-refactor` for native structure/dependency/Observation work and `swiftui-performance-audit` for rendering/refresh/scrolling investigations; keep the concurrency/testing skills available for matching work. If an optional skill is unavailable, follow the project guidance and report the limitation; do not install or upgrade merely to unblock routine work. See [skill setup and fallback](docs/development.md#skills-shared-by-codex-cli-and-claude-code). Performance suspicions remain hypotheses until measured.

## Implement and validate

Use Xcode 27, Swift 6.4 and macOS 27. Follow four-space indentation, bundled `swift format`, Swift 6 concurrency checking and enum-based switches. Comments explain constraints and cite their basis. Use red/green TDD for behavior changes and descriptive Swift Testing tests; positive attribution fixtures must resolve exact sessions, not merely return unknown.

Select checks using the [validation matrix](docs/development.md#choose-checks-for-the-change). Headless validation is the default: deterministic core/presentation/model inputs, fake transports, controlled clocks and synthetic offscreen AppKit renders. Reuse production composition across layers. Computer Use is disabled; do not request or enable it for routine review. The user owns live macOS smoke tests, which remain pending until reported. Automated results cannot prove physical input delivery, menu anchoring or live provider delivery.

Common commands from the repository root:

- `swift build` and `swift test`: build and run the Swift suite; use `swift test --filter <Suite>` for red/green loops and the full suite before committing shared-contract changes.
- `python3 scripts/docs.py check`: documentation links, anchors, folder indices and status tables; required for documentation-only commits.
- `swift format lint --strict --recursive Sources Tests Tools Package.swift`: formatting.
- `bash scripts/doctor.sh`: read-only prerequisites and instruction/skill checks.
- `bash scripts/preview.sh check`: generated TUI preview drift.
- `bash scripts/menubar.sh build`: optimized local bundle; `run` supplies shell PATH to transports.

Specialized native/terminal probes and restricted-environment workarounds are in the [development guide](docs/development.md). Do not run every probe for every change.

## Documentation and durable instructions

Write one paragraph per physical Markdown line and regular links to other documents. The [README](README.md) serves users; [usage](docs/usage.md) owns controls, [architecture](docs/architecture.md) owns accepted contracts, [development](docs/development.md) owns repeatable checks/limits, and [PLAN.md](PLAN.md) owns unfinished work. Consult the [research index](docs/research/README.md) before investigating; extend the matching dated note and index new notes or retained measurements in the same commit. Keep evidence separate from open designs in [proposals](docs/proposals/README.md) and settled outcomes in [decisions](docs/decisions/README.md); every docs folder has a README index. Follow [documentation maintenance](docs/development.md#documentation-and-instruction-maintenance) for provenance and completion records.

Add root instructions only for recurring agent decisions or essential invariants. Put detailed feature contracts in their owning guide and link the task trigger here; do not accumulate a second feature specification in this file.

## Git and handback

Automatically commit completed, validated checkpoints with related documentation; leave unrelated work untouched. This overrides the global preference to only propose fix commits, but does not authorize pushing. Use Conventional Commits with a concise body when rationale is non-obvious. Never create or switch worktrees without explicit instructions. Keep build outputs, caches and temporary evaluations ignored.

PRs describe the problem, resulting behavior and validation, link applicable issues, and include screenshots for visible UI changes. Report material limitations and pending user checks without claiming unperformed validation.

# Repository instructions

Agent Monitor exists to reliably identify the coding agents and processes responsible for CPU and memory use on macOS. It provides text, JSONL, TUI and a maintained native menu bar app. `CLAUDE.md` is canonical; preserve the `AGENTS.md` symlink.

## Product priority

The number-one product question is: **which coding agents, sessions and processes are consuming CPU or memory, and in which working directories?** Every design decision must serve that answer across multiple contributors; Agent Monitor is not another top clone. The [product information contract](docs/product.md) defines the required identity and workload context. Measurement coverage and attribution correctness take precedence over low monitoring overhead, quiet defaults and presentation convenience. A busy agent workload that appears idle or substantially undercounted is a core product failure, even when the limitation is documented.

Coverage must work transparently with already-running agents; opt-in launch wrappers or cooperative worker hooks cannot substitute for that requirement.

Do not use display thresholds, refresh cadence or heavy-process-only totals as a substitute for accounting for agent work. Filters may simplify inspection, but must not silently redefine an advertised agent/session total or hide a coverage gap. Evaluate short-lived and exited workers, below-threshold processes and memory as well as sustained CPU. Never manufacture completeness by assigning unattributed load to an agent or calling the difference from host usage “system load”; preserve unknown ownership and missing measurements explicitly.

These are acceptance priorities, not claims that the current sampler meets them. Read the [resource visibility requirements](docs/architecture.md#resource-visibility-requirements) and the [active accounting work](PLAN.md#resource-accounting-priority) before measurement, filtering or aggregation changes. Display cadence is independent of acquisition: coalesce unique CPU contributions rather than discarding intermediate snapshots. Resource threshold filters default off and observed totals must remain independent of them. The [contributor overview](docs/architecture.md#contributor-overview-and-recent-activity) may collapse lower contributors only into a quantified remainder that preserves population counts, resource totals and uncertainty. Polling gaps and final exit CPU remain accounting limitations.

## UX priority

Provide a clear, actionable resource overview under stress. Keep agent/session identity, workload CWD, executable and contribution understandable together; directory summaries cannot replace session identity. Prefer compact aligned tables and meaningful graphics, with structured disclosure and contextual verified actions. Put explanations and arguments on demand, not in diagnostic paragraphs. Apply the [user-first presentation rules](docs/development.md#user-first-presentation): lead with the user’s decision, establish visual hierarchy and use progressive disclosure rather than exposing the internal data model. Apply the [accepted ledger design](docs/architecture.md#constrained-overview-presentation): full-width workload context, comparable activity lanes and structured details; do not reintroduce competing overview layouts. Keep material coverage gaps visible. Native SwiftUI/AppKit and terminal conventions guide interaction; iStat Menus and htop/btop are references, not a reason to lose the agent/session focus. Review Mac and TUI against the [product contract](docs/product.md) before accepting presentation changes.

For UI/UX recommendations, design, implementation and review, use the repository-owned [monitor-ui-ux skill](skills/monitor-ui-ux/SKILL.md) and the applicable [Mac/TUI review procedure](docs/development.md#resource-overview-ux-review). This is required even for advice without code changes; view-refactoring and performance skills do not substitute for interaction design. If host discovery fails, read the tracked skill directly. Maintain the procedure with accepted UX changes and demonstrated failures, and keep unfinished corrections in PLAN rather than claiming the interface already complies.

**High priority: concise UI text in both Mac and TUI.** Tooltips and contextual hints answer one immediate question in one short phrase; never reuse diagnostic paragraphs as hover text. Keep essential state visible and fuller explanations on demand. Apply the [user-first presentation rules](docs/development.md#user-first-presentation) before adding or changing any UI text.

Before recommending a UI framework or control, check the current platform's standard controls against the actual interaction requirements using the installed SDK or official documentation. For Mac content, evaluate SwiftUI first, including hierarchical `Table` for multi-column trees. Recommend AppKit or custom controls only with a specific demonstrated limitation or an established repository ownership requirement; unfamiliarity is not evidence of a limitation. Preserve AppKit's existing lifecycle ownership. Name the evidence and tradeoff in the recommendation, and leave unverified claims explicit.

Diagnostic recording defaults off. Normal monitoring retains bounded working state and rolling in-memory history only; never add automatic process-data persistence or an unbounded in-memory log. Recording requires explicit opt-in under its [separate proposal](docs/proposals/diagnostic-recording.md).

## Start and scope

Read [PLAN.md](PLAN.md) when resuming; it owns unfinished work and scope decisions. Process termination and adapter-based terminal focus are shipped capabilities, not permission to act on live workloads. Proposals do not authorize implementation. Read-only search and review subagents are allowed; the tier-based delegation of the [working-model proposal](docs/proposals/agent-working-model.md) is not adopted. Keep unrelated product expansion outside the current task.

Before changing a subsystem, read its relevant contract below; do not reread unrelated guides or material already current in this session. If code bypasses its documented ownership, make the smallest authorized extraction before extending it. Surface a material scope conflict rather than building on the bypass. Keep implementation, architecture status and contributor guidance aligned in the same commit.

For every reported issue, check Mac, TUI, text CLI and JSON, even when the user supplies only a Mac screenshot. Trace the shared behavior and verify each affected surface; fix applicable instances together. Report surfaces that are unaffected or have no corresponding feature, with the reason. Use platform-appropriate interactions rather than copying native controls into terminal or machine output. Unrelated feature expansion still needs its own scope decision. Follow the [cross-interface issue review](docs/development.md#cross-interface-issue-review).

Do not fork or vendor-patch SwiftTUI; preserve the user's [dependency decision](docs/decisions/swifttui-fork.md).

## Ownership and essential invariants

Agent Monitor must not initiate Internet connections, directly or through helpers it launches. A local-looking provider command or a flag disabling nonessential traffic is not an offline guarantee. Do not add or approve a helper path without establishing how Internet access is prevented; surface unavailable attribution/actions instead of silently violating this requirement. This runtime rule applies to Mac, TUI and CLI; it does not prohibit development-time documentation lookup or dependency installation. The [offline runtime contract](docs/architecture.md#offline-runtime) defines the fail-closed provider paths and unavailable capabilities.

| Target under `Sources/` | Owns |
| --- | --- |
| `AgentMonitorCore` | Native sampling, lifetimes, attribution and UI-independent snapshots; no UI or Argument Parser dependencies. |
| `AgentMonitor` | CLI arguments and output selection; Argument Parser stays in CLI targets. |
| `AgentMonitorPresentation` | Neutral grouping, selection, disclosure, pins, history and action-review state. |
| `AgentMonitorTUI` | SwiftTUI rendering and terminal input. |
| `AgentMonitorActions` | Verified termination and terminal-focus adapters. |
| `AgentMonitorMenuBar` | AppKit lifecycle and SwiftUI presentation; reuse shared services, never SwiftTUI. |

Harness-specific recognition, marker validation, descriptor/inbox interpretation and runtime classification belong in [attribution adapters](Sources/AgentMonitorCore/AttributionAdapters/). Hosts own native access, allowlisting and command execution; adapters declare and interpret observations. Never add provider heuristics to the sampler, reader, parser, models or UI. Preserve all recognition claims and uncertainty; adapter order cannot select an owner. Terminal focus uses separate action adapters.

Use exact process lifetimes, not PID alone. Never infer ownership from cwd or treat a protocol process handle as an OS PID. Grouping preserves provider/session identity and leaves JSONL flat; [observed session totals](docs/architecture.md#current-implementation) include filtered members and must stay qualified for missed observations. Project labels use workload directories, never a shared runtime's launch directory. Shared presentation owns sticky disclosure without stale measurements or overriding explicit inspection changes.

Actions require frozen identity, fresh same-user/target verification and explicit confirmation where applicable. Acceptance is not delivery or completion; never automatically retry uncertain actions. Never read transcripts or a Claude messaging token. Tests and research probes use fake providers and disposable owned processes, never real harness listings, live messages or signals to user workloads; keep a probe script only when its measurement is retained.

## Read only the contracts relevant to the change

| Change | Required guidance |
| --- | --- |
| Attribution, provider or native observation | [Harness contracts](docs/architecture.md#agent-attribution-adapters), [adapter checks](docs/development.md#changing-attribution-adapters). |
| Grouping, disclosure or snapshot semantics | [Presentation boundaries](docs/architecture.md#boundary-for-multiple-presentations), [shared state](docs/architecture.md#current-implementation). |
| Actions or provider transports | [Action contract](docs/architecture.md#process-and-session-actions), [validation limits](docs/development.md#validation-coverage). |
| Native UI, input or lifecycle | [Native contract](docs/architecture.md#native-menu-bar-app), [headless checks and user smoke test](docs/development.md#menu-bar-app). |
| TUI or resource history | [TUI contract](docs/architecture.md#tui-contract), [history contract](docs/architecture.md#resource-history), [terminal checks](docs/development.md#terminal-and-machine-output-checks). |
| CLI options or JSONL | [Wire/presentation boundary](docs/architecture.md#boundary-for-multiple-presentations), [usage](docs/usage.md). Verify defaults, units and combinations against `Options.swift` and generated `--help`; update the README option table/examples and affected usage, including TUI's unlimited report default. |
| Research note, proposal or decision record | [Research index](docs/research/README.md), [proposal lifecycle and folder indices](docs/development.md#documentation-and-instruction-maintenance); change statuses with `python3 scripts/docs.py status`. |
| Rendered documentation | [Preview maintenance](docs/development.md#readme-preview), [native image generation](docs/development.md#build-and-coverage-details). |
| Dependencies, skills or packaging | [Dual-host skills](docs/development.md#skills-shared-by-codex-cli-and-claude-code), [release packaging](docs/releasing.md). Pin changes require [third-party notices](THIRD_PARTY_NOTICES.md) from locked sources, including vendored components/fonts; retain notices and licenses in archives. |

Use installed `swiftui-view-refactor` for native structure/dependency/Observation work and `swiftui-performance-audit` for rendering/refresh/scrolling investigations; keep the concurrency/testing skills available for matching work. If an optional skill is unavailable, follow the project guidance and report the limitation; do not install or upgrade merely to unblock routine work. See [skill setup and fallback](docs/development.md#skills-shared-by-codex-cli-and-claude-code). Performance suspicions remain hypotheses until measured.

## Implement and validate

Before v1.0, backward compatibility is not required. Prefer a coherent current design over compatibility layers, legacy output modes or migrations solely to preserve pre-1.0 behavior. Keep only the current formats and update schemas, tests and documentation together when contracts change. Do not retain old schema versions or add version bumps solely for pre-1.0 compatibility.

Use Xcode 27, Swift 6.4 and macOS 27. Follow four-space indentation, bundled `swift format`, Swift 6 concurrency checking and enum-based switches. Comments explain constraints and cite their basis. Use red/green TDD for behavior changes and descriptive Swift Testing tests; positive attribution fixtures must resolve exact sessions, not merely return unknown.

Select checks using the [validation matrix](docs/development.md#choose-checks-for-the-change). Headless validation is the default: deterministic core/presentation/model inputs, fake transports, controlled clocks and synthetic offscreen AppKit renders. Reuse production composition across layers. Computer Use is disabled; do not request or enable it for routine review. The user owns live macOS smoke tests, which remain pending until reported. Automated results cannot prove physical input delivery, menu anchoring or live provider delivery.

Common commands from the repository root:

- `swift build` and `swift test`: build and run the Swift suite; use `swift test --filter <Suite>` for focused red/green loops. Keep this POC lean: affected regressions and integration checks first; full suites are for broad refactors, release gates or explicit requests.
- `python3 scripts/docs.py check`: documentation links, anchors, folder indices and status tables; required for documentation-only commits.
- `swift format lint --strict --recursive Sources Tests Tools Package.swift`: formatting.
- `bash scripts/doctor.sh`: read-only prerequisites and instruction/skill checks.
- `bash scripts/preview.sh check`: generated TUI preview drift.
- `bash scripts/menubar.sh build`: optimized local bundle; `run` supplies shell PATH to transports.

Specialized native/terminal probes and restricted-environment workarounds are in the [development guide](docs/development.md). Do not run every probe for every change.

## Documentation and durable instructions

Design-study images must never be added to Git. Always reuse the ignored `.build/design-studies/` directory for studies and their supporting render files; save review images there as PNG files. Do not create alternative study directories or put study images in `docs/assets/`. Track only written findings and decisions in documentation; this rule has no approval exception.

Write one paragraph per physical Markdown line and regular links to other documents. The [product contract](docs/product.md) owns the central question and information requirements; the [README](README.md) serves users; [usage](docs/usage.md) owns controls, [architecture](docs/architecture.md) owns accepted contracts, [development](docs/development.md) owns repeatable checks/limits, and [PLAN.md](PLAN.md) owns unfinished work. Consult the [research index](docs/research/README.md) before investigating; extend the matching dated note and index new notes or retained measurements in the same commit. Keep evidence separate from open designs in [proposals](docs/proposals/README.md) and settled outcomes in [decisions](docs/decisions/README.md); every docs folder has a README index. Follow [documentation maintenance](docs/development.md#documentation-and-instruction-maintenance) for provenance and completion records.

Add root instructions only for recurring agent decisions or essential invariants. Put detailed feature contracts in their owning guide and link the task trigger here; do not accumulate a second feature specification in this file.

## Git and handback

Automatically commit completed, validated checkpoints with related documentation; leave unrelated work untouched. This overrides the global preference to only propose fix commits, but does not authorize pushing. Use Conventional Commits with a concise body when rationale is non-obvious. Never create or switch worktrees without explicit instructions. Keep build outputs, caches and temporary evaluations ignored. Run `python3 scripts/clean-build.py check` before handing back a build checkpoint; the build and doctor scripts run it too. Treat `.build` as disposable: retain durable measurements in indexed docs and remove large raw traces/exports after analysis; follow [artifact retention](docs/development.md#build-and-probe-artifact-retention).

PRs describe the problem, resulting behavior and validation, link applicable issues, and include screenshots for visible UI changes. Report material limitations and pending user checks without claiming unperformed validation.

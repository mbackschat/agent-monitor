# Development guidance

Build and change Agent Monitor from source. For everyday use, start with [installation](installation.md); for publication, use [releasing](releasing.md).

| Task | Guide |
| --- | --- |
| Select checks and build locally | [Build and verify](#build-and-verify) |
| Find an accounting, attribution, action or terminal regression | [Validation recipes](development/validation.md) |
| Review Mac or TUI interaction and presentation | [UI review](development/ui-review.md) |
| Build the Mac app or hand off a smoke test | [Native app](development/native-app.md) |
| Update documentation images | [Preview maintenance](development/previews.md) |
| Set up skills or resolve build/storage issues | [Tools and build hygiene](development/workflow.md) |
| Maintain docs and instructions | [Documentation policy](#documentation-and-instruction-maintenance) |

## Build and verify

### Choose checks for the change

Select checks by the behavior and artifacts affected, not by running every available probe. During implementation, use red/green tests for the changed behavior; before committing, run the affected suites and integration checks. For this POC, use focused regressions and affected integration checks even for bounded shared changes; reserve the full Swift suite for release gates, broad refactors or an explicit request.

Repeat checks only after relevant edits, failures or unresolved concerns. Batch related edits before integration validation; a new commit alone is not a reason to repeat a full suite or optimized build.

| Change | Required verification |
| --- | --- |
| Documentation or instructions only | `python3 scripts/docs.py check` (links, anchors, folder indices, status tables) and `git diff --check`; compare moved requirements with their old locations. Instruction-routing changes also warrant a fresh-context scenario check. No Swift build or live UI test unless executable examples or rendered assets changed. |
| Core, presentation or action behavior | Failing regression first, then affected Swift Testing suites; include exact positive and negative attribution/identity fixtures where relevant. Select the affected contract and integration tests; reserve the full suite for broad changes or release gates. |
| Native UI or lifecycle | Model/composition tests with fake services and controlled clocks; offscreen AppKit renders for affected visible states. For bundle/packaging changes, build and check the bundle. The user performs the [live smoke test](#manual-macos-smoke-test) when input, menu tracking, lifecycle or packaging is affected. |
| TUI layout, text or input | Affected layout and PTY tests; [preview checks](#readme-preview) when the generated fixture can change. Visually review style changes even when SVG bytes stay unchanged. |
| CLI flags, defaults or JSONL | Parser/help and encoded-schema tests; compare generated help with README/usage examples. CLI help-only text does not by itself require regenerating a TUI screenshot. |
| Native observation or provider transport | Retain adapter/action guards and fake transports; use the relevant controlled observation or read-only transport probe when that boundary changes. Live delivery/focus checks require appropriate disposable targets and authorization, not routine test-suite access to real sessions. |
| Dependencies, skills or release packaging | Pin/license checks and affected build/tests; skill changes also run the offline installer tests. Follow the [release guide](releasing.md) for release gates. |

### Build efficiently

Reuse the current backend, toolchain, SDK and Debug configuration. During interactive work, cap compilation at two jobs and batch related edits before validation.

`swift test --filter` filters execution, not necessarily compilation. Build the current test executable once; use `--skip-build` only while it still includes all relevant edits. Package the tested Debug executable for local UI review with `AGENT_MONITOR_BUILD_CONFIGURATION=debug bash scripts/menubar.sh build`. The bundle script reuses the backend named by the current product link and defaults to two jobs; `AGENT_MONITOR_BUILD_SYSTEM` and `AGENT_MONITOR_BUILD_JOBS` explicitly override these choices. Keep optimized builds for performance or delivery checkpoints. Never accumulate two backend trees after a fallback.

Use debug tests for red/green work. Build optimized products for a native integration, packaging, optimization-specific correctness or performance checkpoint, and run performance measurements against that optimized build. Always report the test configuration separately from the build configuration: a release build is not a release-mode test run. Save slow-command output once and inspect the same log. CI and release gates remain unchanged.

For a required full-suite run or a mixed native/PTY run, explicitly pass `--no-parallel`; `-j 2` limits compilation, not Swift Testing concurrency. CI and release preparation use the same serial policy. The [2026-11-01 Verify investigation](research/development-tools.md#verify-scheduling-and-native-ocr--2026-11-01) records the ownership scheduling failure and native runner prerequisites. Automated native checks use presentation values, layout, interaction and pixels rather than OCR. The corrected [hosted Verify run](https://github.com/mbackschat/agent-monitor/actions/runs/41266488353) passed the full suite and packaging checks.

### Available commands

Run selected commands from the repository directory:

```sh
bash scripts/doctor.sh
python3 scripts/docs.py check
swift test --no-parallel
swift format lint --strict --recursive Sources Tests Tools Package.swift
bash scripts/preview.sh check
swift build
python3 scripts/verify-poc.py "$(swift build --show-bin-path)/agent-monitor"
uv run scripts/verify-json-schema.py "$(swift build --show-bin-path)/agent-monitor"
```

The Swift Testing suite covers attribution, ambiguity, PID reuse, nested runtimes, parsing, thresholds, native measurement, action identity/routing guards, offline message refusal and bounded subprocess behavior. Action integration tests signal only a disposable `sleep` child; PTY tests use an injected fake action service. No test should queue messages to live agents or signal user workloads.

### Controlled integration fixture

The smoke check compiles a disposable Swift fixture and launches controlled terminal process trees. It checks exact session IDs, same-directory sessions, detached workers, a scrubbed-marker fallback, CPU normalization, footprint, and exclusion of a small worker.

An exited intermediate launcher leaves a marked worker under PID 1 while its Codex runtime keeps the thread writer descriptor open; the check requires the exact runtime and terminal context, independently of monitor history. It also verifies that a worker whose runtime exited retains only its marked session. It terminates only its own fixtures. Python 3 is needed for this development check, not for the monitor.

The [doctor](../scripts/doctor.sh) checks macOS, Swift, the active macOS SDK, Git, the canonical instruction symlink, and any installed project skills. It does not install dependencies or change configuration. Missing optional skills do not fail the check; an incomplete or modified installed skill setup does. It is a prerequisite check, not a replacement for building and testing.

## Toolchain and package

The PoC uses Swift 6 language mode with complete concurrency checking, a Swift 6.4 package manifest, and a macOS 27 deployment target. It was built with Xcode 27 on Apple Silicon. The installed Apple toolchain is sufficient; no Homebrew installation is required. Swift 6.4.1 is available upstream, but this PoC does not require changing the Xcode toolchain. [Swift 6.4 release](https://www.swift.org/blog/swift-6.4-released/), [Swift 6.4.1 announcement](https://forums.swift.org/t/announcing-swift-6-4-1/90029).

`AgentMonitorCore` owns native inspection, process-lifetime history, attribution, and threshold filtering. `AgentMonitor` uses Apple's Argument Parser for typed options, generated help, and validation; the dependency is pinned to 1.8.2 in [Package.swift](../Package.swift). The migration passed the Swift suite, release build, help/error/JSON checks, and controlled attribution fixtures. Preserve the generated [Package.resolved](../Package.resolved). The monitoring core has no package dependencies. [Argument Parser release](https://github.com/apple/swift-argument-parser/releases/tag/1.8.2).

The completed [SwiftTUI evaluation](research/terminal-ui.md) used version 0.14.0 and synthetic data; its temporary package/build directory has been removed. The monitor now declares the same official remote dependency, exactly pinned in [Package.swift](../Package.swift). It compiles and runs through the public `RunLoop`, avoiding the scene launcher’s discovery socket. See the [evaluation findings](research/terminal-ui.md#libraries-inspected).

The mutable monitor is an exclusively owned value in one sequential sampling loop. Models are `Sendable`; there is no shared mutable singleton, unchecked sendability, or UI actor dependency. The native acquisition thread owns monotonic deadlines with explicit interval-change and cancellation wake-ups; async-only test clocks use the shared scan operation through a cancellable async adapter. Native pointers are confined to the reader and buffer parser. Preserve those boundaries if adding a UI or parallel collection.

Use four-space indentation and the bundled `swift format`, configured in [.swift-format](../.swift-format). Add behavior-focused Swift Testing tests before implementing changes. Native integration tests should use real API observations; attribution tests should use deterministic process lifetimes and explicit expected session IDs.

## Changing attribution adapters

Provider-specific attribution rules live in [AttributionAdapters](../Sources/AgentMonitorCore/AttributionAdapters/), under the internal `AgentAttributionAdapter` contract. Add executable recognition, allowlisted marker keys and validation, runtime evidence decoding and exact detached links there. The registry wires built-ins into parsing, native observation and resolution. The core owns OS calls, process identities, ancestry and conflict resolution; presentation consumes results. Terminal focus remains a separate action capability; messaging is unavailable. The [architecture contract](architecture.md#agent-attribution-adapters) defines these boundaries and the deferred extension scope.

For a provider change, demonstrate the declared inputs and exact session result with deterministic adapter/monitor tests. Retain negative guards for unrelated executable shapes, multi-call invocation names, duplicate marker values, malformed IDs, overlapping recognition claims in both orders, and duplicate provider registration. Exercise detached matches through the shared enrichment path so polling and action lookup stay consistent. Provider-listing and listed-name scaffolding is absent; never run a real harness listing in tests. A synthetic adapter must work through that path without adding branches to the sampler, parser, model or UI. Use disposable native fixtures to verify changes to descriptor decoding or the observations requested from the OS.

The host retains only declared environment keys and bounds native reads; adapters never receive full environment buffers or read transcripts. Never add the Claude messaging token to an allowlist. New observation kinds require a concrete provider need, a bounded host implementation and a regression test; they do not justify general plugin infrastructure. A third provider or wire-contract change needs an explicit enum/schema decision rather than silently expanding the existing API.

Treat a mismatch between code and documented ownership as part of the change being reviewed. Reconcile it within the authorized scope, or report a material scope conflict before extending the bypass. Keep [CLAUDE.md](../CLAUDE.md), [architecture](architecture.md), the user-facing support claims and [PLAN.md](../PLAN.md) current in the same commit. Do not report a boundary as implemented until production consumers use it and the contract tests pass.

## Documentation and instruction maintenance

| Information | Canonical home and maintenance rule |
| --- | --- |
| Product question and information requirements | [Product contract](product.md); implementation gaps belong in PLAN, not claims of shipped UX. |
| User-facing purpose, features, quick start and support | [README](../README.md); detailed controls and examples belong in [usage](usage.md). |
| Accepted behavior and ownership | [Architecture](architecture.md); update alongside code. Keep source ownership, contributor guidance and implemented/deferred status aligned rather than leaving accepted contracts as proposals. |
| Build/check recipes and coverage limits | This guide. Release-specific evidence belongs in the GitHub release notes drafted by [releasing](releasing.md), not an append-only validation log. |
| Unfinished work and decisions | [PLAN.md](../PLAN.md); remove completed entries once their durable outcome is documented. Do not use it as a completed-task log. |
| Dated observations and source evidence | [Research](research/README.md); consult the index first, extend the matching note and index new notes or retained measurements in the same commit. Preserve source/version provenance and uncertainty; editorial edits do not revalidate sources. Keep unique measurements beside their research data. Label inferences and unresolved empirical questions; exclude implementation plans, task lists, effort estimates and product-scope declarations. |
| Open designs | [Proposals](proposals/README.md), holding only **unapproved**, **approved** (authorized scope, with delivery or acceptance still open) or **on hold** designs. An unapproved proposal does not authorize implementation; proposal status alone is not a claim that the design has shipped. Each starts with `# Title` and `Status: **keyword**, YYYY-MM-DD. …`, links its evidence in research instead of embedding it, follows the global proposal structure (required, optional and excluded functionality; typed examples; material risks) and has a [PLAN.md](../PLAN.md) entry while open. |
| Settled decisions that were not implemented | [Decisions](decisions/README.md), holding **deferred**, **rejected** or **superseded** records with their reason and conditions for reconsideration, so settled questions are not reopened without new evidence. |
| Proposal retirement | Move implemented contracts into [architecture](architecture.md) in the implementing commit. Retire the proposal and remove its PLAN entry only when its authorized scope and acceptance work are closed; then either delete it or `git mv` it into decisions reduced to its deferred remainder. When deferred, rejected or superseded as a whole, `git mv` it into decisions with that status. Git history keeps the full proposal text. |
| Folder indices and status | Every folder under `docs/` except `assets/` has a README index linking each document; proposals and decisions carry a status table generated from the documents' `Status:` lines. Index entries carry the date that explains them: the date evidence was checked for research, and the date of the current status for proposals and decisions. Change a status only with `python3 scripts/docs.py status <file> <keyword>`, run `python3 scripts/docs.py sync` after adding, moving or retitling a status document, and never edit the generated table by hand. `python3 scripts/docs.py check` enforces links, anchors, indices, dates, status vocabularies and tables in CI. |
| Recurring agent decisions and essential invariants | [CLAUDE.md](../CLAUDE.md), exposed through the canonical [AGENTS.md](../AGENTS.md) symlink. Route subsystem changes to specific contracts instead of duplicating detailed feature specifications. |

### Write for the reader’s task

Organize human-facing documentation by audience and task. Give each paragraph one coherent concept, with one paragraph per physical Markdown line. Use headings for distinct questions, tables for comparisons and task-oriented lists for independently navigable entries. A long source line is not a reason to combine unrelated information.

Before appending to an overloaded section, rewrite it or split it into focused sections or a companion guide. Keep a useful entry point in the owning guide and link to specialist detail. Preserve normative requirements, commands, evidence, provenance and limitations when moving content; compare the old and new locations before deleting repetition. Review readability and retrieval in context rather than enforcing an arbitrary word limit.

Documentation checks skip Git-ignored generated output, including staged release bundles. Links from repository documents to ignored targets still fail. Documentation links must work without optional local installations. Cite pinned upstream skill files instead of their local discovery symlinks; the link checker rejects Git-ignored targets, including resolved symlink destinations, even when they exist locally.

For instruction restructuring, compare every removed requirement with its destination or an existing equivalent before deleting repetition. Preserve global/project overrides and live-action restrictions. A fresh sub-agent with no conversation history can check discoverability and interpretation against representative tasks; this does not establish automatic loading in a newly launched Codex or Claude host. Keep validation output temporary and report its scope, rather than creating another completed-check log.

## Specialist procedures

Choose the relevant procedure; these are focused references, not an additional checklist to run in full.

| Procedure | When to use it |
| --- | --- |
| <a id="supplemental-inspection-guards"></a>[Supplemental inspection guards](development/validation.md#supplemental-inspection-guards) | Select fake-reader/clock tests for inspection admission, counter conservation, carried observations and synthetic workload coverage. |
| <a id="adaptive-acquisition-guards"></a>[Adaptive acquisition guards](development/validation.md#adaptive-acquisition-guards) | Select controller, production-conservation, wire, native and PTY guards; keep native savings and live scheduling claims separate. |
| <a id="keep-tests-useful"></a>[Keep tests useful](development/validation.md#keep-tests-useful) | Retain independent failure oracles, remove redundant mirrors and establish async readiness before claiming progress. |
| <a id="on-demand-workload-recording"></a>[On-demand workload recording](development/validation.md#on-demand-workload-recording) | Use the recording playbook only on explicit request; synthetic recorder/analyzer checks require no live workload. |
| <a id="validation-coverage"></a>[Validation coverage](development/validation.md#validation-coverage) | Distinguish attribution, accounting, rendered geometry and physical interaction evidence; keep known coverage gaps visible. |
| <a id="terminal-and-machine-output-checks"></a>[Terminal and machine-output checks](development/validation.md#terminal-and-machine-output-checks) | Run owned PTY journeys and synthetic report/diagnosis schema validation. Live terminal and sustained observations have separate scope. |
| <a id="resource-overview-ux-review"></a>[Resource overview UX review](development/ui-review.md) | Review the product question with simultaneous contributors before choosing platform controls. Load monitor-ui-ux first. |
| <a id="user-first-presentation"></a>[User-first presentation](development/ui-review.md#user-first-presentation) | Lead with the user’s decision, keep UI text concise and use progressive disclosure without hiding material uncertainty. |
| <a id="cross-interface-issue-review"></a>[Cross-interface issue review](development/ui-review.md#cross-interface-issue-review) | Trace each issue across Mac, TUI, text CLI and JSON; explain unaffected surfaces as well as verifying affected ones. |
| <a id="shared-information-and-diagnostics"></a>[Shared information and diagnostics](development/ui-review.md#shared-information-and-diagnostics) | Check identity, workload context, resource populations, uncertainty and the accepted ledger design together. |
| <a id="mac-interaction-review"></a>[Mac interaction review](development/ui-review.md#mac-interaction-review) | Review selection, disclosure, sorting, actions, keyboard routing, focus, resizing and light/dark hierarchy. |
| <a id="tui-interaction-review"></a>[TUI interaction review](development/ui-review.md#tui-interaction-review) | Review cell geometry, selection, paging, hierarchy, Help, charts, summary alignment and monochrome behavior. |
| <a id="evidence-and-maintenance"></a>[Evidence and maintenance](development/ui-review.md#evidence-and-maintenance) | Separate demonstrated defects, recommendations, checked evidence and pending physical checks; maintain the owning contracts. |
| <a id="menu-bar-app"></a>[Menu bar app](development/native-app.md) | Build and validate the maintained source-built Mac app. Headless checks are the default; physical interaction remains user-owned. |
| <a id="default-headless-validation"></a>[Default headless validation](development/native-app.md#default-headless-validation) | Use injected services and clocks, production composition and owned offscreen windows. Native checks require no OCR. |
| <a id="manual-macos-smoke-test"></a>[Manual macOS smoke test](development/native-app.md#manual-macos-smoke-test) | Hand off the open/menu/keyboard/detach/quit journey after native integration changes; keep it pending until the user reports results. |
| <a id="manual-tui-workflow-check"></a>[Manual TUI workflow check](development/native-app.md#manual-tui-workflow-check) | Check actual terminal key delivery and navigation at narrow and wide sizes; source and PTY checks do not prove every keyboard mapping. |
| <a id="manual-terminal-focus-check"></a>[Manual terminal-focus check](development/native-app.md#manual-terminal-focus-check) | Use disposable Terminal.app tabs for the remaining activation/Space/window cases; fake adapters do not establish desktop delivery. |
| <a id="build-and-coverage-details"></a>[Build and coverage details](development/native-app.md#build-and-coverage-details) | Find bundle commands, opt-in row/grouping/collection probes, their evidence limits and native image-generation guidance. |
| <a id="readme-preview"></a>[README preview](development/previews.md) | Regenerate the deterministic TUI SVG when its fixture changes. Update the Mac panel WebP only during release preparation. |
| <a id="skills-shared-by-codex-cli-and-claude-code"></a>[Skills shared by Codex CLI and Claude Code](development/workflow.md#skills-shared-by-codex-cli-and-claude-code) | Use the tracked UX skill and optional pinned upstream skills through identical project-local discovery paths for both hosts. |
| <a id="restricted-agent-environments"></a>[Restricted agent environments](development/workflow.md#restricted-agent-environments) | Apply cache, backend or symbol-generation workarounds only to diagnosed failures; unavailable process fields do not justify Full Disk Access. |
| <a id="build-and-probe-artifact-retention"></a>[Build and probe artifact retention](development/workflow.md#build-and-probe-artifact-retention) | Keep active products, clean owned disposable outputs when idle and retain only approved durable evidence in indexed research. |
| <a id="recent-overview-checks"></a>[Recent overview checks](development/validation.md#recent-overview-checks) | Check immutable categories, membership, history capacity and native/PTY overview composition. |
| <a id="simultaneous-ownership-checks"></a>[Simultaneous ownership checks](development/validation.md#simultaneous-ownership-checks) | Exercise coexisting report, metadata, diagnosis and history holders; distinguish logical charges from allocator observations. |
| <a id="acquisition-review-guards"></a>[Acquisition review guards](development/validation.md#acquisition-review-guards) | Check compact-accounting conservation, deadline/wake behavior, argument reads and opt-in pipeline counters. |
| <a id="on-demand-argument-inspection-checks"></a>[On-demand argument inspection checks](development/validation.md#on-demand-argument-inspection-checks) | Verify explicit-only reads, one in-flight request, lifetime matching and late-result rejection. |
| <a id="contributor-information-checks"></a>[Contributor information checks](development/validation.md#contributor-information-checks) | Keep information separate from folding, preserve exact targets and close filtered inspection safely. |
| <a id="embedded-workload-labels"></a>[Embedded workload labels](development/validation.md#embedded-workload-labels) | Verify adapter labels and exact sessions survive category collapse and capacity pressure. |
| <a id="accounting-row-projection"></a>[Accounting row projection](development/validation.md#accounting-row-projection) | Compare cached and uncached ownership, ordering, action markers and storage charges. |
| <a id="native-executable-claim-reuse"></a>[Native executable-claim reuse](development/validation.md#native-executable-claim-reuse) | Check recognition reuse, withdrawal, UTF-8 identity and adapter-order independence. |
| <a id="completion-regression-guards"></a>[Completion regression guards](development/validation.md#completion-regression-guards) | Check environment preparation, history leases, compact labels and departed-runtime storage. |

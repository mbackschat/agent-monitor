# Development guidance

## Build and verify

For everyday CLI use, follow the [installation guide](installation.md). The commands here are for working on the source code.

For downloadable archives and GitHub publication, follow the [release guide](releasing.md).

Run these commands from the repository directory:

```sh
bash scripts/doctor.sh
swift test
swift format lint --strict --recursive Sources Tests Tools Package.swift
bash scripts/preview.sh check
swift build
python3 scripts/verify-poc.py "$(swift build --show-bin-path)/agent-monitor"
uv run scripts/verify-json-schema.py "$(swift build --show-bin-path)/agent-monitor"
```

The Swift Testing suite covers attribution, ambiguity, PID reuse, nested runtimes, parsing, thresholds, native measurement, action identity/routing guards, a fake Codex protocol server and bounded subprocess behavior. Action integration tests signal only a disposable `sleep` child; PTY tests use an injected fake action service. No test should queue messages to live agents or signal user workloads. The smoke check compiles a disposable Swift fixture and launches controlled terminal process trees. It checks exact session IDs, same-directory sessions, detached workers, a scrubbed-marker fallback, CPU normalization, footprint, and exclusion of a small worker. An exited intermediate launcher leaves a marked worker under PID 1 while its Codex runtime keeps the thread writer descriptor open; the check requires the exact runtime and terminal context, independently of monitor history. It also verifies that a worker whose runtime exited retains only its marked session. It terminates only its own fixtures. Python 3 is needed for this development check, not for the monitor.

The [doctor](../scripts/doctor.sh) checks macOS, Swift, the active macOS SDK, Git, the canonical instruction symlink, and any installed project skills. It does not install dependencies or change configuration. Missing optional skills do not fail the check; an incomplete or modified installed skill setup does. It is a prerequisite check, not a replacement for building and testing.

## Validation coverage

Release-specific checks belong in the [release notes](releases/0.2.2.md#license-and-verification); the commands above and [terminal checks](#terminal-and-machine-output-checks) reproduce automated coverage. The following live evidence was collected on Apple Silicon, macOS 27.0.1 and Swift 6.4 on 2026-10-14–15. It does not establish compatibility with other systems or provider versions.

| Area | Evidence and remaining limits |
|---|---|
| Session attribution | A real heavy child of native Claude Code matched independent provider metadata, runtime lifetime and stdin TTY; see [retained measurements](research/README.md#retained-measurements). Real terminal Codex heavy workloads and npm-based Claude installations remain unvalidated. Shared nonterminal Codex workloads and synthetic terminal fixtures do not close that gap. |
| Codex messaging | A read-only production-adapter probe verified recipient lookup against Codex CLI 0.162.1 using the app-server proxy's WebSocket transport, without requesting transcript turns. Live child-recipient routing and actual queue delivery remain untested; protocol and routing tests use fake providers. |
| Claude messaging | The production action path delivered a peer message to one approved disposable Claude Code 2.1.300 session, which answered in a new turn. See the [transport check](research/claude-session-messaging.md#live-transport-check-2026-10-14) for the undocumented line format, receiver controls and platform-binary environment limitation. |
| Terminal focus | The user confirmed Terminal.app tab selection on 2026-10-15. Other window/Space states and the first Automation prompt remain the open manual gate in [PLAN.md](../PLAN.md#open-follow-ups). Automated tests use fake adapters and do not drive real terminals. |
| Sustained operation | A bounded ten-minute headless watch with process churn showed no sustained footprint growth. The [dated measurements](research/README.md#retained-measurements) are not an hours-long leak guarantee, larger-population benchmark or sustained TUI measurement. |

Sampling can miss short-lived work, and CPU needs two observations. Missing readable markers can leave detached processes unknown; launch-origin attribution does not establish which client caused a shared daemon's current load.

The report table's character-based sizing can misalign wide Unicode names; this is tracked in [PLAN.md](../PLAN.md#open-follow-ups).

PTY screen checks have occasionally timed out in development; passing retries did not establish the cause. Retain failed-run evidence when investigating timing failures.

## Manual terminal-focus check

With disposable Terminal.app tabs, check selection in a background window, minimized window, another Space, full screen, and when monitor and target share a window. Record which activation route macOS honors and the first Automation prompt, including the controller named by the prompt. Tab selection was user-confirmed on 2026-10-15; these remaining cases are tracked in [PLAN.md](../PLAN.md#open-follow-ups). Fake-adapter tests do not verify desktop activation. The [terminal research](research/terminal-focus.md) explains the platform limits.

## README preview

The [preview script](../scripts/preview.sh) builds the development-only `monitor-preview` target. Its [synthetic fixture](../Tools/Preview/Fixture.swift) feeds the production `LiveReportState` and `LiveReportLayout`; the [SVG generator](../Tools/Preview/Preview.swift) adds illustrative terminal decoration. It never samples processes or reads agent sessions. Fixed identities, measurements, time, update count, and a 120 × 19 viewport make the output reproducible.

```sh
bash scripts/preview.sh update
bash scripts/preview.sh check
```

`update` replaces [the SVG shown in README](assets/tui-preview.svg). Open it in a browser, inspect spacing, clipping, and legibility, and commit it alongside the TUI change. `check` regenerates in memory and compares bytes; missing or different output fails with the update command and leaves the asset untouched. Run it after changing presentation, grouping, details, labels, or the fixture. Never hand-edit the generated SVG. README embeds SVG directly, so there is no second PNG to synchronize and no converter or font package to install. Browser font appearance can vary; the asset's cell geometry and generated bytes are deterministic.

The generator places each visible character at its terminal-cell coordinate and leaves spaces as gaps. Do not fit whole rows with SVG `textLength` or `lengthAdjust`: glyph scaling can distort the font, and collapsed whitespace can change the apparent column widths. Keep the fixed-cell regression tests and check the image in an isolated headless browser; a converter rendering alone does not establish browser compatibility. Use a fresh temporary profile, never an existing user browser or profile. Headless Chrome with `--disable-gpu --run-all-compositor-stages-before-draw` successfully rendered the published SVG during verification; GPU-backed capture was blank in this environment.

[CI](../.github/workflows/verify.yml) runs on every pull request, main push, and manual dispatch, avoiding path filters that could miss a new dependency. It runs the Swift suite, formatting, preview check, and offline skill-installer tests. The [Xcode 27 runner](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md) supplies the required macOS SDK and Swift toolchain; the workflow selects Xcode 27.0 explicitly. No skill download is needed for CI. A stale preview fails the check; CI does not rewrite or commit assets. Requiring the check before merges is a separate repository branch-rule setting.

[Preview tests](../Tests/PreviewTests/PreviewTests.swift) exercise missing/stale asset detection, XML escaping, and process/session layouts at 60, 85, 120, and 160 columns. The preview represents one illustrative state, not every interaction or exact terminal theme. Keep the existing layout and PTY tests, and review style-only TUI changes visually even if the SVG bytes do not change. `monitor-preview` is not part of the installed CLI or release archive.

## Toolchain and package

The PoC uses Swift 6 language mode with complete concurrency checking, a Swift 6.4 package manifest, and a macOS 27 deployment target. It was built with Xcode 27 on Apple Silicon. The installed Apple toolchain is sufficient; no Homebrew installation is required. Swift 6.4.1 is available upstream, but this PoC does not require changing the Xcode toolchain. [Swift 6.4 release](https://www.swift.org/blog/swift-6.4-released/), [Swift 6.4.1 announcement](https://forums.swift.org/t/announcing-swift-6-4-1/90029).

`AgentMonitorCore` owns native inspection, process-lifetime history, attribution, and threshold filtering. `AgentMonitor` uses Apple's Argument Parser for typed options, generated help, and validation; the dependency is pinned to 1.8.2 in [Package.swift](../Package.swift). The migration passed the Swift suite, release build, help/error/JSON checks, and controlled attribution fixtures. Preserve the generated [Package.resolved](../Package.resolved). The monitoring core has no package dependencies. [Argument Parser release](https://github.com/apple/swift-argument-parser/releases/tag/1.8.2).

The completed [SwiftTUI evaluation](research/terminal-ui.md) used version 0.14.0 and synthetic data; its temporary package/build directory has been removed. The monitor now declares the same official remote dependency, exactly pinned in [Package.swift](../Package.swift). It compiles and runs through the public `RunLoop`, avoiding the scene launcher’s discovery socket. See the [evaluation findings](research/terminal-ui.md#libraries-inspected).

The mutable monitor is an exclusively owned value in one sequential sampling loop. Models are `Sendable`; there is no shared mutable singleton, unchecked sendability, or UI actor dependency. The async loop uses cancellable sleep. Native pointers are confined to the reader and buffer parser. Preserve those boundaries if adding a UI or parallel collection.

Use four-space indentation and the bundled `swift format`, configured in [.swift-format](../.swift-format). Add behavior-focused Swift Testing tests before implementing changes. Native integration tests should use real API observations; attribution tests should use deterministic process lifetimes and explicit expected session IDs.

## Changing attribution adapters

Provider-specific attribution rules live in [AttributionAdapters](../Sources/AgentMonitorCore/AttributionAdapters/), under the internal `AgentAttributionAdapter` contract. Add executable recognition, allowlisted marker keys and validation, runtime evidence decoding and exact detached links there. The registry wires built-ins into parsing, native observation and resolution. The core owns OS calls, process identities, ancestry and conflict resolution; presentation consumes results. Messaging and terminal focus remain separate action capabilities. The [architecture contract](architecture.md#agent-attribution-adapters) defines these boundaries and the deferred extension scope.

For a provider change, demonstrate the declared inputs and exact session result with deterministic adapter/monitor tests. Retain negative guards for unrelated executable shapes, duplicate marker values, malformed IDs, overlapping recognition claims in both orders, and duplicate provider registration. Exercise detached matches through the shared enrichment path so polling and action lookup stay consistent. A synthetic adapter must work through that path without adding branches to the sampler, parser, model or UI. Use disposable native fixtures to verify changes to descriptor decoding or the observations requested from the OS.

The host retains only declared environment keys and bounds native reads; adapters never receive full environment buffers or read transcripts. Never add the Claude messaging token to an allowlist. New observation kinds require a concrete provider need, a bounded host implementation and a regression test; they do not justify general plugin infrastructure. A third provider or wire-contract change needs an explicit enum/schema decision rather than silently expanding the existing API.

Treat a mismatch between code and documented ownership as part of the change being reviewed. Reconcile it within the authorized scope, or report a material scope conflict before extending the bypass. Keep [CLAUDE.md](../CLAUDE.md), [architecture](architecture.md), the user-facing support claims and [PLAN.md](../PLAN.md) current in the same commit. Do not report a boundary as implemented until production consumers use it and the contract tests pass.

## Skills shared by Codex CLI and Claude Code

**Every project skill must work with both hosts.** A canonical skill directory must include its `SKILL.md`, referenced resources, and license. Expose the same directory under both `.agents/skills/<name>` and `.claude/skills/<name>` through relative symlinks. Verify both paths resolve to the same file and that every relative reference exists. Do not duplicate the skill contents or silently rely on host-specific hooks, subagents, permission settings, or MCP tool names.

The skills below are installed project-locally. Both hosts' discovery paths resolve to the same skill files; referenced resources and upstream licenses are retained. The concurrency/testing skills were installed on 2026-10-14 and discovered by both hosts in live sessions. The SwiftUI skills were installed and tried in a code review on 2026-10-15; filesystem discovery was verified for both hosts, but a fresh Claude catalog was not observed. Nothing was installed globally. Exact source revisions are recorded in [skills.lock](../skills.lock).

- [AvdLee Swift Concurrency](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill): inspect actual language/isolation settings, prefer explicit ownership and structured lifetimes, and avoid blanket `@MainActor` or unchecked concurrency escapes. [Skill source](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill/blob/main/skills/swift-concurrency/SKILL.md).
- [AvdLee Swift Testing](https://github.com/AvdLee/Swift-Testing-Agent-Skill): use `@Test`, `#expect`, prerequisite `#require`, parameterized cases, and parallel-safe fixtures. [Skill source](https://github.com/AvdLee/Swift-Testing-Agent-Skill/blob/main/swift-testing-expert/SKILL.md).
- [SwiftUI View Refactor](https://github.com/steipete/agent-scripts/blob/9989fe852a3f63f3933a1bdc20b4a25321240759/skills/swiftui-view-refactor/SKILL.md): use for native view structure, explicit dependencies and Observation review. Preserve our AppKit-owned model and shared service boundaries; its preference for view-owned orchestration is guidance, not a replacement architecture.
- [SwiftUI Performance Audit](https://github.com/steipete/agent-scripts/blob/9989fe852a3f63f3933a1bdc20b4a25321240759/skills/swiftui-performance-audit/SKILL.md): use for refresh/scrolling overhead, broad invalidation, identity and layout investigations. Start with code evidence and use traces before claiming a measured bottleneck or improvement. Both SwiftUI skills are distributed by Peter Steinberger's `agent-scripts` and credit Dimillian's collection.

Explicit requests can name the skill: “Use swiftui-view-refactor to review the menu bar views while preserving lifecycle ownership,” or “Use swiftui-performance-audit to investigate refresh overhead.” Agents should also select them when the task fits. Apple interface guidance remains the design baseline; these skills do not replace macOS interaction/accessibility checks. The [first trial](research/development-tools.md#first-project-trial--2026-10-15) records their practical usefulness and limits.

To reproduce the installation on another computer, run the following from this repository in a network-enabled terminal:

```sh
bash scripts/skills.sh install
bash scripts/skills.sh check
```

[The setup script](../scripts/skills.sh) clones complete upstream repositories, including references and licenses, into ignored `.skill-sources/swift-concurrency/`, `.skill-sources/swift-testing-expert/` and `.skill-sources/agent-scripts/`. Both SwiftUI skills share the single `agent-scripts` checkout and lock entry. Only the selected skill directories are exposed through relative links under `.agents/skills/` and `.claude/skills/`, with identical files for both hosts. The installer does not apply upstream repository instructions, run upstream setup scripts, change global skill directories or install host-specific plugins/hooks. Skills become available to newly discovered sessions; restart an existing CLI if it does not refresh its catalog.

The first installation records exact commit IDs in `skills.lock`; subsequent installs reuse those revisions. Keep that lock file and both hosts' symlinks in version control. On another computer, run the install command again to populate the ignored source checkouts. To upgrade deliberately:

```sh
bash scripts/skills.sh update
bash scripts/skills.sh check
```

Updates fetch each upstream `main`, select its current commit, and refresh the lock. The script refuses dirty source checkouts, missing root licenses or conflicting discovery paths. Review the lock changes and upstream instructions before continuing agent work. `bash scripts/test-skills.sh` checks dual-host discovery, retained references/licenses, pinned reinstalls, shared-source upgrades and edit protection against disposable local Git repositories without contacting GitHub. Additional profiling helpers and app-release skills are not installed; distribution remains deferred.

## Restricted agent environments

SwiftPM may need workspace-local caches when the agent cannot write user Library directories. The development runs used `CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"` and SwiftPM's `--cache-path .build/cache --config-path .build/config --security-path .build/security --manifest-cache local --disable-sandbox` flags. These flags accommodate the enclosing agent sandbox; ordinary terminal use should start with the commands in the [README](../README.md).

In this agent environment, release linking succeeded but Swift Build's dSYM generation returned `Operation not permitted`. Building with `swift build -c release -debug-info-format none` completed successfully; this produces an optimized executable without a debug-symbol bundle. Keep ordinary debug builds for source-level debugging. No machine permissions or installed tools were changed for this workaround.

Do not request Full Disk Access merely because a process field is unavailable. Missing permissions, short-lived processes, and omitted environment entries are normal inspection outcomes and must remain visible in the model.

SwiftTUI’s 0.14.0 scene launcher attempts to bind a Unix discovery socket, rejected by this sandbox. The monitor uses its documented public `RunLoop`, `TerminalHost`, `InputReader`, and `SignalReader` instead. This single-screen terminal host needs no discovery service or permission changes. See the [runtime findings](research/terminal-ui.md#sandbox-compatible-terminal-host).


## Terminal and machine-output checks

`swift test` includes a real PTY journey using `monitor-tui-fixture`, a deterministic snapshot source exercising the production TUI adapter. The default test lookup uses `.build/debug/monitor-tui-fixture`; set `AGENT_MONITOR_TUI_FIXTURE` to an absolute binary path for another configuration. Tests cover refresh, sorting, stable disclosure, resize, Ctrl-C, and terminal restoration. The fixture is a development target, not part of the shipped CLI interface.

After `swift build -c release`, run `python3 scripts/verify-tui-terminal.py .build/release/agent-monitor` for live color, NO_COLOR and `--no-color`, signal cleanup, and short CPU measurements. Use `--fixture` with `.build/release/monitor-tui-fixture` to isolate rendering overhead from collection. SwiftPM compiles official dependency sources normally; no fork or manual SwiftTUI installation is required.

Run `uv run scripts/verify-json-schema.py .build/release/agent-monitor` to validate real JSONL records using the pinned development-only JSON Schema validator. Run `python3 scripts/verify-sustained.py .build/release/agent-monitor --output /tmp/agent-monitor-sustained.json` for a ten-minute watch with native footprint/CPU observations and controlled process churn. The latter records launch-origin findings only for heavy terminal Codex candidates; it does not read transcripts or generate agent work.

## Menu bar app

Build with `bash scripts/menubar.sh build`; the local ad-hoc bundle is `.build/Agent Monitor.app`. Use `bash scripts/menubar.sh run` to launch with the shell PATH, or `swift run agent-monitor-menubar` for direct executable development. The menu bar app is a maintained source-built feature. Its local bundle is not included in CLI release archives or Homebrew installation; distribution is deferred until the app is finished. It adds no third-party dependencies. CI builds the local app bundle and checks its property list and ad-hoc signature.

Run `swift test --filter AgentMonitorMenuBarTests` for lifecycle and fake-action coverage: no startup collection, close cancellation, stale-result rejection, sequential reopening, visible collection errors, frozen termination identity, explicit message review, root routing, uncertain-send handling and closed-panel action rejection. Draft tests cover dismissal during composition/review, fresh recipient preparation, explicit cancellation, failed target/recipient verification, protection against overwriting another draft and uncertain-send exclusion. Native layout tests bound process summaries to two lines at compact widths. Existing core/presentation/action tests continue to guard attribution, grouping and transport behavior. No test sends messages or signals live workloads.

For an opt-in grouping microbenchmark, run `MENUBAR_GROUPING_MEASUREMENT_PATH=/tmp/native-grouping.json swift test --filter measureNativeGroupingProjection`. It compares two reads with one local read of the production grouping getter across synthetic workloads. The output measures that expression only; it does not establish whole-app CPU usage or scrolling performance.

For an optional synthetic native render, set `MENUBAR_PREVIEW_PATH=/tmp/agent-monitor-menubar.png` when running the menu bar tests. The native hosting view is rendered offscreen; this does not validate menu bar anchoring, dismissal, keyboard focus or Automation. Inspect the output rather than treating successful image encoding as a visual oracle.

Remaining manual app checks: open/dismiss/reopen rapidly, scroll and expand long identities, compose/review/cancel, try terminal focus with disposable sessions, check provider command discovery and first Automation consent from the bundle. Use controlled owned fixtures for actual signal/send checks. Observe closed-panel CPU and wakeups for ten minutes separately from open sampling; cancellation tests establish task behavior, not a zero-energy claim. Production signing, Gatekeeper, installation/upgrades, login registration, multiple displays/Spaces and menu bar auto-hide remain unvalidated.

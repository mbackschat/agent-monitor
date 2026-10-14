# Development guidance

## Build and verify

For everyday CLI use, follow the [installation guide](installation.md). The commands here are for working on the source code.

For downloadable archives and GitHub publication, follow the [release guide](releasing.md).

Run these commands from the repository directory:

```sh
swift test
swift format lint --strict --recursive Sources Tests Package.swift
swift build
python3 scripts/verify-poc.py "$(swift build --show-bin-path)/agent-monitor"
uv run scripts/verify-json-schema.py "$(swift build --show-bin-path)/agent-monitor"
```

The Swift Testing suite covers attribution, ambiguity, PID reuse, nested runtimes, parsing, thresholds, and native measurement. The smoke check compiles a disposable Swift fixture and launches controlled terminal process trees. It checks exact session IDs, same-directory sessions, detached workers, a scrubbed-marker fallback, CPU normalization, footprint, and exclusion of a small worker. It terminates only its own fixtures. Python 3 is needed for this development check, not for the monitor.

## Toolchain and package

The PoC uses Swift 6 language mode with complete concurrency checking, a Swift 6.4 package manifest, and a macOS 27 deployment target. It was built with Xcode 27 on Apple Silicon. The installed Apple toolchain is sufficient; no Homebrew installation is required. Swift 6.4.1 is available upstream, but this PoC does not require changing the Xcode toolchain. [Swift 6.4 release](https://www.swift.org/blog/swift-6.4-released/), [Swift 6.4.1 announcement](https://forums.swift.org/t/announcing-swift-6-4-1/90029).

`AgentMonitorCore` owns native inspection, process-lifetime history, attribution, and threshold filtering. `AgentMonitor` uses Apple's Argument Parser for typed options, generated help, and validation; the dependency is pinned to 1.8.2 in [Package.swift](../Package.swift). The migration passed the Swift suite, release build, help/error/JSON checks, and controlled attribution fixtures. Preserve the generated [Package.resolved](../Package.resolved). The monitoring core has no package dependencies. [Argument Parser release](https://github.com/apple/swift-argument-parser/releases/tag/1.8.2).

The completed [SwiftTUI evaluation](research/terminal-ui.md) used version 0.14.0 and synthetic data; its temporary package/build directory has been removed. The monitor now declares the same official remote dependency, exactly pinned in [Package.swift](../Package.swift). It compiles and runs through the public `RunLoop`, avoiding the scene launcher’s discovery socket. See the [evaluation findings](research/terminal-ui.md#source-evaluation-and-local-status).

The mutable monitor is an exclusively owned value in one sequential sampling loop. Models are `Sendable`; there is no shared mutable singleton, unchecked sendability, or UI actor dependency. The async loop uses cancellable sleep. Native pointers are confined to the reader and buffer parser. Preserve those boundaries if adding a UI or parallel collection.

Use four-space indentation and the bundled `swift format`, configured in [.swift-format](../.swift-format). Add behavior-focused Swift Testing tests before implementing changes. Native integration tests should use real API observations; attribution tests should use deterministic process lifetimes and explicit expected session IDs.

## Skills shared by Codex CLI and Claude Code

**Every project skill must work with both hosts.** A canonical skill directory must include its `SKILL.md`, referenced resources, and license. Expose the same directory under both `.agents/skills/<name>` and `.claude/skills/<name>` through relative symlinks. Verify both paths resolve to the same file and that every relative reference exists. Do not duplicate the skill contents or silently rely on host-specific hooks, subagents, permission settings, or MCP tool names.

The following upstream skills were read and applied during this PoC and installed project-locally on 2026-10-14. Both hosts' discovery paths resolve to the same skill files; referenced resources and licenses are present. Codex has discovered both skills in this session. Nothing was installed globally. Exact installed revisions are recorded in [skills.lock](../skills.lock).

- [AvdLee Swift Concurrency](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill): inspect actual language/isolation settings, prefer explicit ownership and structured lifetimes, and avoid blanket `@MainActor` or unchecked concurrency escapes. [Skill source](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill/blob/main/skills/swift-concurrency/SKILL.md).
- [AvdLee Swift Testing](https://github.com/AvdLee/Swift-Testing-Agent-Skill): use `@Test`, `#expect`, prerequisite `#require`, parameterized cases, and parallel-safe fixtures. [Skill source](https://github.com/AvdLee/Swift-Testing-Agent-Skill/blob/main/swift-testing-expert/SKILL.md).

To reproduce the installation on another computer, run the following from this repository in a network-enabled terminal:

```sh
bash scripts/skills.sh install
bash scripts/skills.sh check
```

[The setup script](../scripts/skills.sh) clones complete upstream repositories, including references and licenses, into ignored `.skill-sources/swift-concurrency/` and `.skill-sources/swift-testing-expert/`. Relative links under `.agents/skills/` and `.claude/skills/` expose exactly the same skill files to Codex CLI and Claude Code. It does not change global skill directories or install host-specific plugins or hooks. Skills become available to newly discovered sessions; restart an existing CLI if it does not refresh its catalog.

The first installation records exact commit IDs in `skills.lock`; subsequent installs reuse those revisions. Keep that lock file and both hosts' symlinks in version control. On another computer, run the install command again to populate the ignored source checkouts. To upgrade deliberately:

```sh
bash scripts/skills.sh update
bash scripts/skills.sh check
```

Updates fetch each upstream `main`, select its current commit, and refresh the lock. The script refuses dirty source checkouts or conflicting discovery paths. Review the lock changes and upstream instructions before continuing agent work. `bash scripts/test-skills.sh` checks discovery, pinned reinstalls, upgrades, and edit protection against disposable local Git repositories without contacting GitHub. SwiftUI and app-packaging skills remain unnecessary for the headless PoC.

## Restricted agent environments

SwiftPM may need workspace-local caches when the agent cannot write user Library directories. The development runs used `CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"` and SwiftPM's `--cache-path .build/cache --config-path .build/config --security-path .build/security --manifest-cache local --disable-sandbox` flags. These flags accommodate the enclosing agent sandbox; ordinary terminal use should start with the commands in the [README](../README.md).

In this agent environment, release linking succeeded but Swift Build's dSYM generation returned `Operation not permitted`. Building with `swift build -c release -debug-info-format none` completed successfully; this produces an optimized executable without a debug-symbol bundle. Keep ordinary debug builds for source-level debugging. No machine permissions or installed tools were changed for this workaround.

Do not request Full Disk Access merely because a process field is unavailable. Missing permissions, short-lived processes, and omitted environment entries are normal inspection outcomes and must remain visible in the model.

SwiftTUI’s 0.14.0 scene launcher attempts to bind a Unix discovery socket, rejected by this sandbox. The monitor uses its documented public `RunLoop`, `TerminalHost`, `InputReader`, and `SignalReader` instead. This single-screen terminal host needs no discovery service or permission changes. See the [runtime findings](research/terminal-ui.md#sandbox-compatible-terminal-host).


## Terminal and machine-output checks

`swift test` includes a real PTY journey using `monitor-tui-fixture`, a deterministic snapshot source exercising the production TUI adapter. The default test lookup uses `.build/debug/monitor-tui-fixture`; set `AGENT_MONITOR_TUI_FIXTURE` to an absolute binary path for another configuration. Tests cover refresh, sorting, stable disclosure, resize, Ctrl-C, and terminal restoration. The fixture is a development target, not part of the shipped CLI interface.

After `swift build -c release`, run `python3 scripts/verify-tui-terminal.py .build/release/agent-monitor` for live color/NO_COLOR, signal cleanup, and short CPU measurements. Use `--fixture` with `.build/release/monitor-tui-fixture` to isolate rendering overhead from collection. SwiftPM compiles official dependency sources normally; no fork or manual SwiftTUI installation is required.

Run `uv run scripts/verify-json-schema.py .build/release/agent-monitor` to validate real JSONL records using the pinned development-only JSON Schema validator. Run `python3 scripts/verify-sustained.py .build/release/agent-monitor --output /tmp/agent-monitor-sustained.json` for a ten-minute watch with native footprint/CPU observations and controlled process churn. The latter records launch-origin findings only for heavy terminal Codex candidates; it does not read transcripts or generate agent work.

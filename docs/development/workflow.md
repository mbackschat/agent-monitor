# Development tools and build hygiene

Set up shared skills, handle diagnosed toolchain restrictions and keep build/probe outputs disposable. Ordinary source validation starts in the [development guide](../development.md#build-and-verify).

[Development guide](../development.md) · [All development references](README.md)

## Skills shared by Codex CLI and Claude Code

The repository-owned [monitor-ui-ux skill](../../skills/monitor-ui-ux/SKILL.md) is required for UI/UX advice, design, implementation and review in Mac or TUI. It is tracked with the project, uses the repository license and needs no download.

Both discovery paths link to `skills/monitor-ui-ux`; read that canonical source directly if the host has not refreshed its skill catalog. Update its routing when the owning contracts move, and update the [review procedure](ui-review.md) when accepted interaction requirements change. Skill validation and filesystem discovery do not establish that a fresh host has loaded it or that an interface is usable.

### Optional upstream skills

Upstream skills are optional development aids, not build/runtime dependencies. Use an installed skill when its documented task matches; if it is unavailable, follow the linked project contracts and state the limitation without blocking routine work. Install only for an explicit setup request or a task that actually needs the missing resource; do not install or upgrade merely because a symlink is absent. Do not install project skills globally.

On a fresh clone, upstream skill links remain unresolved until `install` populates ignored `.skill-sources/` at the locked revisions; missing optional skills differ from a broken installed setup, which the doctor reports as an error.

### Dual-host contract

**Every project skill must work with both hosts.** A canonical skill directory must include its `SKILL.md`, referenced resources, and license. Expose the same directory under both `.agents/skills/<name>` and `.claude/skills/<name>` through relative symlinks. Verify both paths resolve to the same file and that every relative reference exists. Do not duplicate the skill contents or silently rely on host-specific hooks, subagents, permission settings, or MCP tool names.

### Installed references

The skills below are installed project-locally. Both hosts' discovery paths resolve to the same skill files; referenced resources and upstream licenses are retained. The concurrency/testing skills were installed on 2026-10-14 and discovered by both hosts in live sessions. The SwiftUI skills were installed and tried in a code review on 2026-10-15; filesystem discovery was verified for both hosts, but a fresh Claude catalog was not observed. Nothing was installed globally. Exact source revisions are recorded in [skills.lock](../../skills.lock).

- [AvdLee Swift Concurrency](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill): inspect actual language/isolation settings, prefer explicit ownership and structured lifetimes, and avoid blanket `@MainActor` or unchecked concurrency escapes. [Skill source](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill/blob/main/skills/swift-concurrency/SKILL.md).
- [AvdLee Swift Testing](https://github.com/AvdLee/Swift-Testing-Agent-Skill): use `@Test`, `#expect`, prerequisite `#require`, parameterized cases, and parallel-safe fixtures. [Skill source](https://github.com/AvdLee/Swift-Testing-Agent-Skill/blob/main/swift-testing-expert/SKILL.md).
- [SwiftUI View Refactor](https://github.com/steipete/agent-scripts/blob/9989fe852a3f63f3933a1bdc20b4a25321240759/skills/swiftui-view-refactor/SKILL.md): use for native view structure, explicit dependencies and Observation review. Preserve our AppKit-owned model and shared service boundaries; its preference for view-owned orchestration is guidance, not a replacement architecture.
- [SwiftUI Performance Audit](https://github.com/steipete/agent-scripts/blob/9989fe852a3f63f3933a1bdc20b4a25321240759/skills/swiftui-performance-audit/SKILL.md): use for refresh/scrolling overhead, broad invalidation, identity and layout investigations. Start with code evidence and use traces before claiming a measured bottleneck or improvement. Both SwiftUI skills are distributed by Peter Steinberger's `agent-scripts` and credit Dimillian's collection.

Explicit requests can name the skill: “Use swiftui-view-refactor to review the menu bar views while preserving lifecycle ownership,” or “Use swiftui-performance-audit to investigate refresh overhead.” Agents load them by the files they touch, per the [skill activation triggers](../../CLAUDE.md#skill-activation). Apple interface guidance remains the design baseline; these skills do not replace macOS interaction/accessibility checks. The [first trial](../research/development-tools.md#first-project-trial--2026-10-15) records their practical usefulness and limits.

### Install or update

To reproduce the installation on another computer, run the following from this repository in a network-enabled terminal:

```sh
bash scripts/skills.sh install
bash scripts/skills.sh check
```

[The setup script](../../scripts/skills.sh) clones complete upstream repositories, including references and licenses, into ignored `.skill-sources/swift-concurrency/`, `.skill-sources/swift-testing-expert/` and `.skill-sources/agent-scripts/`. Both SwiftUI skills share the single `agent-scripts` checkout and lock entry. Only the selected skill directories are exposed through relative links under `.agents/skills/` and `.claude/skills/`, with identical files for both hosts.

The installer does not apply upstream repository instructions, run upstream setup scripts, change global skill directories or install host-specific plugins/hooks. Skills become available to newly discovered sessions; restart an existing CLI if it does not refresh its catalog.

The first installation records exact commit IDs in `skills.lock`; subsequent installs reuse those revisions. Keep that lock file and both hosts' symlinks in version control. On another computer, run the install command again to populate the ignored source checkouts. To upgrade deliberately:

```sh
bash scripts/skills.sh update
bash scripts/skills.sh check
```

Updates fetch each upstream `main`, select its current commit, and refresh the lock. The script refuses dirty source checkouts, missing root licenses or conflicting discovery paths. Review the lock changes and upstream instructions before continuing agent work.

`bash scripts/test-skills.sh` checks dual-host discovery, retained references/licenses, pinned reinstalls, shared-source upgrades and edit protection against disposable local Git repositories without contacting GitHub. Additional profiling helpers and app-release skills are not installed. The repository owns its [Mac release workflow](../macos-release.md).

## Restricted agent environments

When SwiftPM cannot write user caches, use `CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"` and `--cache-path .build/cache --config-path .build/config --security-path .build/security --manifest-cache local --disable-sandbox`. Ordinary terminal use should start with the commands in the [README](../../README.md).

### Diagnosed build stalls

For a diagnosed `clang-stat-cache` stall, try `-Xxcbuild SDK_STAT_CACHE_ENABLE=NO`; if it persists, the recorder can be prepared with `swift build --build-system native -c release --product monitor-workload-capture`.

This deprecated backend is a local fallback, not a project-wide toolchain change. Stop only diagnosed stuck builds you own before retrying, and keep builds serialized.

A “Build complete” line does not establish that the test runner exited successfully.

If release linking succeeds but dSYM generation fails with `Operation not permitted`, use `swift build -c release -debug-info-format none` to produce an optimized executable without a debug-symbol bundle. Keep ordinary debug builds for source-level debugging.

Do not request Full Disk Access merely because a process field is unavailable. Missing permissions, short-lived processes, and omitted environment entries are normal inspection outcomes and must remain visible in the model.

SwiftTUI’s 0.14.0 scene launcher attempts to bind a Unix discovery socket, rejected by this sandbox. The monitor uses its documented public `RunLoop`, `TerminalHost`, `InputReader`, and `SignalReader` instead. This single-screen terminal host needs no discovery service or permission changes. See the [runtime findings](../research/terminal-ui.md#sandbox-compatible-terminal-host).

## Build and probe artifact retention

`.build` is disposable working storage, not a project archive. Source, pinned dependencies (`Package.resolved`), maintained probe sources and indexed measurements in [research](../research/README.md) are the durable inputs. Before deleting an experimental output that supports a retained claim, save its small sanitized result and interpretation in research; do not retain raw machine-wide traces merely because they are ignored by Git.

| Artifact | Retention rule |
| --- | --- |
| `.build/out`, module caches, manifests and dependency checkouts | Rebuildable. Keep the active tree during builds/tests; remove stale configurations and caches when idle. |
| Design-study images and supporting render files | Always reuse `.build/design-studies/`; review images are PNG files. Never track study images in Git or place them in `docs/assets/`. Keep written findings and decisions in indexed documentation. |
| Local `Agent Monitor.app` bundle | Rebuildable with the [menu bar build](native-app.md). Keep the current app while it is being used; remove obsolete spike/duplicate bundles. |
| Probe executables, exported XML, Instruments `.trace` directories and release-verification downloads | Temporary. Delete after the required result has been extracted and retained; raw traces can grow by gigabytes in seconds. |
| Test/profile logs for the active change | Keep through validation/review, then retain only the evidence needed to explain the result. Tests can regenerate routine logs. |
| Measurements, decisions and review conclusions needed later | Store in their indexed documentation location, never solely under `.build`. |

Use [clean-build.py](../../scripts/clean-build.py) for new probes and experimental exports. Its read-only `check` runs before and after the local menu-bar build and from `doctor.sh`: it fails on top-level logs older than seven days, PNGs outside `design-studies`, abandoned scratch runs and coexisting build-backend trees, even when Debug and Release each reference one of them. Findings require review, not automatic deletion; product links do not prove a tree is idle. This is a narrow guard for demonstrated waste, not a generic artifact classifier or cache-size limit. Completed-checkpoint logs should normally be removed sooner, after recording their findings.

```sh
python3 scripts/clean-build.py run -- bash -c 'your-probe > "$AGENT_MONITOR_SCRATCH/result.json"; your-analysis "$AGENT_MONITOR_SCRATCH/result.json"'
python3 scripts/clean-build.py check
python3 scripts/clean-build.py clean
python3 scripts/clean-build.py clean --apply
```

`run` creates a locked scratch directory and removes it on normal exit, command failure or Ctrl-C; commands must wait for their children.

### Interrupted probe cleanup

Interrupted cleanup signals only a still-running owned command's process group, with a five-second wait after SIGTERM and, if needed, SIGKILL. A vanished group still permits reaping the owned command.

Termination failure preserves the original interruption as the primary exception and retains the cleanup failure as traceback context. The scratch directory is preserved because the command may still be running; its inherited lease continues protecting it from cleanup.

Analyze output inside that command and copy only explicitly approved durable evidence out before it exits.

### Dry-run cleanup and validation

Each run also prunes unlocked abandoned scratch directories older than seven days.

`clean` is a dry run unless `--apply` is supplied; it only considers marked `run-*` directories under `.build/scratch`, skips active locks and symlinks, and never cleans SwiftPM products, caches, app bundles or arbitrary `.build` files. A forced kill can leave a scratch directory for the next cleanup.

Validate the script with `python3 -m unittest discover -s scripts -p test_clean_build.py`; its mocked interruption guards cover signaling/reaping failures, already-finished commands, disappearing groups and bounded escalation without signaling user workloads.

Check size before and after profiling with `du -h -d 2 .build`. Keep one active build backend; do not create a new scratch tree for each retry. Never clean an active compiler/test tree. A full `.build` removal is appropriate when idle if all durable evidence is already retained; the next build restores dependencies and products.

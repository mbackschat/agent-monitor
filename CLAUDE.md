# Repository Guidelines

## Project Status & Structure

Agent Monitor is a macOS Swift PoC for mapping heavy processes to specific coding-agent sessions. `Sources/AgentMonitorCore/` contains native sampling, attribution, and models; `Sources/AgentMonitor/` contains the command-line harness; `AgentMonitorPresentation/` owns neutral rendering/interaction state and `AgentMonitorTUI/` owns SwiftTUI views. `Tests/` contains Swift Testing tests and disposable process fixtures. [TUI research](docs/research/terminal-ui.md) records the isolated probe; its temporary build directory has been removed. Keep UI dependencies out of the monitoring core. See [README.md](README.md), [development guidance](docs/development.md), and [product scope](docs/research/PRODUCT.md).

`CLAUDE.md` is canonical; preserve the `AGENTS.md` symlink.

Keep the [README](README.md) focused on users: purpose, features, quick start, and current support. Detailed controls belong in the [usage guide](docs/usage.md), build/check instructions in the [development guide](docs/development.md), and implementation contracts in the [architecture document](docs/architecture.md).

When changing CLI options, defaults, or incompatible combinations, update the README option table and affected usage examples in the same commit. Verify them against `Options.swift` and the executable's generated `--help`, including the different default sample count in TUI mode.

Read [PLAN.md](PLAN.md) when resuming. Keep its PoC tasks, completion evidence, and next action current; do not expand into product development.

Follow [architecture boundaries](docs/architecture.md): monitoring logic and snapshots are UI-independent; text, TUI, and future native views own presentation only. Document architectural changes alongside the code.

Session grouping belongs to presentation and totals only displayed heavy processes. Preserve provider/session identities and attribution uncertainty; never merge by directory or shared runtime alone. Keep JSONL's flat snapshot contract independent of grouping.

## Build, Test, and Development Commands

- `swift build`: build the library and executable.
- `swift run agent-monitor`: report heavy consumers.
- `swift test`: run unit and native integration tests.
- `swift format lint --strict --recursive Sources Tests Tools Package.swift`: check formatting.
- `bash scripts/doctor.sh`: check the contributor toolchain and optional skill setup without installing anything.
- `bash scripts/preview.sh check`: verify the README preview matches the production layout and synthetic fixture.
- `python3 scripts/verify-poc.py "$(swift build --show-bin-path)/agent-monitor"`: verify controlled terminal attribution after building.

Use Xcode 27, Swift 6.4, and macOS 27. Apple Argument Parser belongs only to CLI targets; keep the monitoring core independent of it and UI libraries.

## Coding Style & Naming Conventions

Project skills must work with both Codex CLI and Claude Code. Keep one canonical copy with its references and license; expose it through both hosts' skill discovery directories, using symlinks where appropriate. Keep host-specific hooks, plugins, and tool configuration separate, and verify both discovery paths before adopting a skill.

Use `bash scripts/skills.sh install` for project-local skills, `update` for explicit upgrades, and `check` to verify both discovery paths. Preserve the generated `skills.lock`; see [skill setup](docs/development.md#skills-shared-by-codex-cli-and-claude-code).

On a fresh clone, the tracked skill symlinks do not resolve until `install` populates ignored `.skill-sources/` at the locked revisions. Skills are optional development aids, not build/runtime dependencies. Do not commit those source checkouts, change the lock during routine setup, or install skills globally. The read-only doctor reports missing skills as optional and broken installed skills as an error.

Keep the generated [README preview](docs/assets/tui-preview.svg) current when changing layout, displayed text, grouping, details, or synthetic fixtures. Run `bash scripts/preview.sh update`, visually review the SVG, and commit it with the change; then run `bash scripts/preview.sh check`. Edit [the generator and fixture](Tools/Preview/), never the SVG by hand. Use synthetic identities and paths only; never sample real processes for documentation images. The generator is development-only and must not be included in release archives. CI runs preview drift checks and Swift tests on every pull request and main push. The SVG verifies text/layout, not terminal interaction or exact theme colors; preserve PTY tests and visually review TUI style changes. See [preview maintenance](docs/development.md#readme-preview).

Preserve fixed character positions in the preview SVG; do not stretch rows with `textLength`/`lengthAdjust` or rely on whitespace preservation for terminal columns. Validate browser appearance when available and state explicitly when only a converter render was inspected.

Use four-space indentation, the bundled `swift format`, Swift 6 concurrency checking, and enum-based switches. Keep presentation separate from collection. Comments explain constraints and cite their basis. Write Markdown with one paragraph per physical line and regular links to other documents.

## Testing Guidelines

Use red/green TDD and descriptive Swift Testing tests. Positive fixtures must resolve exact sessions; unknown everywhere cannot pass. Cover same-directory sessions, PID reuse, detached children, ambiguity, and resource-unit semantics. Never infer ownership from cwd alone or treat a protocol process handle as an OS PID.

## Commit & Pull Request Guidelines

Git is initialized on `main`. Build outputs, caches, and temporary evaluations must remain ignored. Use Conventional Commits, such as `feat(attribution): identify heavy session workloads`. Add a concise body for non-obvious rationale.

Automatically commit completed, validated checkpoints and relevant features without asking for confirmation. Keep each commit coherent, include related documentation, and leave unrelated work untouched. This project-specific authorization overrides the global preference to only propose commits for fixes; it does not authorize pushing.

Pull requests should describe the problem, resulting behavior, and validation performed. Link applicable issues and include screenshots for visible UI changes. Do not create or switch worktrees without explicit instructions.

# Repository Guidelines

## Project Status & Structure

Agent Monitor is a macOS Swift PoC for mapping heavy processes to specific coding-agent sessions. `Sources/AgentMonitorCore/` contains native sampling, attribution, and models; `Sources/AgentMonitor/` contains the command-line harness; `AgentMonitorPresentation/` owns neutral rendering/interaction state and `AgentMonitorTUI/` owns SwiftTUI views. `Tests/` contains Swift Testing tests and disposable process fixtures. [TUI research](docs/research/terminal-ui.md) records the isolated probe; its temporary build directory has been removed. Keep UI dependencies out of the monitoring core. See [README.md](README.md), [development guidance](docs/development.md), and [product scope](docs/research/PRODUCT.md).

`CLAUDE.md` is canonical; preserve the `AGENTS.md` symlink.

Keep the [README](README.md) focused on users: purpose, features, quick start, and current support. Detailed controls belong in the [usage guide](docs/usage.md), build/check instructions in the [development guide](docs/development.md), and implementation contracts in the [architecture document](docs/architecture.md).

Read [PLAN.md](PLAN.md) when resuming. Keep its PoC tasks, completion evidence, and next action current; do not expand into product development.

Follow [architecture boundaries](docs/architecture.md): monitoring logic and snapshots are UI-independent; text, TUI, and future native views own presentation only. Document architectural changes alongside the code.

Session grouping belongs to presentation and totals only displayed heavy processes. Preserve provider/session identities and attribution uncertainty; never merge by directory or shared runtime alone. Keep JSONL's flat snapshot contract independent of grouping.

## Build, Test, and Development Commands

- `swift build`: build the library and executable.
- `swift run agent-monitor`: report heavy consumers.
- `swift test`: run unit and native integration tests.
- `swift format lint --strict --recursive Sources Tests Package.swift`: check formatting.
- `python3 scripts/verify-poc.py "$(swift build --show-bin-path)/agent-monitor"`: verify controlled terminal attribution after building.

Use Xcode 27, Swift 6.4, and macOS 27. Apple Argument Parser belongs only to CLI targets; keep the monitoring core independent of it and UI libraries.

## Coding Style & Naming Conventions

Project skills must work with both Codex CLI and Claude Code. Keep one canonical copy with its references and license; expose it through both hosts' skill discovery directories, using symlinks where appropriate. Keep host-specific hooks, plugins, and tool configuration separate, and verify both discovery paths before adopting a skill.

Use `bash scripts/skills.sh install` for project-local skills, `update` for explicit upgrades, and `check` to verify both discovery paths. Preserve the generated `skills.lock`; see [skill setup](docs/development.md#skills-shared-by-codex-cli-and-claude-code).

Use four-space indentation, the bundled `swift format`, Swift 6 concurrency checking, and enum-based switches. Keep presentation separate from collection. Comments explain constraints and cite their basis. Write Markdown with one paragraph per physical line and regular links to other documents.

## Testing Guidelines

Use red/green TDD and descriptive Swift Testing tests. Positive fixtures must resolve exact sessions; unknown everywhere cannot pass. Cover same-directory sessions, PID reuse, detached children, ambiguity, and resource-unit semantics. Never infer ownership from cwd alone or treat a protocol process handle as an OS PID.

## Commit & Pull Request Guidelines

Git is initialized on `main`. Build outputs, caches, and temporary evaluations must remain ignored. Use Conventional Commits, such as `feat(attribution): identify heavy session workloads`. Add a concise body for non-obvious rationale.

Automatically commit completed, validated checkpoints and relevant features without asking for confirmation. Keep each commit coherent, include related documentation, and leave unrelated work untouched. This project-specific authorization overrides the global preference to only propose commits for fixes; it does not authorize pushing.

Pull requests should describe the problem, resulting behavior, and validation performed. Link applicable issues and include screenshots for visible UI changes. Do not create or switch worktrees without explicit instructions.

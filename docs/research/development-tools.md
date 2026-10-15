# Development tool findings

Sources inspected on 2026-10-14. This comparison did not install tools or benchmark their effect on code quality. Current adopted skills, pinned revisions and installation commands belong in the [development guide](../development.md#skills-shared-by-codex-cli-and-claude-code) and [skills.lock](../../skills.lock).

## Skill and tooling candidates

| Source | Observed contents and limitations |
|---|---|
| [AvdLee Swift Concurrency](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill) | Portable skill and references covering isolation, cancellation, `Sendable` and build-setting inspection. [MIT license](https://raw.githubusercontent.com/AvdLee/Swift-Concurrency-Agent-Skill/main/LICENSE). It does not establish Darwin accounting correctness. |
| [AvdLee Swift Testing](https://github.com/AvdLee/Swift-Testing-Agent-Skill) | Portable skill/reference layout and Claude plugin packaging; parameterized tests, async waiting and parallel isolation. [License and packaging](https://github.com/AvdLee/Swift-Testing-Agent-Skill/blob/main/README.md). |
| [AvdLee SwiftUI](https://github.com/AvdLee/SwiftUI-Agent-Skill), [twostraws SwiftUI](https://github.com/twostraws/SwiftUI-Agent-Skill) | Both expose portable, MIT-licensed guidance. The inspected twostraws instructions assumed an iOS target and recent Swift defaults; those are not macOS compatibility evidence. [AvdLee license](https://raw.githubusercontent.com/AvdLee/SwiftUI-Agent-Skill/main/LICENSE), [twostraws license](https://raw.githubusercontent.com/twostraws/SwiftUI-Agent-Skill/main/LICENSE). |
| [twostraws Swift Concurrency](https://github.com/twostraws/Swift-Concurrency-Agent-Skill) | Structured concurrency, actors and task groups with Codex and Claude installation descriptions. [MIT license](https://raw.githubusercontent.com/twostraws/Swift-Concurrency-Agent-Skill/main/LICENSE). No comparative quality measurement was performed. |
| [Dimillian SwiftPM app packaging](https://github.com/Dimillian/Skills/tree/main/macos-spm-app-packaging) | Skill, templates and executable scripts for bundling, signing and notarization; authored for Codex. The separate [menu-bar skill](https://raw.githubusercontent.com/Dimillian/Skills/main/macos-menubar-tuist-app/SKILL.md) assumes Tuist and a specific app architecture. [MIT license](https://raw.githubusercontent.com/Dimillian/Skills/main/LICENSE); scripts were not fully audited. |
| [Axiom](https://github.com/CharlesWiltgen/Axiom) | Apple-development skills plus agents, hooks, executables and MCP integration. [Codex packaging](https://charleswiltgen.github.io/Axiom/start/codex-install) differs from Claude packaging; skills-only installation omits helpers/hooks, and the full plugin's MCP dependency was described as unpinned. [MIT license](https://raw.githubusercontent.com/CharlesWiltgen/Axiom/main/LICENSE). |
| [MobileBuildMCP](https://github.com/getsentry/MobileBuildMCP) | Executable build/run/test tooling, not just instructions. The [2.7.1 release](https://github.com/getsentry/MobileBuildMCP/releases/tag/v2.7.1) records the rename from XcodeBuildMCP and changed binary/configuration names. [MIT license](https://raw.githubusercontent.com/getsentry/MobileBuildMCP/main/LICENSE); third-party notices and transitive tools were not fully audited. |

## Cross-host discovery

The inspected [Codex documentation](https://learn.chatgpt.com/docs/build-skills) describes `SKILL.md`, repository `.agents/skills` discovery and symlinked directories. [Claude documentation](https://code.claude.com/docs/en/skills) describes `.claude/skills`, symlinks and additional host-specific frontmatter. [Axiom's compatibility table](https://charleswiltgen.github.io/Axiom/start/codex-install#differences-from-claude-code) confirms that procedures represented as skills in Codex may be agents or commands in Claude.

Inference: portable prose and relative references can be shared, but that does not make hook configuration, MCP tools or agent execution equivalent. The repository's later cross-host discovery checks are recorded in the development guide, not established by this source comparison.

## Gaps

No controlled quality ranking or complete transitive license/script audit was performed. Repository and release pages had differing crawl dates, so they did not establish synchronized latest revisions. These dated observations do not establish current upstream versions or compatibility.

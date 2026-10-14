# macOS Development Skills and Agent Integration

Research checked on 2026-10-14. This is a source-backed assessment, not an installation or implementation. Repository pages and release listings may have different crawl dates; the revisions below are observed evidence, not a claim that every listed commit is the latest upstream HEAD. No skills, hooks, plugins, or MCP servers were installed or enabled.

Follow-up source inspection of the installed Codex 0.162.1 release confirms `CODEX_THREAD_ID`, `CODEX_SESSION_ID`, and `CODEX_VERSION` injection into shell commands. `CODEX_SESSION_ID` equals the root thread ID, not an OS process-instance ID. The absence of these fields from the reviewed environment documentation below must not be interpreted as absence from the implementation. See [Codex terminal attribution](codex-terminal-attribution.md) for pinned source, the proposed mapping, and compatibility limits.

## Which development skills are useful for this project?

### Takeaway

If the implementation uses Swift, start with two narrowly scoped skills: **AvdLee Swift Concurrency** and **AvdLee Swift Testing**. Add **one SwiftUI skill** and **Dimillian's SwiftPM app packaging skill** only when the product reaches its optional GUI stage. Axiom and MobileBuildMCP are useful additional references and tooling candidates, but adopting their complete bundles is unnecessary for the headless core.

### Cited Findings

| Candidate | Type and verified support | Fit and limitations | License and maintenance evidence |
|---|---|---|---|
| [AvdLee/Swift-Concurrency-Agent-Skill](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill) | `SKILL.md` plus references; README supplies Claude Code plugin and portable skill installation paths, including Codex. | **Recommended now if Swift.** Actor isolation, cancellation, `Sendable`, streams, task lifetimes, and async tests directly concern a long-lived sampler. It first inspects actual build settings and rejects blanket `@MainActor` fixes. Does not teach Darwin process accounting. [Inspected skill](https://raw.githubusercontent.com/AvdLee/Swift-Concurrency-Agent-Skill/main/skills/swift-concurrency/SKILL.md). | [MIT, Antoine van der Lee](https://raw.githubusercontent.com/AvdLee/Swift-Concurrency-Agent-Skill/main/LICENSE). Release listing shows **2.1.1**, `faa595e`, May 4, 2026, correcting task isolation guidance. [Releases](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill/releases). |
| [AvdLee/Swift-Testing-Agent-Skill](https://github.com/AvdLee/Swift-Testing-Agent-Skill) | Portable `swift-testing-expert/SKILL.md` and reference files; Claude Code plugin also provided. | **Recommended now if Swift.** Parameterized cases, asynchronous waiting, parallel test isolation, and XCTest coexistence. Useful for process graph fixtures and deterministic polling tests. [Inspected skill](https://raw.githubusercontent.com/AvdLee/Swift-Testing-Agent-Skill/main/swift-testing-expert/SKILL.md). | README declares MIT and identifies Antoine van der Lee. Observed **1.2.0**, `798e9b1`, April 22, 2026; release fixes the plugin skill path. [README and license](https://github.com/AvdLee/Swift-Testing-Agent-Skill/blob/main/README.md), [releases](https://github.com/AvdLee/Swift-Testing-Agent-Skill/releases). |
| [AvdLee/SwiftUI-Agent-Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill) | Portable SwiftUI guidance with Claude Code packaging. | **Recommended later**, when there is a GUI to review. Pick this or the twostraws alternative, rather than loading overlapping UI guidance. GUI expertise does not solve attribution. | [MIT, Antoine van der Lee](https://raw.githubusercontent.com/AvdLee/SwiftUI-Agent-Skill/main/LICENSE). Observed **5.2.1**, `9897311`, October 2, 2026. [Releases](https://github.com/AvdLee/SwiftUI-Agent-Skill/releases). |
| [Dimillian/Skills: macos-spm-app-packaging](https://github.com/Dimillian/Skills/tree/main/macos-spm-app-packaging) | A concrete skill, templates, and shell scripts; authored for Codex. Generic SwiftPM/Apple command workflows are adaptable to Claude Code. | **Recommended later if using SwiftPM app packaging.** Covers `.app` creation, signing, notarization, and menu-bar packaging. Audit scripts before reuse; optional Sparkle/release publishing is outside this project's present scope. [Inspected skill](https://raw.githubusercontent.com/Dimillian/Skills/main/macos-spm-app-packaging/SKILL.md). | [MIT, Thomas Ricouard](https://raw.githubusercontent.com/Dimillian/Skills/main/LICENSE). Observed repository commit `23e5213`, March 28, 2026; historical rather than confirmed current HEAD. [Commit listing](https://github.com/Dimillian/Skills/commits/main/). |

Other evaluated candidates:

- **[Axiom](https://github.com/CharlesWiltgen/Axiom):** a large Apple-development suite containing skills, agents, hooks, helper executables, and MCP integration. It has explicit macOS guidance for menus, AppKit, sandboxing, and direct distribution, plus profiling and memory diagnostics. This is broader than an iOS-only prompt collection. Relevant individual references are [macOS](https://charleswiltgen.github.io/Axiom/skills/macos/) and [performance profiling](https://charleswiltgen.github.io/Axiom/skills/debugging/performance-profiling). The project is [MIT licensed](https://raw.githubusercontent.com/CharlesWiltgen/Axiom/main/LICENSE); documentation displayed v27.5.0 while a separately crawled [commit listing](https://github.com/CharlesWiltgen/Axiom/commits/main/) showed September 8, 2026 activity. These do not establish a single synchronized revision.
- **Axiom portability is explicit but not identical behavior:** the Codex version exposes auditor procedures as skills, while Claude Code has agents and slash commands. Skills-only installation omits lifecycle hooks and helpers; the full Codex plugin includes them. The documentation also states that the full plugin's MCP dependency is unpinned. Prefer selected references initially, and review a pinned bundle before adoption. [Axiom Codex integration](https://charleswiltgen.github.io/Axiom/start/codex-install).
- **[twostraws/SwiftUI-Agent-Skill](https://github.com/twostraws/SwiftUI-Agent-Skill):** Paul Hudson's portable `swiftui-pro` alternative, [MIT licensed](https://raw.githubusercontent.com/twostraws/SwiftUI-Agent-Skill/main/LICENSE). The [inspected skill](https://raw.githubusercontent.com/twostraws/SwiftUI-Agent-Skill/main/swiftui-pro/SKILL.md) has useful review discipline but explicitly prescribes a recent Swift version and an iOS default target; those defaults need adaptation for this macOS project. Its current skill metadata says 2.0.0, while the separately crawled [commit listing](https://github.com/twostraws/SwiftUI-Agent-Skill/commits/main/) shows April 20, 2026 v1.1 activity. Do not combine these into a false exact version claim.
- **[twostraws/Swift-Concurrency-Agent-Skill](https://github.com/twostraws/Swift-Concurrency-Agent-Skill):** another portable, [MIT-licensed](https://raw.githubusercontent.com/twostraws/Swift-Concurrency-Agent-Skill/main/LICENSE) option covering structured concurrency, task groups, actors, and `Sendable`, with explicit Codex and Claude instructions. An observed [commit listing](https://github.com/twostraws/Swift-Concurrency-Agent-Skill/commits/main/) includes Claude plugin support merged May 17, 2026. Choose one concurrency authority to avoid contradictory defaults; the AvdLee skill's inspected build-setting checks make it the stronger initial fit here.
- **[Dimillian macos-menubar-tuist-app](https://raw.githubusercontent.com/Dimillian/Skills/main/macos-menubar-tuist-app/SKILL.md):** directly relevant menu-bar instructions, but explicitly assumes Tuist manifests and a particular model/client/store/view architecture. It is not a neutral reason to choose Tuist. Defer unless that build system is selected independently.
- **[MobileBuildMCP, formerly XcodeBuildMCP](https://github.com/getsentry/MobileBuildMCP):** an executable MCP server and CLI for Apple development, not merely a skill. It provides build/run/test workflows and includes skills; the repository is [MIT licensed](https://raw.githubusercontent.com/getsentry/MobileBuildMCP/main/LICENSE), with separate third-party notices. The [v2.7.1 release](https://github.com/getsentry/MobileBuildMCP/releases/tag/v2.7.1), September 23, 2026, documents the rename, changed binary/config names, and a Homebrew installation path. Old instructions using XcodeBuildMCP tool names require version checks. Defer until Xcode workflows or app debugging justify it.
- **Official documentation is a separate resource class:** [Swift Package Manager](https://github.com/swiftlang/swift-package-manager), [Swift Testing](https://developer.apple.com/documentation/testing), and [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) are upstream references rather than agent instruction bundles. Apple pages returned a JavaScript shell in this research environment; no substantive API guarantee is inferred from those unopened page bodies.

### Inferences

- The recommended four-item set is deliberately staged: two skills for a Swift headless core, one for UI, one for distribution. This recommendation changes if the core is implemented in Rust or another language; none of these skills requires choosing Swift.
- A monitoring application must itself remain cheap and cancellation-safe. Concurrency and deterministic testing guidance therefore has greater immediate value than visual-design skills.
- Skills improve developer workflow; they do not supply a tested process-attribution library. No reviewed skill establishes the correctness of Darwin PID accounting or session ownership.

### Gaps

- No controlled quality benchmark was performed across these skill authors. Maintainer identity, inspected instructions, release activity, and license evidence support a shortlist, not a measured ranking.
- Exact latest commit hashes for every candidate were not confirmed. Direct GitHub API access from the shell failed DNS resolution; browser-accessible primary pages were used instead. Recheck and pin the chosen revision before installation or copying code.
- The complete helper scripts and transitive packages in Axiom, MobileBuildMCP, and the packaging template were not audited. Their top-level license does not replace checking copied-file provenance and third-party notices.

## What genuinely transfers between Codex and Claude Code?

### Takeaway

Portable `SKILL.md` instructions and their relative references can be shared; host-specific agents, hook configurations, permission metadata, and MCP tool names need separate validation. A vendor's statement that a skill supports both hosts is not evidence that every bundled automation behaves identically.

### Cited Findings

- Codex documents YAML-frontmatter `SKILL.md` files, repository `.agents/skills` discovery, user `~/.agents/skills`, and symlinked skill directories. Its current docs distinguish plain skill folders from plugins that can also contain MCP configuration. Older repository instructions mentioning only `$CODEX_HOME/skills` should be checked against the installed version. [Official OpenAI skill documentation](https://learn.chatgpt.com/docs/build-skills).
- Claude Code documents project `.claude/skills/<name>/SKILL.md`, personal `~/.claude/skills`, symlinked skill folders, and plugin skill namespaces. Its frontmatter also supports host behavior beyond portable instructions. [Official Claude Code skills documentation](https://code.claude.com/docs/en/skills).
- Axiom documents different Codex/Claude representations and a separate Codex plugin distribution, demonstrating why copying a whole Claude plugin into Codex is insufficient. [Axiom compatibility table](https://charleswiltgen.github.io/Axiom/start/codex-install#differences-from-claude-code).

### Inferences

- If adopted, keep one reviewed canonical copy of each selected skill and expose it through the appropriate host discovery locations. Preserve the skill's reference directory and license. Do not copy an isolated `SKILL.md` that points at missing references.
- Verify loading in each installed CLI, then give both agents the same small repository task to confirm reference resolution and command compatibility. This is proposed acceptance work, not work already performed.
- Keep architectural decisions in this repository's documentation. Skills should support those decisions rather than silently introduce Tuist, a UI framework, autonomous reviewers, or a deployment workflow.

### Gaps

- Neither CLI was reconfigured and no live cross-host installation smoke test was run. Portability conclusions are based on official discovery contracts and inspected upstream content.

## Which agent interfaces can connect a process to its session?

### Takeaway

Current Claude Code documentation provides a direct inherited session marker. Both products now document lifecycle hooks useful for session and command context, but their reviewed hook schemas do not provide a general child OS PID. Resource attribution still needs an OS process identity and observed lineage; provider metadata should enrich that evidence rather than replace it.

### Cited Findings

| Interface | Verified evidence | Attribution limit |
|---|---|---|
| Claude `CLAUDE_CODE_SESSION_ID` | Automatically set in Bash/PowerShell, hook-command, and stdio MCP subprocesses; Bash/hooks track `/clear`. Explicit `--resume <id>` gives MCP the resumed ID. [Environment reference](https://code.claude.com/docs/en/env-vars). | MCP retains its spawn ID; `--continue` or unspecified `--resume` can leave its initial ID. A session marker does not identify a particular tool invocation. |
| Claude `CLAUDE_CODE_MESSAGING_SOCKET` | Officially documented for sessions binding an inbox socket; each session exports its own path to hooks/Bash, requiring v2.1.224+. [Environment reference](https://code.claude.com/docs/en/env-vars). | Conditional availability. Prefer the explicit session ID for correlation; do not classify all versions or sessions by socket presence. |
| Claude hooks | Common `session_id`, `cwd`, `transcript_path`; tool hooks add `tool_name`, `tool_input`, `tool_use_id`. Transcript writes may lag. Command hooks use their own OS session without a controlling terminal. [Hook reference](https://code.claude.com/docs/en/hooks). | Reviewed schemas do not expose a universal child PID. A hook's own PID/PPID describes the hook, not necessarily the pending Bash workload. |
| Codex hooks | Common session/cwd fields; tool events add `tool_use_id` and tool input; subagent hooks use the parent session ID and add agent identity. Transcript format explicitly unstable. [Official hooks reference](https://learn.chatgpt.com/docs/hooks). | No documented general child PID in reviewed schemas. Preserve subagent IDs separately instead of treating them as independent OS sessions. |
| Codex app-server | Thread/turn/item events supply command context. Documentation describes experimental `thread/backgroundTerminals/list` with `processId` plus nullable `osPid`, `cpuPercent`, and `rssKb`. [App-server reference](https://learn.chatgpt.com/docs/app-server). | `processId` is not interchangeable with an OS PID. The pinned 0.162.1 core record lacks OS PID/resource fields, so populated values cannot be promised; see the [source follow-up](codex-terminal-attribution.md). The list is not an inventory of every descendant. |

- App-server supports stdio, WebSocket, and Unix socket transports; documentation allows schemas generated from the installed CLI version. Some transports and methods are experimental. This is a possible integration surface for a connected client, not proof that every independently launched CLI exposes an attachable monitor endpoint. [Official app-server documentation](https://learn.chatgpt.com/docs/app-server).
- The reviewed official Codex [environment-variable reference](https://learn.chatgpt.com/docs/config-file/environment-variables) did not document `CODEX_THREAD_ID`. That absence does not establish that the variable never exists; it means this research cannot endorse it as a stable public integration contract.

### Inferences

- Distinguish **session attribution** from **tool-call attribution**. An inherited session identifier can resolve which agent launched a process; a concurrent tool run still needs separately recorded invocation/launch evidence.
- Read only an allowlist of candidate marker names if environment access is implemented. Do not persist whole environments, prompt transcripts, or messaging tokens to obtain a session label.
- Correlate hooks with independently observed process identity and timestamps. Persist observed ancestry before it disappears; treat a matching working directory or command string as a heuristic because multiple agent sessions can share both.
- A wrapper or launch registration could provide an exact initial process identity, but would be an opt-in product integration to validate. It is not a capability guaranteed by the reviewed hook schemas.
- Model confidence explicitly: direct marker/registered launch, observed lineage, heuristic association, or unknown. Preserve ambiguous candidates rather than guessing the responsible session.

### Gaps

- No live compatibility matrix was run for agent versions, `/clear`, resumed sessions, subagents, sandboxed launches, environment scrubbing, detached children, or shared MCP/build daemons. Documented fields still need end-to-end macOS validation.
- No stable public Codex transcript schema or universal hook-to-child-PID mapping was established. Internal JSONL fields, filename encodings, environment variables without a documented contract, and socket path parsing should remain versioned fallback adapters.
- Whether an unprivileged macOS collector can read each target process's permitted metadata, and whether experimental `osPid` values are populated by the installed provider, must be measured on the target Mac. Missing values must remain visible rather than becoming false ownership claims.

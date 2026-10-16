# Research index

These notes record dated observations, cited source behavior, labeled inferences and unresolved empirical questions. Dates and versions apply to each investigation; editorial cleanup does not revalidate upstream sources. Raw measurements retain their original scope and limitations.

Check this index before investigating a topic, and extend the matching note rather than starting a parallel one. Every new note or retained measurement gets an entry here in the same commit.

Current behavior and accepted contracts belong in the [README](../../README.md) and [architecture](../architecture.md). Repeatable checks and live coverage belong in [development](../development.md#validation-coverage); unfinished work and scope decisions belong in [PLAN.md](../../PLAN.md). Design proposals and investigation briefs:

- [Menu bar](../proposals/menubar-app.md): retained native-app proposal and deferred decisions.
- [Contributor model](../proposals/agent-working-model.md): unapproved working-model proposal.
- [Agent-friendly CLI](../proposals/agent-friendly-cli.md): unapproved built-in guidance and bounded CPU-diagnosis proposal.
- [Claude runtime binding](../proposals/claude-runtime-binding.md): implemented registry binding and deferred detached-workload link.
- [Codex session listing brief](../proposals/codex-session-registry-research.md): investigated questions and limits.
- [Codex registry assessment](../proposals/codex-session-registry.md): accepted deferral, its consequences and native identity conditions for reconsideration.

## Findings by topic

- [Codex process and session identities](codex-terminal-attribution.md): pinned marker injection, logical thread/root semantics, writer descriptors and tool-call correlation limits; the 2026-10-16 follow-up checks 0.163.0 listing scope, null OS PIDs, connection effects and one live call.
- [Claude session metadata and messaging](claude-session-messaging.md): marker lifecycle, session lookup, inbox protocol evidence and the disposable-session transport check.
- [Claude runtime and workload attribution signals](claude-runtime-attribution.md): runtime-to-session binding sources, embedded tools invoked under another name, workload environment variables and directories within one session.
- [Process signaling and messaging interfaces](session-actions.md): signal races, queue/resume interfaces, recipient identity and acceptance versus delivery.
- [Terminal focus mechanisms](terminal-focus.md): host identifiers, per-terminal APIs, macOS permission/activation behavior and untested desktop states.
- [Menu bar feasibility](menubar-app.md): UI/lifecycle APIs, launch environment, process access, signing and Homebrew evidence, with unverified inferences identified.
- [Menu bar load collection cost](menu-bar-load-cost.md): native sampling breakdown, runtime-recognition and argument-buffer hotspots, bounded measurements and energy limits.
- [Native menu design](native-menu-design.md): Apple interface guidance, pinned CodexBar/RepoBar/Trimmy source and screenshots, content-sizing API observations and unresolved live interaction questions.
- [Swift terminal UI findings](terminal-ui.md): library observations, discovery-socket failure, direct runtime behavior and bounded probe measurements.
- [Local process observations](terminal-process-observations.md): anonymized process topology, marker readability and synthetic orphan experiments.
- [macOS measurement and attribution](macos-process-attribution.md): native APIs, counter units, process identity, permissions and event-collection limits.
- [CPU accounting coverage](cpu-accounting.md): first-interval, exited and short-lived lifetimes, reaped-descendant counters, unprivileged host CPU ticks and the 2026-10-16 disposable probes.
- [Existing tools and reusable mechanisms](existing-solutions.md): inspected source, license files, maintenance observations and untested compatibility; the [2026-10-16 CLI investigation](existing-solutions.md#agent-oriented-cli-investigation--2026-10-16) adds agent-oriented guidance, finite diagnostics, discovery/schema comparisons and a constrained helper experiment.
- [Development tools](development-tools.md): skill contents, Peter Steinberger's SwiftUI/profiling candidates, host discovery differences and audit/benchmark gaps.

## Retained measurements

- [Codex session listing on 2026-10-16](codex-session-listing-2026-10-16.json): one connection to an existing 0.163.0 server on macOS 27.0.1 returned ten loaded threads and one background terminal with null OS PID. Total wall time was 61.277 ms; proxy-only CPU was 22.798 ms. Server CPU, network and filesystem effects were not measured. See [method and limits](codex-terminal-attribution.md#cost-and-side-effects).

### Earlier process measurements

These observations were collected on Apple Silicon, macOS 27.0.1, Xcode 27 and Swift 6.4 on 2026-10-14. Session IDs and project paths/names are anonymized replacements; measurements and process relationships are retained. They describe the measured binaries and sampling windows, not current performance guarantees.

- [Sustained-watch trace and binary SHA-256](sustained-watch-2026-10-14.json): a 600.817-second headless JSONL run at the default one-second interval delivered 569 reports across 561–604 same-user processes, including 120 deliberately short-lived owned children. Average CPU was 0.805% of one core; physical footprint peaked at 8.37 MB, with warm-up/final-minute medians of 7.72/5.42 MB. No sustained growth appeared in this bounded run. The [harness](../../scripts/verify-sustained.py) uses native physical footprint (not RSS) and user/system Mach ticks converted with `mach_timebase_info`; see [reproduction commands](../development.md#terminal-and-machine-output-checks). This is not a long-duration leak guarantee or a sustained TUI measurement.
- [Claude terminal observations and independent evidence](claude-terminal-validation-2026-10-14.json): a real Java child at 13:15:45 UTC used 34.51% CPU and 85.87 MB footprint; an earlier child used 423.51% CPU. Both mapped to the same session/runtime/TTY. Allowlisted Claude session metadata, a native runtime birth-identity query and an `lsof` stdin-device check independently matched the attribution. Only relevant metadata was inspected, not transcripts. This validated native Claude terminal attribution; no heavy terminal Codex workload was observed.

Short optimized TUI smoke runs on that date used approximately 1.9–4.2% of one core, including startup and rendering. These are historical smoke observations without a retained full trace, not a sustained benchmark; rerun the [terminal check](../../scripts/verify-tui-terminal.py) for a current measurement.

# Research index

These notes record dated observations, cited source behavior, labeled inferences and unresolved empirical questions. Dates and versions apply to each investigation; editorial cleanup does not revalidate upstream sources. Raw measurements retain their original scope and limitations.

Check this index before investigating a topic, and extend the matching note rather than starting a parallel one. Every new note or retained measurement gets an entry here in the same commit.

Current behavior and accepted contracts belong in the [README](../../README.md) and [architecture](../architecture.md). Repeatable checks and live coverage belong in [development](../development.md#validation-coverage); unfinished work and scope decisions belong in [PLAN.md](../../PLAN.md). Designs built on this evidence are indexed in [proposals](../proposals/README.md) and [decisions](../decisions/README.md).

## Findings by topic

Checked dates are when the evidence was gathered; later editorial edits do not revalidate it.

| Note | Checked | Covers |
| --- | --- | --- |
| [Codex process and session identities](codex-terminal-attribution.md) | 2026-10-14; follow-ups to 2026-10-16 | Pinned marker injection, logical thread/root semantics, writer descriptors and tool-call correlation limits; the 2026-10-16 follow-up checks 0.163.0 listing scope, null OS PIDs, connection effects and one live call. |
| [Claude session metadata and messaging](claude-session-messaging.md) | 2026-10-14 | Marker lifecycle, session lookup, inbox protocol evidence and the disposable-session transport check. |
| [Claude runtime and workload attribution signals](claude-runtime-attribution.md) | 2026-10-16 | Runtime-to-session binding sources, embedded tools invoked under another name, workload environment variables and directories within one session. |
| [Process signaling and messaging interfaces](session-actions.md) | 2026-10-14 | Signal races, queue/resume interfaces, recipient identity and acceptance versus delivery. |
| [Terminal focus mechanisms](terminal-focus.md) | 2026-10-14; follow-up 2026-10-15 | Host identifiers, per-terminal APIs, macOS permission/activation behavior and untested desktop states. |
| [Menu bar feasibility](menubar-app.md) | 2026-10-15 | UI/lifecycle APIs, launch environment, process access, signing and Homebrew evidence, with unverified inferences identified. |
| [Menu bar load collection cost](menu-bar-load-cost.md) | 2026-10-15; follow-ups to 2026-10-25 | Native sampling breakdown, runtime-recognition and argument-buffer hotspots, the native row-command stall with synthetic before/after measurements, display-window aggregation costs, screenshot/source/aggregate-process evidence behind the population-overview feedback, and the overview addendum's external reviews including the capacity/compaction correction; immutable-history capacity/timing validation, the [startup retention reproduction](menu-bar-load-cost.md#startup-retention-failure--2026-10-24), the [frozen-grouping and acquisition review guards](menu-bar-load-cost.md#frozen-grouping-and-acquisition-review-guards--2026-10-25), the [unchanged-context optimization](menu-bar-load-cost.md#unchanged-context-optimization--2026-10-25), the [agent/session orientation feedback](menu-bar-load-cost.md#agent-and-session-orientation-feedback--2026-10-25), the [bounded executable-claim reuse investigation](menu-bar-load-cost.md#bounded-executable-claim-reuse--2026-10-25), and attribution/energy limits. |
| [Native menu design](native-menu-design.md) | 2026-10-15; follow-up 2026-10-24 | Apple interface guidance, pinned CodexBar/RepoBar/Trimmy source and screenshots, content-sizing API observations, iStat Menus/btop/htop resource-monitor references and unresolved live interaction questions. |
| [Swift terminal UI findings](terminal-ui.md) | 2026-10-14 | Library observations, discovery-socket failure, direct runtime behavior and bounded probe measurements. |
| [Local process observations](terminal-process-observations.md) | 2026-10-14 | Anonymized process topology, marker readability and synthetic orphan experiments. |
| [macOS measurement and attribution](macos-process-attribution.md) | 2026-10-14 | Native APIs, counter units, process identity, permissions and event-collection limits. |
| [CPU accounting coverage](cpu-accounting.md) | 2026-10-16; follow-up 2026-10-23 | First-interval, exited and short-lived lifetimes, reaped-descendant counters, unprivileged host CPU ticks, disposable exit-race and native/scheduler conservation probes, a user-authorized live build capture quantifying interval/filter sensitivity, and source-based analysis of independent acquisition, deferred evidence and adaptive sampling; adaptive behavior remains unmeasured. Includes conditional diagnostic-recording size estimates; compression ratios are unmeasured. The two external-review assessments and authorized live-load timing distinguish confirmed gaps from untested recommendations, including per-level point/support labels and recording lifecycle/authority. |
| [Existing tools and reusable mechanisms](existing-solutions.md) | 2026-10-14; follow-ups to 2026-10-17 | Inspected source, license files, maintenance observations and untested compatibility; the [2026-10-16 CLI investigation](existing-solutions.md#agent-oriented-cli-investigation--2026-10-16) adds agent-oriented guidance, finite diagnostics, discovery/schema comparisons and a constrained helper experiment; the [2026-10-17 interactive assessment](existing-solutions.md#interactive-diagnosis-assessment--2026-10-17) records local reuse evidence, cancellation/cadence observations, monitor-helper risks and the excluded-parent correction, plus unverified UI benefits; the implemented design lives in the [interactive diagnosis contract](../architecture.md#interactive-cpu-diagnosis). |
| [Development tools](development-tools.md) | 2026-10-14 to 2026-10-15 | Skill contents, Peter Steinberger's SwiftUI/profiling candidates, host discovery differences and audit/benchmark gaps. |

## Retained measurements

- [Aggregate acceptance profile on 2026-10-25](pipeline-acceptance-2026-10-25.json): optimized commit `bd87b9d`, 633 seconds with providers enabled, fixed stage/thread costs and per-window coverage; [interpretation and limits](menu-bar-load-cost.md#aggregate-acceptance-profile--2026-10-25). This one-run retention exception contains no process identities or raw traces.

- [Docker workload observations on 2026-10-24](docker-workload-2026-10-24.json): user-authorized host/client/session attribution and container Lake/Lean CPU and memory readings; [method, limits and probe-design implications](menu-bar-load-cost.md#docker-workload-attribution-and-nested-resources--2026-10-24).

- [Live heavy-load pipeline on 2026-10-24](live-pipeline-2026-10-24.json): user-requested system pressure and optimized five-second pipeline run; [method and limits](menu-bar-load-cost.md#live-heavy-load-pipeline-profile--2026-10-24) record successful finite draining but substantial resolution backlog.

- [Native row commands on 2026-10-24](native-row-commands-2026-10-24.json): synthetic command-predicate timings in session/process views and aggregate observations from the reported UI stall; [method and limits](menu-bar-load-cost.md#native-row-command-stall--2026-10-24).

- [Same-path exec identity on 2026-10-23](exec-identity-2026-10-23.json): twenty owned-child trials compare fresh/retained audit-token ports, birth/image/name observations and rising kernel peaks; [method and limits](cpu-accounting.md#controlled-same-path-exec-follow-up).

- [Live-load timing on 2026-10-23](cpu-live-timing-2026-10-23.json): provider-free production collection cost and per-scan aggregate timings during user-authorized live activity; [method and limits](cpu-accounting.md#live-load-timing--2026-10-23).

- [Live build CPU churn on 2026-10-23](cpu-churn-2026-10-23.json): read-only direct-worker counters and common-window replays at nominal 0.1–5 second cadences, with CPU filters and observed footprint peaks. The [method and limits](cpu-accounting.md#live-build-observation--2026-10-23) distinguish partial observed work from a complete load oracle.

- [Native menu bar load cost on 2026-10-15](menu-bar-load-cost-2026-10-15.json): raw sampling breakdown behind the [menu bar load cost](menu-bar-load-cost.md) note.
- [History collection cost on 2026-10-15](history-collection-cost-2026-10-15.json): all-agent summary cost at one-second and 15-second cadences; method and limits in [menu bar load cost](menu-bar-load-cost.md).
- [Native grouping getter benchmark on 2026-10-15](native-grouping-2026-10-15.json): synthetic microbenchmark from the [development tools trial](development-tools.md).
- [Codex session listing on 2026-10-16](codex-session-listing-2026-10-16.json): one connection to an existing 0.163.0 server on macOS 27.0.1 returned ten loaded threads and one background terminal with null OS PID. Total wall time was 61.277 ms; proxy-only CPU was 22.798 ms. Server CPU, network and filesystem effects were not measured. See [method and limits](codex-terminal-attribution.md#cost-and-side-effects).

### Earlier process measurements

These observations were collected on Apple Silicon, macOS 27.0.1, Xcode 27 and Swift 6.4 on 2026-10-14. Session IDs and project paths/names are anonymized replacements; measurements and process relationships are retained. They describe the measured binaries and sampling windows, not current performance guarantees.

- [Sustained-watch trace and binary SHA-256](sustained-watch-2026-10-14.json): a 600.817-second headless JSONL run at the default one-second interval delivered 569 reports across 561–604 same-user processes, including 120 deliberately short-lived owned children. Average CPU was 0.805% of one core; physical footprint peaked at 8.37 MB, with warm-up/final-minute medians of 7.72/5.42 MB. No sustained growth appeared in this bounded run. The [harness](../../scripts/verify-sustained.py) uses native physical footprint (not RSS) and user/system Mach ticks converted with `mach_timebase_info`; see [reproduction commands](../development.md#terminal-and-machine-output-checks). This is not a long-duration leak guarantee or a sustained TUI measurement.
- [Claude terminal observations and independent evidence](claude-terminal-validation-2026-10-14.json): a real Java child at 13:15:45 UTC used 34.51% CPU and 85.87 MB footprint; an earlier child used 423.51% CPU. Both mapped to the same session/runtime/TTY. Allowlisted Claude session metadata, a native runtime birth-identity query and an `lsof` stdin-device check independently matched the attribution. Only relevant metadata was inspected, not transcripts. This validated native Claude terminal attribution; no heavy terminal Codex workload was observed.

Short optimized TUI smoke runs on that date used approximately 1.9–4.2% of one core, including startup and rendering. These are historical smoke observations without a retained full trace, not a sustained benchmark; rerun the [terminal check](../../scripts/verify-tui-terminal.py) for a current measurement.

- [Controlled CPU exit and scheduler probes on 2026-10-23](cpu-exit-probes-2026-10-23.json): independent `wait4` oracles, native polling conservation/cost, exit-notification and retained-port failures, scheduler-trace results, and kernel footprint peaks across free/exec; [method and limits](cpu-accounting.md#controlled-exit-and-scheduler-probes--2026-10-23).

- [Display-window aggregation measurements — 2026-10-24](display-window-accounting-2026-10-24.json): initial, repeated and final synthetic aggregation timings; [method and limits](menu-bar-load-cost.md#independent-display-windows--2026-10-24).

- [Recent overview measurements — 2026-10-24](recent-overview-2026-10-24.json): synthetic 90/613-lifetime retention, aggregation/projection cost and whole-process RSS; [method and limits](menu-bar-load-cost.md#overview-implementation-validation--2026-10-24).

- [Review-follow-up live pipeline measurement](live-pipeline-review-2026-10-24.json): intermediate optimized collector, real provider listings, full period distribution and retention diagnostics; interpretation in the [load-cost note](menu-bar-load-cost.md#review-follow-up-live-profile--2026-10-24).

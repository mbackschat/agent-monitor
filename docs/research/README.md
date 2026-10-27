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
| [Menu bar load collection cost](menu-bar-load-cost.md) | 2026-10-15; follow-ups to 2026-10-26 | Native sampling/argument costs, row-command and aggregation measurements, population feedback, compact-history capacity, provider feedback loops, and aggregate/ordinary-launch acceptance limits. |
| [Retained-state ownership](menu-bar-load-cost.md#retained-state-ownership-audit--2026-10-26) | 2026-10-26 | Task/input/draft ownership, [collapsed-count birth provenance](menu-bar-load-cost.md#collapsed-count-birth-provenance--2026-10-26), command-sharing requirements and [population/scratch boundaries](menu-bar-load-cost.md#population-and-scratch-ownership-follow-up--2026-10-26); logical caps do not establish a heap ceiling. |
| [Native menu design](native-menu-design.md) | 2026-10-15; follow-ups to 2026-10-27 | Apple interface guidance, pinned CodexBar/RepoBar/Trimmy source and screenshots, content sizing, iStat Menus/btop/htop references, user-confirmed interaction checkpoints, [secondary-row context](native-menu-design.md#secondary-process-row-context--2026-10-26), [standalone SwiftUI table expansion](native-menu-design.md#standalone-swiftui-table-expansion--2026-10-27) and unresolved live checks. |
| [Swift terminal UI findings](terminal-ui.md) | 2026-10-14; follow-up 2026-10-26 | Host/library probes, ordered-input retention, original feedback and [source triage](terminal-ui.md#feedback-triage--2026-10-26), including truncation and [viewport pressure](terminal-ui.md#process-viewport-under-coverage-pressure--2026-10-26). |
| [Local process observations](terminal-process-observations.md) | 2026-10-14 | Anonymized process topology, marker readability and synthetic orphan experiments. |
| [macOS measurement and attribution](macos-process-attribution.md) | 2026-10-14 | Native APIs, counter units, process identity, permissions and event-collection limits. |
| [CPU accounting coverage](cpu-accounting.md) | 2026-10-16; follow-ups to 2026-10-26 | Polling/newborn/exit coverage, child-counter correctness, native/scheduler probes, live-build timing, exec evidence and conditional recording-size arithmetic. |
| [Adaptive sampling prototype](cpu-accounting.md#adaptive-sampling-offline-prototype--2026-10-27) | 2026-10-27 | Closed-loop synthetic idle savings, short-worker phase losses, persistent-read-failure comparison and the limits of scan count as a native-cost proxy. |
| [Supplemental inspection observations](cpu-accounting.md#supplemental-inspection-observations-source-review--2026-10-26) | 2026-10-26 | Census/identity/freshness source constraints and the [bounded native comparison](cpu-accounting.md#bounded-inspection-comparison-retry--2026-10-26): better 50 ms-worker capture, persistent shorter-worker loss and cost above the absolute target. |
| [Exit accounting alternatives and workload evidence](cpu-accounting.md#exit-accounting-alternatives-and-workload-evidence--2026-10-26) | 2026-10-26 | User-reported build/runtime workload families; source-supported cumulative exit CPU and exact-lifetime trace linkage; root/private-interface, endpoint and event-loss limits; ES/BSD accounting and Docker/Linux alternatives. No complete native CPU/memory backend is validated. |
| [Activity Monitor data path](cpu-accounting.md#activity-monitor-data-path--2026-10-26) | 2026-10-26 | Installed binary imports, private client entitlements and sysmond access checks; separate host/process/coalition mechanisms and limits of Apple's documented process and energy views. No complete exited-worker accounting or public replacement API established. |
| [Transparent coalition coverage](cpu-accounting.md#transparent-coalition-coverage-feasibility--2026-10-26) | 2026-10-26 | Source/SDK SPI review and bounded owned-fixture follow-up: CLI access observed, shared-coalition reconciliation inconclusive, invalid harness cross-check excluded; ordinary app launch supplies no documented isolation guarantee or unseen-session attribution. |
| [Existing tools and reusable mechanisms](existing-solutions.md) | 2026-10-14; follow-ups to 2026-10-17 | Pinned source/licenses, CLI discovery/schema comparisons, constrained helper exercise and finite-diagnosis/helper-identity feasibility; live usability remains unmeasured. |
| [Development tools](development-tools.md) | 2026-10-14–15; source audit 2026-10-26 | Skill contents/discovery, first source trial, grouping/sizing observations and [test-oracle limitations](development-tools.md#test-value-audit--2026-10-26). |

## Retained measurements

- [Adaptive sampling synthetic comparison on 2026-10-27](adaptive-sampling-2026-10-27.json): 54 scenarios × three schedules through production acquisition with a virtual clock; [method and limits](cpu-accounting.md#adaptive-sampling-offline-prototype--2026-10-27). Contains synthetic aggregate results and source hashes, not recorded user processes or native overhead measurements.

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

# PoC validation

Publication note: session IDs, local project paths/names, and a project-specific process name in these observations are consistently anonymized. Measurements and process relationships are retained; the identifiers are illustrative replacements, not original session values.

## Environment and scope

Validated on 2026-10-14 using Apple Silicon, macOS 27.0.1, Xcode 27, and Apple Swift 6.4. This validates the current headless implementation and small CLI harness, not all macOS versions or provider installations. No Homebrew packages, privileged helper, hooks, or monitoring service were installed.

The default filter is strictly above 25% interval CPU or 1,000,000,000 bytes physical footprint. CPU uses one core as 100%; a process can exceed 100%. Only same-user processes are sampled. Missing access and disappearing processes remain inspection failures, not zero-resource observations.

## Automated evidence

- Swift Testing: 30 core, 15 CLI/presentation, and one real-terminal test function passed in the integrated TUI run on 2026-10-14, including parameterized cases. Changes followed failing-then-passing tests. The CLI regression test checks sample timestamps, concise ambiguity reporting, and retention of full candidate IDs in JSON.
- Attribution tests cover exact session IDs, sessions sharing a directory, nested runtimes, orphan history, PID reuse, conflicting markers, multiple writer locks, executable changes, and terminal enrichment.
- Native measurement tests compare converted resource counters with `CLOCK_PROCESS_CPUTIME_ID` and inspect the current process's identity, directory, and footprint. The Apple Silicon Mach timebase conversion is essential; treating raw ticks as nanoseconds undercounts CPU.
- The controlled process check uses disposable Swift executables with Codex/Claude names and markers, independent terminal roots, a scrubbed-marker writer-lock fallback, and a detached worker. It checks six heavy workers against exact expected sessions and excludes one small worker. These are synthetic process fixtures, not actual provider conversations.
- Formatting passed with `swift format lint --strict --recursive Sources Tests Package.swift`. Optimized release compilation succeeded with the sandbox-specific dSYM workaround described in [development guidance](development.md#restricted-agent-environments).

Apple Argument Parser 1.8.2 migration verification also passed: `--help` and `-h` return 0; invalid values and unknown options return 64 with usage; equals syntax, one default report, and two JSON reports retain their behavior. The optimized executable passed the controlled attribution check again. SwiftTUI checks are recorded separately in [TUI research](research/terminal-ui.md).

Reproduce with the commands in the [development guide](development.md#build-and-verify). The [skill setup test](../scripts/test-skills.sh) separately verifies both discovery symlinks, revision pinning, explicit updates, and protection of local edits using local Git repositories. Actual upstream installation completed on 2026-10-14: `bash scripts/skills.sh check` verified the locked revisions and both hosts' discovery paths, and a separate check confirmed all references listed by the skill entry points and both licenses are present. Codex discovered both project-local skills. A live Claude Code session on 2026-10-14 also listed both project-local skills in its catalog; `bash scripts/test-skills.sh` passed.

## Live observations

These are observations from separate sampling windows, not simultaneous totals or continuing claims about these PIDs. Physical footprint is decimal GB.

| Workload | Observed usage | Session evidence |
|---|---|---|
| Java PID 16974 in `sample-java-project` | 358.8% CPU, 1.12 GB | Claude session `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa`, terminal `ttys015` |
| Node PID 89473 in `sample-agent-project` | Approximately 95.7% CPU | Claude session `bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb`, runtime PID 25388, terminal `ttys016` |
| Kotlin daemon PID 74587 | Approximately 2.21 GB | Inherited Claude marker `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa`; its parent Gradle daemon was already detached |
| This PoC's compiler workload | Approximately 95% CPU during compilation | Codex thread `dddddddd-dddd-4ddd-8ddd-dddddddddddd` |
| Shared Codex host PID 46427 | Approximately 1.43 GB | Native Codex runtime, but many writer locks; correctly reported ambiguous logical thread |

The final optimized sample at 11:05:20 UTC also resolved a new Java worker to the same Claude session and `ttys015`. OneDrive, Spotlight, Finder, and Terminal appeared as heavy consumers when above thresholds and remained unattributed. No actual user workload was terminated.

During the subsequent test drive, Node PID 2385 used 99.96% CPU and resolved to Claude session `bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb` on `ttys016` in `sample-agent-project`. `lean-worker` PID 2104 used 96.81% CPU and resolved to Claude session `cccccccc-cccc-4ccc-8ccc-cccccccccccc`, runtime PID 20005, on `ttys012` in `sample-lean-project`. A three-report run of the final release ended at 11:12:43 UTC after those CPU workloads had subsided; the shared Codex host still used roughly 1.48 GB and correctly remained ambiguous across 32 candidate threads. Text output showed timestamps and a candidate count; full IDs remain available in JSON. Independent follow-up verification is recorded below.

An inherited marker establishes **launch origin**. A shared Gradle, Kotlin, or MCP daemon may subsequently serve other sessions; the PoC does not establish which client caused its current load. Actual Codex-owned compiler descendants were observed, but a heavy worker under a real terminal Codex root has not yet been validated end to end; terminal Codex coverage currently comes from controlled fixtures.

## Monitor overhead

A five-report optimized run with a one-second wait used 0.055 CPU seconds over 5.528 wall seconds: approximately **0.99% of one core**, with 595 same-user processes in the final report. This is a short measurement on a busy machine, not a formal benchmark or guaranteed ceiling. Measurement used the subprocess's user plus system CPU time from `getrusage(RUSAGE_CHILDREN)`, divided by elapsed monotonic wall time.

The initial implementation measured 17.08% under a comparable five-report run. Profiling located the dominant cost in resolving terminal device names for every sampled terminal process: roughly 175 ms per scan versus roughly 7 ms for native identity, usage, and path reads. The final reader carries the raw terminal device through sampling and resolves its name only for relevant agent runtimes during enrichment. The regression test preserves terminal presentation after that separation.

## Remaining limitations

Sampling can miss short-lived work, and CPU requires two observations. A preexisting detached process without accessible explicit markers may remain unknown. Successful argument inspection does not guarantee that the environment includes session markers. Only the observed native Claude installation is validated; npm roots and desktop conversation attribution need separate work. Shared daemon causality, Intel hardware, operation beyond the bounded ten-minute run below, and substantially larger process populations remain unvalidated.

## Independent live-session verification (2026-10-14)

At 12:11:09 UTC, the user’s release run attributed three heavy Lean workers to Claude runtime 20005, session `cccccccc-cccc-4ccc-8ccc-cccccccccccc`, project `sample-lean-project`, and terminal `ttys012`. The agent independently sampled two more reports at 12:12 UTC and observed further heavy Lean workers in the same session, plus workers in `sample-agent-project` and `sample-graph-project`.

Independent provider metadata in `~/.claude/sessions/20005.json` identifies the same PID, session ID, project, and process start time; `/usr/sbin/lsof -a -p 20005 -d 0 -Fn` independently resolves stdin to `/dev/ttys012`. Session metadata for runtimes 25388 and 52310 also matches the monitor’s session IDs and project directories. Only allowlisted metadata fields were inspected; no conversation content or session key files were read. This verifies the live report’s session mapping without asking the user to perform the verification.


## Shared pipeline and live terminal integration (2026-10-14)

Text, JSONL, and the TUI consume `MonitoringSession` snapshots. Deterministic tests prove sequential baseline/wait/scan/enrich/deliver behavior, cancellation, configuration bounds, and propagation of collection/consumer errors. Scope tests hide unrelated processes by default while retaining agent-associated unknown, ambiguous, and conflicting evidence. The optimized binary again passed the six-worker controlled attribution check after integration.

The independent draft-2020-12 validator accepted two live JSONL reports, rejected five malformed record variants, and confirmed that `--json-schema --interval 60` exits immediately. Piped `--tui` exits with usage status 64 and explains the interactive terminal requirement. The generated help covers both TUI spellings, mode conflicts, continuous versus one-report defaults, resource units, and keyboard controls.

The production TUI adapter passed a controlled real-PTY journey: one-second updates, changing CPU order, persistent selected process/disclosure, PID ascending/reversed sorting, resize from 100×24 to 60×16, collapse, Ctrl-C, exit status 0, restored termios flags, cursor, and alternate screen. Separate live checks passed `q`, bounded sample completion, color/Ctrl-C, and `NO_COLOR`/SIGTERM. Pure presentation tests cover sorting, unavailable measurements, stable ties, PID reuse, disappearing findings, narrow layouts, threshold markers, and bounded detail scrolling.

A normal optimized build of the official SwiftTUI 0.14.0 dependency and monitor succeeded in 220.08 seconds. Two ten-second live TUI runs used 0.244 CPU seconds over 10.320 wall seconds (2.37% of one core) and 0.251 over 10.306 seconds (2.44%). Child peak RSS high-water mark was 34.4 MB, not physical footprint. These include startup/shutdown and real sampling on a busy host; sustained headless behavior is measured separately.


The final optimized fixture also passed the expanded PTY journey, including repeated detail-scroll input followed by immediate reverse scrolling after resize. Final live cleanup runs used 2.46% and 1.85% of one core, with a 34.3 MB child RSS high-water mark. The final release also passed an agent-only scope assertion and noninteractive-TUI rejection. These repeat checks validate the final presentation changes; the shared collector was unchanged during the sustained measurement.


## Real terminal Codex validation attempt (2026-10-14)

Sixty reports at two-second intervals from 12:35:58 to 12:38:04 UTC found no heavy terminal Codex process. A separate all-process inventory found real terminal Codex runtimes 633 (`ttys014`, 0.016% CPU, 0.503 GB), 75829 (`ttys003`, 0.652%, 0.172 GB), and 96723 (`ttys004`, 0.061%, 0.084 GB), all below the default thresholds. Independent `lsof -a -p 633,75829,96723 -d 0 -Fn` matched all three terminal devices. Their reports had no thread writer-lock candidate and remained `runtimeOnly`; a separate `lsof` file-descriptor inventory also found no `thread-writer-locks` path for those PIDs.

The active heavy Codex compiler work belonged to shared nonterminal runtime 46427, so it cannot satisfy the terminal-session acceptance check. No agent task was submitted to manufacture load. At that stage POC-05 remained open pending a suitable workload. The user subsequently directed validation against Claude Code; the completed check is recorded below.


## Sustained optimized watch (2026-10-14)

The headless JSONL watch ran from 12:40:13 UTC for 600.817 seconds at the default one-second interval and heavy thresholds. It delivered 569 reports while sampling 561–604 same-user processes. The harness created and reaped 120 short-lived `sleep` processes in six-process batches every thirty seconds, alongside natural host churn. No user workload was terminated. [Raw measurements and binary SHA-256](research/sustained-watch-2026-10-14.json) are retained for review; the shared collector was unchanged by the final presentation-only edits.

The independent harness uses macOS `proc_pid_rusage` v2 physical footprint and user/system Mach ticks converted with `mach_timebase_info`, divided by monotonic elapsed time. This is physical footprint, not RSS. The reproducible command is `python3 scripts/verify-sustained.py .build/release/agent-monitor --output /tmp/agent-monitor-sustained.json`.

| Measurement | Result |
|---|---|
| Average CPU, one core = 100% | 0.805% |
| Initial / final physical footprint | 3.64 / 7.08 MB |
| Peak physical footprint | 8.37 MB |
| Warm-up median, seconds 30–60 | 7.72 MB |
| Final-minute median | 5.42 MB |
| Reports / deliberately churned processes | 569 / 120 |

The initial baseline grew into a small working set, but the trace did not show sustained growth: minute medians stayed between 4.41 and 8.37 MB after the first minute and fell to 5.42 MB in the final minute. The final-minute median was below the warm-up median. This bounded run supports continued PoC use at one-second cadence on this host; it is not an hours-long leak guarantee, population-scale benchmark, or sustained TUI measurement. Short live TUI measurements are recorded separately above.

No heavy terminal Codex finding appeared during this additional ten-minute window. This did not validate real terminal Codex attribution. The later user-directed Claude Code check below closes the PoC gate without treating synthetic tests or shared-host observations as terminal Codex evidence.


## Real terminal Claude Code validation (2026-10-14)

At the user’s direction, the remaining terminal-session acceptance check was changed from Codex to Claude Code. A fresh fifteen-report watch from 13:15:20 to 13:15:50 UTC captured Java PID 49880 at 34.51% CPU and 85.87 MB footprint at 13:15:45 UTC. Its observed ancestry was `49880 ← 49851 ← 88196`; it resolved to session `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa`, runtime 88196, terminal `ttys015`, and `sample-java-project`. This exceeds the default CPU threshold and is an actual user workload, not a synthetic fixture.

Three independent checks matched: Claude’s `~/.claude/sessions/88196.json` supplies the same runtime PID, session ID, and project directory; a direct `proc_pidinfo(PROC_PIDTBSDINFO)` query confirms runtime birth identity `1791970394325683` microseconds; and `lsof -a -p 88196 -d 0 -Fn` confirms stdin `/dev/ttys015`. Only allowlisted provider metadata and the relevant descriptor were inspected. A stored report from 12:52:11 UTC also records Java PID 48937 at 423.51% CPU under the same runtime and session. [Retained observations and independent evidence](research/claude-terminal-validation-2026-10-14.json) make both checks reviewable.

The initial fresh samples also showed detached Kotlin/Gradle Java daemons around 1.60 GB and 1.03 GB carrying the same Claude launch marker. Their runtime/TTY remained unverified, and they were not used to satisfy the terminal-session test. Launch-origin evidence still does not prove which client currently uses a shared daemon.

POC-05 is complete for Claude Code. The implementation, terminal interaction tests, schema validation, controlled attribution cases, project-local skills, and sustained-operation evidence fulfill the remaining plan items. A real heavy child of a terminal Codex session remains unvalidated and is explicitly retained as a coverage limitation.

## Fixed TUI details split (2026-10-14)

Red/green regressions cover fixed pane geometry with changing process counts, explicit row selection, disappearing processes, remembered ratios, bounds, minimization/maximization/restoration, and terminal resizing. The presentation layer allocates and pads the panes independently of content; SwiftTUI renders each line in exactly one row. The [architecture contract](architecture.md#tui-contract) and generated CLI help describe the controls.

The final test run passed all 49 functions (30 core, 18 CLI/presentation, one real PTY journey), using the rebuilt release fixture for terminal interaction. The PTY oracle checks exact divider rows after `+`, `9`, `0`, `=`, `-`, and resizing from 100×24 to 60×16; it also covers scrolling, sorting, disclosure, and restored terminal attributes/cursor/alternate screen. An earlier full debug run had a PTY timeout; an isolated rerun and the final release-fixture run passed. The transient timeout's cause was not established.

The normal release build completed in 378 seconds with the unchanged upstream SwiftTUI dependency. Formatting passed. Two five-second live release checks passed color/Ctrl-C and NO_COLOR/SIGTERM cleanup. Their short-run CPU measurements were 4.16% and 3.11% of one core, with 40.1 MB child peak RSS; these are startup-inclusive smoke measurements, not physical footprint or a sustained performance claim. No collection or attribution logic changed.

## Terminal text selection (2026-10-14)

The default `TerminalHost()` enabled mouse-reporting modes, routing drag events to the application instead of native terminal selection. A regression in `scripts/verify-tui-terminal.py` rejects DEC private mode sequences enabling mouse tracking or mouse coordinate reporting, including combined mode sequences. It failed independently in color and NO_COLOR runs against the previous release executable.

The host now uses the public SwiftTUI 0.14.0 option `mouseInputResolution: .preResolved(.disabled)`. After rebuilding release, both smoke variants passed, including Ctrl-C/SIGTERM and terminal restoration. The release-fixture keyboard, split, resize, and scrolling journey passed in 2.388 seconds, and formatting passed. This verifies that the application no longer captures terminal mouse selection; clipboard commands and selection retention during redraws remain terminal behavior and were not GUI-automated.

## Table alignment and session grouping (2026-10-14)

The alignment regression reproduced misplaced columns in compact and wide layouts, including CPU `189.90*`, footprint `1.02*`, unstarred values, unavailable CPU, and varying PID lengths. Explicit shared padding replaced the Foundation object-format width specifiers, and each numeric column now reserves its own marker cell. Header/process/provider/terminal column offsets and numeric endpoints pass the regression.

Grouping tests cover corroborated root/child merging, exact-session fallback without root evidence, same-directory separation, provider separation, unresolved and ambiguous entries, duplicate identity suppression, known-only partial totals, group-total sorting, expansion/selection across refreshes, and PID reuse. The CLI option and grouped text report are exercised; JSONL/schema modes reject session grouping. A narrow-layout regression first failed for an unmarked partial total and now passes with `~` beside its numeric value.

All 56 Swift test functions passed (30 core, 25 CLI/presentation, one PTY journey). The PTY journey additionally toggles grouping, expands an unresolved group without merging its sibling on the same runtime, selects the process, opens its details, and returns to flat view. It passed against the release fixture in 2.261 seconds. Formatting and the normal release build passed; the build took 212.56 seconds. A live text snapshot produced launch-session summaries while leaving the ambiguous shared Codex host separate; this checks output behavior, not new attribution evidence.

`python3 scripts/verify-tui-terminal.py .build/release/agent-monitor --seconds 3 --group-session` passed grouped startup, disabled mouse reporting, color/NO_COLOR, Ctrl-C/SIGTERM, and terminal restoration. Short startup-inclusive CPU measurements were 3.27% and 3.49% of one core, with peak child RSS 35.1 MB and 38.7 MB respectively. These are smoke measurements, not sustained performance results. The grouping projection uses only heavy findings; root corroboration can therefore be unavailable when no root-thread finding appears. The [architecture](architecture.md) describes the exact fallback and totals contract.

## Readable controls and live filters (2026-10-14)

The key legend now separates navigation, filter adjustments, and details-pane controls with consistent spacing. Whole controls wrap at narrow widths; insufficient-height windows show a resize hint and quit keys. A dedicated threshold row stays visible in grouped mode and alongside disappearance notices. The settings preserve the CPU OR footprint rule: `1`/`2` change CPU by 10 percentage points, `3`/`4` change footprint by 1 decimal GB, with zero as the lower bound. Changed values are labeled pending until a snapshot reflects them.

Red regressions reproduced the missing settings in both grouped and disappearance-notice states and missing key labels at 60- and 100-column widths. Live-control tests initially failed to compile because no update path existed. The implemented UI-independent supplier reads one threshold pair per sample for enrichment, filtering, and snapshot fields. Deterministic tests recover previously omitted processes through both CPU and footprint changes, retain the baseline and exact attribution, reject invalid CPU thresholds, and guard zero/overflow boundaries. Layout tests cover complete legends at 40, 60, and 100 columns and bounded tiny-window output.

All 64 Swift test functions passed, including the real PTY journey. Strict formatting passed. The optimized executable and fixture were rebuilt with `-debug-info-format none`; the PTY journey also passed against the release fixture, including threshold changes that remove and restore both processes. The live release passed grouped startup, color/NO_COLOR, disabled mouse reporting, Ctrl-C/SIGTERM, cursor restoration, and terminal-attribute restoration. Generated release help includes the new bindings and units. Documentation links and the shared skill symlinks were checked. At that checkpoint the adapter design was a proposal only; no adapter refactoring or plugin loader was implemented. The later built-in extraction is documented in [architecture](architecture.md#agent-attribution-adapters).

## Responsive terminal layout (2026-10-14)

Header allocation now follows terminal width: one row at 120 columns and above, two at 85–119, and three below 85. Key groups share rows whenever they fit; an oversized group wraps only between whole controls. A 120×24 flat report with minimized details now has room for 19 process rows instead of 16. At 200 columns, the full key legend occupies one row. Width-based header allocation keeps the divider stable across refreshes and disappearance notices, and detail-scroll limits use the same available-height calculation as rendering.

The table reserves aligned numeric fields and threshold markers, then allocates descriptive space across process, provider/session, and terminal/project columns. Wider views reveal longer process names and session IDs; a 160-column regression displays the full UUID alongside a long process and project name. Compact views omit the terminal/project column and reserve separate process and agent/session widths. A second red regression reproduced a long process name pushing the session entirely off a 60-column screen; the compact allocation now preserves that session abbreviation. The small-window fallback also respects both viewport dimensions.

Red/green tests cover the recovered process capacity and long-name/session behavior. All 67 Swift test functions pass, including viewport cases across widths 1–200 and heights 3–24, column alignment, all key labels, and stable detail geometry. The real PTY journey resizes through 120, 200, 80, 100, and 60 columns while checking table/header/footer positions, disclosure, sorting, filter hide/recover behavior, scrolling, and terminal restoration. Strict formatting and whitespace checks pass.

The optimized executable and fixture were rebuilt. The expanded PTY journey also passed against the release fixture, and the live grouped release passed color/NO_COLOR, disabled mouse reporting, Ctrl-C/SIGTERM cleanup, cursor restoration, and terminal-attribute restoration.

## Content-sized process column (2026-10-14)

The process column contains names only, so allocating it a fixed share of surplus terminal width padded short names while truncating useful session information. It now measures the longest name across current findings, keeps enough room for the `PROCESS` heading, and respects the existing viewport-dependent cap. Width recovered from short names goes to session identity and terminal/project information. Executable paths and optional arguments remain in details.

Red regressions reproduced excess padding for both short (`codex`, `java`) and medium-length names at 60, 85, 120, 160, and 200 columns. Green regressions verify content-sized widths and header/row alignment, plus a complete Claude UUID and project name beside `java` at 120 columns. Existing long-name, viewport-bound, and resize guards still pass. All 69 Swift test functions and strict formatting pass; the optimized executable and fixture are rebuilt.

The multi-width PTY journey also passed against the release fixture, covering resize, sorting, selection, details, filter changes, scrolling, and terminal restoration.

## Public release verification (2026-10-14)

[Release v0.1.0](https://github.com/mbackschat/agent-monitor/releases/tag/v0.1.0) is published from the sanitized initial commit under MIT. The public source scan covered all 70 files, including the image asset and symlink targets, and the binary archive scan covered 322 entries. Known private session IDs, local project names/paths, and credential patterns were absent. Archive headers contain no build-account user/group values. Original unpublished history is retained only in a local backup, outside the pushed refs.

The archive and checksum downloaded anonymously from GitHub matched the locally audited bytes. After extraction outside the checkout, `--version` returned `0.1.0`, `--json-schema` parsed successfully, and `codesign --verify` passed. This validates the existing ad-hoc signature; it does not imply Developer ID signing, notarization, or a Gatekeeper-approved download. The 70-test suite and release PTY journey passed before packaging; the anonymized display fixture also passed after sanitization.

## Homebrew distribution (2026-10-14)

The [public tap](https://github.com/mbackschat/homebrew-tap) installs the existing v0.1.0 archive by its published SHA-256. `brew audit --strict mbackschat/tap/agent-monitor` passed. A fresh `brew install mbackschat/tap/agent-monitor` cloned the public tap and installed the command; `brew test mbackschat/tap/agent-monitor` verified the reported version and JSON Schema loaded from the packaged resource bundle. The installed launcher also passed color/NO_COLOR, Ctrl-C/SIGTERM, mouse-selection-mode, and terminal-restoration checks using the terminal verification script. Homebrew’s automatically enabled developer mode was restored to its prior off setting after validation.

## Process actions (2026-10-14, unreleased)

The current source adds confirmed single-process SIGTERM and Codex queued messages. The optimized build, both PTY journeys against the optimized fixture, CLI help/schema smoke checks, strict Swift formatting, contributor doctor and preview freshness also passed. All 90 Swift test functions pass, including native termination of a disposable `sleep` child, stale lifetime/changed attribution rejection, independent inspection below display thresholds, root/selected routing, literal message arguments, bounded timeouts and fake Codex WebSocket protocol exchanges. Fake-server cases cover upgrade validation, client masking, fragmented responses with ping/pong, oversized frames, closure, unknown statuses, unavailable/missing roots, and queue uncertainty. No real workload was signaled and no agent message was sent.

The real PTY journeys cover the existing dashboard plus confirmation, a frozen target, root/selected choice, automatic PID context, bracketed paste containing control bytes, and refusal to confirm a hidden panel after resizing below 40×8. Review layout tests cover narrow/wide terminals and wide Unicode message text. At 60 columns, the added action key group needs one extra footer row; common widths retain their previous footer height. The generated README SVG passes freshness checks and was inspected in headless Chrome with a fresh temporary profile; glyphs remain unscaled.

A read-only probe using the production Swift `CodexMessaging` adapter verified the current local Codex CLI 0.162.1 app server: the selected UUID matched, the root was available, and this root session yielded one recipient choice. The initial JSONL probe timed out because `app-server proxy` forwards raw WebSocket bytes. Reproducing that mismatch with a fake WebSocket server failed before adding the upgrade/framing layer and passed afterward. No transcript turns were requested (`includeTurns: false`); no IDs or conversation content were retained in this record. Live child-recipient routing and actual queue delivery remain untested.

## Claude Code messaging (2026-10-14, unreleased)

The source now routes `s` for Claude Code rows to a Claude adapter that verifies the runtime/session binding with `claude agents --json` and hands one message line to the session's documented inbox socket, located from the workload's `CLAUDE_CODE_MESSAGING_SOCKET`. Red/green tests cover inbox parsing beside its own session marker, unusable paths that leave attribution intact, the marker staying out of JSONL, provider routing, a fake `claude agents --json` (other session, missing/duplicate PID, unknown status, exited session, malformed output, CLI failure), an unauthenticated single-line post to a fake inbox, missing/regular-file/symlinked/stale sockets reporting that nothing was sent, a bounded uncertain result when the inbox never closes, and provider-specific acceptance wording. The full Swift suite and strict formatting passed.

With the user's approval, the production path was also exercised once against a disposable `claude -p` session (Claude Code 2.1.300, Haiku, safe mode, no persistence) whose Homebrew Python child carried the session environment: the message was routed to the session queue as a peer message and answered in a new turn. No existing Claude session was messaged. Details and the platform-binary environment limitation are in [Claude session messaging research](research/claude-session-messaging.md#live-transport-check-2026-10-14).

A separate pre-existing limitation remains in report-table sizing: it measures process/session text by character count rather than terminal-cell width, so wide Unicode names can misalign columns. Action panels use conservative cell budgeting to keep their full review text visible; changing the report table is outside this action checkpoint.

## Detached Codex jobs (2026-10-15, unreleased)

The missing runtime lookup was reproduced before the fix with both a directly marked detached worker and a child inheriting a detached ancestor's marker. Both retained their exact thread but lacked runtime and terminal context. The native [process fixture](../Tests/Fixtures/SessionFixture.swift) also failed its runtime assertion: an intermediate launcher exited, the worker verified its own parent was PID 1 before announcing readiness, and the synthetic Codex runtime remained alive with an open thread writer descriptor. The monitor started after detachment, so captured ancestry could not supply the answer.

After the fix, the [native verification script](../scripts/verify-poc.py) mapped all seven heavy fixtures to their exact Codex/Claude sessions, including the detached job's correct live runtime and terminal context. A separate orphan whose runtime had exited retained its thread marker with no runtime. Deterministic regressions cover inherited markers, separate threads under one root, multiple writer descriptors, same-directory runtimes, duplicate matches, missing locks, wrong providers, later runtime starts, and refreshing candidate evidence after a successful match. The resolver uses the marker-bearing process's lifetime, not a younger descendant's lifetime, for the start-time guard.

All 152 Swift test functions passed across the suite and an isolated retry of `terminalRefreshDisclosureResizeAndRestoration`. That existing PTY test passed in the initial sandboxed run, timed out in the full run outside the sandbox, and passed on retry; its timing-sensitive screen check was not changed. The full suite needed permission to bind its disposable Unix-socket fixtures. Strict Swift formatting, whitespace checks and the built preview generator's freshness check passed. Validation used the updated debug executable and synthetic processes; real terminal Codex workload validation remains outstanding. No live agents were messaged or real workloads signaled.

## Shared runtime label (2026-10-15, unreleased)

Red/green presentation tests reproduced and corrected the shared Codex runtime's unresolved wording in flat/grouped text reports, TUI rows/details and action targets. Guards cover unresolved descendants, single and duplicate writer IDs, unknown/other providers, exact sessions and mismatched process lifetimes. A grouping regression keeps the shared runtime, its exact-session workload and its unresolved workload in separate groups. JSONL retains ambiguous evidence and all candidate IDs, with no display label added to the wire contract.

All 77 presentation/CLI, preview and PTY test functions passed, along with strict Swift formatting and whitespace checks. The synthetic README fixture now includes a shared Codex runtime. The preview script's build stalled in the SDK cache subprocess; the already-built production preview generator regenerated and checked the SVG successfully. Its appearance was reviewed in headless Chrome with a fresh isolated temporary profile. A read-only live report also showed the shared-runtime label for the user's daemon, whose multiple writer threads and absent terminal explain why no single session or terminal can be selected from that process row. No terminal focus, messages or workload signals were exercised.

## Built-in attribution adapters (2026-10-15, unreleased)

Codex and Claude runtime recognition, marker allowlists/validation, descriptor decoding, detached-runtime link rules and shared-runtime interpretation now live behind the internal `AgentAttributionAdapter` contract. Production sampling, action lookup and process argument parsing use the same built-in registry. Native inspection and process-lifetime/ambiguity decisions remain in the shared host. The provider enum, snapshot/JSONL contract and rendered preview are unchanged.

New contract tests verify duplicate-provider rejection, overlapping executable claims in both registration orders, adapter-declared environment and observation inputs, malformed-marker handling, native executable shapes and writer-file decoding. A synthetic adapter drives a marked detached workload through the shared enrichment and resolution path to an exact session/runtime/terminal, without using built-in executable names or marker keys. Existing nested-marker, same-directory, PID-reuse, detached-runtime, native reader, shared-runtime display and action tests remain green.

All 162 Swift test functions passed with the permissions needed by disposable Unix-socket fixtures. The native verification script mapped all seven heavy workers to exact sessions, including the exited intermediate shell and the exited runtime cases; the low-load worker remained excluded. Strict Swift formatting, whitespace checks and the built preview generator's freshness check passed. No live agent messages, terminal focus or real-workload signals were used. [Architecture](architecture.md#agent-attribution-adapters), [contributor guidance](development.md#changing-attribution-adapters), [CLAUDE.md](../CLAUDE.md) and support claims now describe the implemented boundary separately from deferred capabilities.

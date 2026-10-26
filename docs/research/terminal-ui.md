# Swift terminal UI findings

Checked 2026-10-14 with Swift 6.4 on Apple Silicon/macOS 27. Sources and an isolated synthetic SwiftTUI probe were inspected; the probe was subsequently removed. The adopted host and dependency boundary are documented in [architecture](../architecture.md#swifttui-host-evaluation); this note records the evidence behind them.

## Libraries inspected

| Library | Findings and limits |
|---|---|
| [SwiftTUI/swift-tui](https://github.com/SwiftTUI/swift-tui/tree/0.14.0) | Version 0.14.0, revision `581c3ab7e2383ce86fcebe36e81041aecac443a5`, built with Swift 6.4. `SwiftTUIRuntime` and `SwiftTUICLI` expose a terminal host without compiling the umbrella's web host. The scene launcher has a separate discovery-socket requirement. |
| [phranck/TUIkit](https://github.com/phranck/TUIkit) | Documentation describes tables, lists, focus, keyboard handling and lifecycle. Upstream labeled the API work in progress; no local runtime comparison was performed. |
| [rensbreur/SwiftTUI](https://github.com/rensbreur/SwiftTUI) | A distinct repository with a SwiftUI-like API, scrolling and keyboard focus. Compatibility with this toolchain was not tested. |
| [Tuist Noora](https://noora.tuist.dev/components/tables/static) | Documentation establishes CLI components and static tables, not the complete continuously updating screen lifecycle needed here. |

## Sandbox-compatible terminal host

The scene-based probe rendered once and exited with `Failed to bind discovery socket ... Operation not permitted`. The tagged [TerminalRunner](https://github.com/SwiftTUI/swift-tui/blob/0.14.0/Platforms/CLI/Sources/SwiftTUITerminalCLI/TerminalRunner.swift) creates a discovery server even for a single window. Selecting a terminal-only package product did not avoid that IPC.

The documented [RunLoop entry point](https://github.com/SwiftTUI/swift-tui/blob/0.14.0/Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Running-Apps.md) worked with `TerminalHost`, `InputReader`, `SignalReader`, state and focus tracking. The probe did not start `TerminalRunner`, a browser or a discovery service. SwiftTUI retained ownership of raw mode, drawing, input and cleanup; no upstream fork or permission change was needed. Test-only screen helpers used the pinned framework's testing SPI.

## Observed behavior and limits

The synthetic PTY journey passed refresh, disclosure, resizing from 100×24 to 60×16, Ctrl-C and restoration of terminal flags, cursor and alternate screen. Separate runs passed color/NO_COLOR and SIGTERM cleanup. Debug smoke runs used about 6.3% of one core and 42 MB peak RSS; optimized smoke runs used 1.28–1.60% and 26.2 MB. These short, startup-inclusive measurements describe the probe, not the production collector or physical footprint.

The PTY peer had to keep draining output while awaiting exit: the tagged POSIX controller's `TCSAFLUSH` restoration waited for queued output. Stopping reads falsely reported a hung child with both Foundation `Process` and `posix_spawn`; draining corrected it. This probe finding does not explain every later PTY timeout.

An uninterrupted optimized build completed in 482 seconds. Earlier terminated builds did not establish an upstream compiler incompatibility. The tagged styling API was `.foregroundStyle`; examples for other revisions or the similarly named repository are not evidence of 0.14.0 compatibility.

The probe did not inspect processes or validate attribution. Production [terminal checks](../development.md#terminal-and-machine-output-checks), [coverage limits](../development.md#validation-coverage) and [measurements](README.md#retained-measurements) are separate evidence.

## Ordered input and retention boundary — 2026-10-26

Provenance: source review of Agent Monitor `e798ec9` and the locked SwiftTUI 0.14.0 revision `581c3ab7e2383ce86fcebe36e81041aecac443a5`, independently checked by a read-only review. No build, terminal stress test, native profile or workload observation was performed for this investigation. These are source mechanisms, not measured heap sizes or observed user failures. The earlier [retained-state audit](menu-bar-load-cost.md#retained-state-ownership-audit--2026-10-26) identified the streams; the following review traces the entire input path.

| Stage | Pinned source | Finding |
| --- | --- | --- |
| Raw read turn | [TerminalInputStreamReading.swift](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Sources/SwiftTUIRuntime/Input/TerminalInputStreamReading.swift#L103) | `drainAvailableTerminalInput` appends 256-byte reads until EAGAIN, EOF or error; 256 bounds a syscall, not the accumulated array. A continuously readable descriptor can keep the dispatch handler occupied. |
| Partial decoding | [TerminalInputParser.swift](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Sources/SwiftTUIRuntime/Input/TerminalInputParser.swift#L770) | An incomplete bracketed paste remains in `bufferedBytes`. Completion creates a payload array and a String. A single paste can exceed any event-count-only allowance before the composer sees it. |
| Reader stream | [InputReader.swift](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Sources/SwiftTUIRuntime/Input/InputReader.swift#L468), [stream helper](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Sources/SwiftTUIRuntime/Support/AsyncStreamTeardown.swift) | The native reader uses the helper's default-unbounded AsyncStream and produces independently of dispatch. |
| Host wrapper | [ActionInputReader.swift](../../Sources/AgentMonitorTUI/ActionInputReader.swift) | Adds another default-unbounded stream. Paste is applied immediately to shared state on MainActor, while keys are yielded for later runtime dispatch. |
| Pump and dispatch | [EventPumpBuffer.swift](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Sources/SwiftTUIRuntime/RunLoop/EventPumpBuffer.swift), [RunLoop+EventPump.swift](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Sources/SwiftTUIRuntime/RunLoop/RunLoop+EventPump.swift) | The pump eagerly consumes events into uncapped batches, then accumulates all pending batches before dispatch. Charging only queued batches would miss drained-but-undispatched events. |

The wrapper also creates an ordering defect independent of retention. A queued Return or Escape can still be awaiting runtime dispatch when the producer applies a later paste to the composer. Its effect is therefore evaluated against an earlier action phase. Actor isolation serializes these mutations but does not restore input order across the two paths. A deterministic regression must stall consumption, submit key → paste → key, then check effects at dispatch; existing PTY tests cover ordinary interaction rather than this backlog condition.

The public reader seam returns `AsyncStream<InputEvent>`. That type can support pull production with `AsyncStream(unfolding:)`; changing the protocol is not inherently necessary. The concrete reader and eager pump still need coordinated admission. The public custom-host RunLoop seam offers a key handler but no equivalent ordered paste callback. The [paste dispatcher](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Sources/SwiftTUIRuntime/RunLoop/RunLoop+EventDispatch.swift#L329) and focused text-control paste registration are package-owned. The capability-probe read-suspension API is also package-owned and does not reserve downstream dispatch capacity.

Conclusion: neither a bufferingNewest wrapper nor a bounded custom reader establishes the required bound. The former can drop command text or confirmations; the latter merely moves the backlog into the runtime. Fixing this requires a dependency-level input contract, or replacing the runtime's input ownership. The [bounded terminal input proposal](../proposals/bounded-terminal-input.md) recommends the smaller dependency extension, with FIFO paste dispatch and reservations held through handling. The later [user decision rejects a fork](../decisions/swifttui-fork.md); the proposal is on hold and does not establish a process-wide heap ceiling.

### Upstream 0.16.0 comparison

The [0.16.0 release](https://github.com/SwiftTUI/swift-tui/releases/tag/0.16.0) advertises bounded input ownership. Read-only comparison against the already available local tag object `9ef8feec9fee6fc199767a52aa1c913976bdb2c9` shows that its bounded ingress applies to WebHost, not this native reader path. No checkout, fetch or dependency update was performed. The raw drain and public custom-host initializers are unchanged; native reader production, partial paste storage and the eager event pump remain unbounded. Chunk recovery and recursive-parser fixes do not supply a storage limit.

The new [InputAdmission](https://github.com/SwiftTUI/swift-tui/blob/9ef8feec9fee6fc199767a52aa1c913976bdb2c9/Sources/SwiftTUIRuntime/Input/ScopedInputReading.swift) follows scoped events through their queued/dispatched lifetime, but it and the pulling interfaces are package-only. WebHost uses that machinery; ordinary macOS `InputReader` does not. Public host paste dispatch is still missing. A simple version bump therefore does not close TUI-INPUT-01. Extending the existing reservation mechanism to native/custom-host input is a more focused candidate than introducing another parallel queue model; source review establishes feasibility direction, not an implemented solution.

## User feedback — 2026-10-17

Moved from PLAN on 2026-10-26. These are the original user reports and ideas, not assertions that every described behavior remains current. The source triage below distinguishes current defects from partial improvements and unapproved bindings.

- **FEEDBACK-02 — Separate folding from opening details.** TUI, possibly Mac app: ←/→ currently feels overloaded between root expand/collapse and child details. Footer calls this “fold”. The explanation “←/→ collapses/expands processes; ↑/↓ selects a process, then → opens its details.” appears only inside details, although it describes general navigation. User recommends separate functions and discoverable general help.
- **FEEDBACK-03 — Make grouped hierarchy visible at the leading edge.** TUI: no clear symbol or indentation at/before the first column; `[-]` in the middle of the “LAUNCH SESSION / HEAVY PROCESS” column is easy to overlook. Screenshot 1 shows group count `1` and child PID `51519` aligned without a clear leading hierarchy cue.
- **FEEDBACK-04 — Distinguish expandable rows.** TUI: it is not visually obvious which rows support expand/collapse. Related to FEEDBACK-03, but track the affordance independently from indentation.
- **FEEDBACK-05 — Distinguish session rows from column headers.** TUI: user reports launch sessions appear white like table headers, while processes are orange, making row roles confusing.
- **FEEDBACK-06 — Investigate missing per-process project information after grouping.** TUI bug candidate; assess shared grouping and Mac app impact. Before grouping, PID `64679`, process `2.1.299`, session `claude/b62cf475-622b-4ae8-8098-1fad1101babc`, TTY `ttys010` shows project `conceptgraph`; sibling node workloads show `client-activity`. After grouping, the session header shows `client-activity`, and `conceptgraph` is absent. PID `64679` is still visible in screenshot 3, so the screenshots support loss of the project label rather than disappearance of that process. Root cause and intended grouped display remain unverified; the screenshots also show different node PIDs/sample totals.
- **FEEDBACK-07 — Open keyboard help with `?`.** Idea for both TUI and Mac app: provide discoverable keyboard help through `?`.
- **FEEDBACK-08 — Visually scope details controls.** TUI: footer segment `| [/] scroll  -/+ size  0 min  9 max  = restore` concerns details, but identical color/spacing and an overlooked separator fail to communicate that scope.
- **FEEDBACK-09 — Make hiding details discoverable.** TUI: user cannot tell how to hide the details pane. Track separately from footer styling so the close interaction is explicitly resolved.
- **FEEDBACK-10 — Remove ambiguity from the details size percentage.** TUI: `Details 45%` after pressing `-` resembles CPU utilization. User suggests removing the percentage or moving it beside `-/+ size` in keyboard help.
- **FEEDBACK-11 — Clarify pin state across focus changes.** TUI: `@` and `+` shown while changing focus do not communicate pinning clearly. Assess shared pin state/Mac app impact if investigation indicates a common cause.
- **FEEDBACK-12 — Add larger diagnosis scrolling steps and endpoint jumps.** TUI idea: long diagnosis output is cumbersome to scroll line by line; proposed Space/Shift+Space scroll by one-third page, `t` jumps to top, and `b` to bottom. Check interaction conflicts before accepting bindings.
- **FEEDBACK-13 — Fix usable, clearly scoped scrolling on German keyboards.** TUI: user asks what scroll keys target and reports `[`/`]`, entered as Option+5/Option+6 on their German keyboard, do not work. Verify input handling and provide usable bindings; coordinate scope labeling with FEEDBACK-08 and longer navigation with FEEDBACK-12.

Screenshot provenance: user attachments in the 2026-10-17 feedback conversation. Image 1: `/Users/mbackschat/Desktop/missing indent when grouped.png`; image 2: `/Users/mbackschat/Desktop/lost before.png`; image 3: `/Users/mbackschat/Desktop/lost after.png`. These are local source references, not portable repository assets; the observations and identifying values needed for triage are recorded above.

## Feedback triage — 2026-10-26

Read-only review of `79c9255`; no fresh physical terminal testing. The main overview and secondary process view have different input/rendering paths, so overview improvements do not close process-view reports. Unfinished work remains in [PLAN](../../PLAN.md#temporary-feedback-intake--2026-10-17).

| ID | Source finding and remaining gap |
| --- | --- |
| FEEDBACK-02 | Resolved by the process-disclosure follow-up below: TUI arrows fold children and `i` independently toggles details in both views. Native process-row clicks retain their existing disclosure behavior. |
| FEEDBACK-03 | Resolved by the hierarchy follow-up below: process group controls now lead the row at narrow and wide widths. |
| FEEDBACK-04 | Resolved by the inspection-affordance follow-up below: process leaves show `i`, distinct from group disclosure arrows. |
| FEEDBACK-05 | Resolved by the hierarchy follow-up below: column labels use `.muted`, and session rows retain `.heading`. |
| FEEDBACK-06 | At the reviewed checkpoint, wide grouped children omitted CWD and native rows used group context. The follow-up below addresses this omission; it does not prove the retrospective screenshot cause. |
| FEEDBACK-07 | Native menu help exists, but `?` is absent from [shared shortcuts](../../Sources/AgentMonitorPresentation/ReportShortcut.swift) and [terminal input](../../Sources/AgentMonitorTUI/TerminalReport.swift); the binding remains an idea. |
| FEEDBACK-08 | Resolved by the inspection-affordance follow-up below: pane controls follow **Details:**, with unrelated controls outside that group. |
| FEEDBACK-09 | The process footer now advertises `i details` and `0 hide`; the minimized divider uses `i/= show`. Physical discoverability remains part of the user smoke check. |
| FEEDBACK-10 | Resolved by the inspection-controls follow-up below: the divider labels the requested size as `Details | pane N%`. |
| FEEDBACK-11 | Resolved by the pin-indicator follow-up below: selection stays `>` and the adjacent `★` independently marks pinning in both TUI views. |
| FEEDBACK-12 | Diagnosis implements Page Up/Down. Proposed Space/Shift+Space and endpoint jumps remain unapproved; `t` already has a browsing meaning. |
| FEEDBACK-13 | Page Up/Down now route to the visible inspector, verified through the PTY. Modified bracket input and actual German-keyboard event delivery remain unverified; no physical-layout fix is claimed. |


### Process-directory follow-up — 2026-10-26

The wide grouped TUI renderer substituted per-row evidence/context text for CWD, while the native process label showed no CWD outside details. Synthetic mixed-directory sessions reproduced both omissions: the new per-row TUI guards failed at 60/85/120/160 columns, and offscreen native OCR found neither child directory. The fix uses the shared population-level directory labels in both hosts, keeps CPU/memory on the same compact row and leaves full paths/evidence on demand. Matching suffixes remain distinguishable and absent CWD does not borrow sibling/runtime context. Independent review found that concatenation still lost CWD for long executables and session identity when a group heading scrolled away at 60 columns; both were reproduced with failing guards. Below 85 columns the fix keeps complete two-line identity/resource blocks; wider grouped rows reserve all three fields and abbreviate each explicitly. Row-scoped native OCR also caught middle truncation hiding a distinguishing leading directory component; native CWD now truncates at the tail. Offscreen inspection confirms the compact native layout; physical input and overall workflow acceptance remain user-owned. FEEDBACK-06's demonstrated omission is resolved, not the other process-view feedback.


### Process-disclosure follow-up — 2026-10-26

The process TUI routed directional arrows through the native-compatible disclosure operation, which opens a process inspector for leaf rows. The production PTY journey reproduced this coupling: repeated Right followed by an acknowledged sort opened the details pane without a details request. TUI arrows now request child disclosure only; `i` independently shows/hides process or session details, preserving the chosen pane ratio. Native row clicks still use their existing disclosure operation. Shared-state guards cover flat and grouped selections, group details without expansion, and leaf arrows with details both hidden and visible. The PTY journey opens and hides with `i`, retains bulk-group folding, and checks the explicit minimized state rather than treating an offscreen line as evidence of closure.

The process footer advertises `i details` and `0 hide`, and its minimized divider advertises `i/= show`. The README preview was regenerated and inspected in an isolated headless browser: columns and complete key hints fit the synthetic viewport. This resolves FEEDBACK-02 and the missing hide hint in FEEDBACK-09; it does not settle the remaining hierarchy, scope, split-percentage, pin-symbol or physical keyboard concerns. Measurement and attribution are unchanged.

Validation on 2026-10-26: the changed production PTY journey and flat/grouped state guards pass, and all 712 debug tests passed after the separately documented [consumer-stall fixture correction](development-tools.md#consumer-stall-fixture-scheduling-correction--2026-10-26). Strict formatting, documentation links and generated-preview checks pass. No optimized rebuild, live provider access or native performance experiment was performed for this interaction change.


### Process-hierarchy follow-up — 2026-10-26

Wide process groups placed their `[+]`/`[-]` control after the CPU and memory columns, while narrow groups placed it first. Both used the same heading style as column labels. The renderer now uses the overview's `▸`/`▾` glyphs at the start of group rows and a reserved two-cell control column in wide tables. Numeric columns remain aligned for groups, child processes and pinned groups in flat mode; narrow identity/resource pairs remain intact. Column labels use the muted role, session rows use the heading role, and selected rows keep their existing role. No measurement, ordering, selection or disclosure-state semantics changed.

A failing guard established the old layout at 60/85/120/160 columns in grouped and pinned-flat modes. The corrected guard checks leading controls, distinct header/session roles and CPU-column alignment; existing per-process directory, long-name, whole-block and PTY disclosure checks remain in force. This closes FEEDBACK-03/05's source defects, not the user's physical legibility or full workflow checks.


The same review found a related flat-mode width defect: pinned group totals were omitted from the metrics used to size numeric columns. A synthetic group with 1,999.80% CPU and 199.98 GB needed more digits than its individual rows; the failing guard showed CPU shifted one cell and memory two cells. Column sizing now includes the groups actually represented in the row projection, independently of grouping mode. The guard retains exact resource values and compares numeric endpoints, rather than accepting clipped totals.

Validation on 2026-10-26: all 224 CLI/presentation, four PTY and five preview debug tests pass. The generated README preview was checked in an isolated headless browser; muted headers remain legible and column spacing is unchanged in the flat example. Strict formatting, documentation and preview checks pass. This TUI-only rendering change required no Core-suite rerun, optimized build, native app interaction or workload measurement.


### Inspection-controls follow-up — 2026-10-26

Page Up/Down always changed the overview offset, even while the process inspector was displayed. Replacing bracket-only scrolling with actual terminal Page Down/Up sequences in the existing PTY journey reproduced the unchanged process pane. The TUI now routes paging and single-line bracket scrolling to the visible inspector only, leaving hidden offsets untouched. It preserves the existing five-line paging increment, one-line bracket increment and process scroll clamping after resize. The process footer advertises the page keys, and its split divider says `Details | pane N%`: this is the remembered requested pane share, subject to minimum geometry, not a resource percentage. Mac uses its native scroll area and is unaffected.

This closes FEEDBACK-10 and the source-level Page Up/Down part of FEEDBACK-13. The PTY verifies key decoding, reaching the end, scrolling back one line and returning to the start; it does not establish German-keyboard modified-bracket delivery. Contextual footer grouping, process-leaf affordances and pin symbols remain separate UX work.

Validation on 2026-10-26: all 224 CLI/presentation, four PTY and five preview debug tests pass. Existing 80/100/120-column footer budgets remain unchanged: Page Up/Down is the compact primary hint, and brackets remain documented aliases. The updated synthetic preview was inspected in an isolated headless browser. Formatting, documentation and preview checks pass; no Core-suite rerun, optimized rebuild or live measurement was needed for this TUI-only change.


### Inspection-affordance follow-up — 2026-10-26

The process renderer had no leaf inspection marker and its session inspector still taught that Right opened process details, contradicting the child-only arrow behavior. The footer mixed pane controls with quit without labelling their scope. Failing layout guards reproduced the missing marker and scope plus the obsolete instruction. Process leaves now show `i`, expandable groups retain `▸`/`▾`, and the footer labels the contiguous pane controls **Details:**. Quit stays outside that group. Wide flat and grouped numeric columns use the same two-cell control space; narrow identity/resource pairs remain intact. The README's obsolete process-arrow instruction is corrected as well. No input routing, native behavior, measurement or attribution changes.

Validation on 2026-10-26: all 226 CLI/presentation, four PTY and five preview debug tests pass. The first integration run caught a footer row added at 80 columns and a shifted 85-column layout breakpoint; both were corrected without weakening the existing geometry guards. The regenerated synthetic preview was visually checked in an isolated headless browser. Documentation and strict formatting checks pass. This closes FEEDBACK-04/08 at the source/rendering level; physical workflow checks remain open. No native performance trial or optimized rebuild was needed.


### Pin-indicator follow-up — 2026-10-26

The overview and process table independently replaced the selection marker with `@` for selected pins and `+` for other pins. Their renderers now share separate indicators: `>` for selection and `★` for pinning. This remains explicit without color and for missing-target placeholders. Wide process rows reuse the existing control spacing; narrow identity/resource pairs retain their geometry, with pinning on the identity line and selection on both. Overview rows reserve one extra cell for the separate pin indicator. Native SF Symbols and all pin lifecycle, limits and removal behavior are unchanged.

Failing renderer guards cover selected/unselected process and session pins, narrow grouped identity/resource pairs, disappearance and removal of a missing process pin. The production PTY journey now requires the combined `>★` indicator after pinning and an ordinary selected row after unpinning rather than searching for `@` anywhere in the screen. This resolves FEEDBACK-11's source presentation issue; physical legibility remains part of UX-01.

Validation on 2026-10-26: all 228 CLI/presentation, four PTY and five preview debug tests pass. The regenerated synthetic preview was visually inspected; resource columns and footer geometry remain unchanged. Strict formatting, documentation links and preview drift checks pass. No optimized rebuild, Core-suite rerun, native interaction or workload experiment was performed for this TUI-only presentation change.


### Flat-process directory correction — 2026-10-26

Source review of `be7bd9c`, including a bounded independent read-only review, found that wide flat process rows bypassed `ProcessDirectoryLabels`: they displayed TTY plus only the directory basename, while grouped/narrow rows already disambiguated matching suffixes. Large numeric fields could also select a compact-column branch that omitted CWD entirely. Adding a historical prefix outside the column grid shifted text fields and reduced the remaining location space. This was a separate remaining path of the FEEDBACK-06 orientation problem, not evidence that its grouped/native fix failed.

Synthetic live and historical workers in `/work/alpha/project` and `/tmp/alpha/project` reproduced the indistinguishable flat labels. The flat table now allocates population-wide executable, agent/session and CWD widths after the numeric prefix, abbreviates each field explicitly and uses the same precomputed directory labels as the other process views. `[past]` stays inside the executable cell. TTY remains in inspection details. The change also removes the per-row URL basename construction from this renderer; no performance benefit is claimed without measurement. Grouped/narrow rows, native views and text reports retain their existing behavior.

Validation on 2026-10-26: all 229 CLI/presentation, four PTY and five preview debug tests pass. Guards cover 85/120/160-column matching basenames, historical text-column alignment and numeric values that previously forced the CWD-dropping fallback; existing Unicode, group-alignment and full-session-at-120 guards remain in force. The latter caught an avoidable one-character session truncation during allocation refinement. Independent source review found no additional regression; the regenerated synthetic preview was visually inspected. Documentation and strict formatting checks pass. No native measurement, optimized rebuild or Core-suite rerun was needed for this TUI-only correction.

### Contributor context under truncation — 2026-10-26

A bounded independent source review of the native responsibility view at `591449c` found two remaining context losses. Overview executable groups placed the executable and CWD in one tail-truncated string, so a long executable hid the directory distinguishing otherwise identical workloads. Native process children always inherited the containing group heading, even when corroborated root grouping placed distinct exact child sessions beneath it. Offscreen native guards reproduced both omissions before the fixes; no live workloads were inspected.

The shared contributor label now carries executable/count and optional directory separately. Native summaries reserve independent text space beside the unchanged resource columns; the terminal uses an executable line followed by directory/resources when one line cannot fit. Whole-block viewport handling also keeps the selected two-line contributor visible at minimum height: the new 80-column/eight-line guard caught a clipping path that previously left only the preceding row. Native process children retain their own provider/session line when their exact session differs from the enclosing group. Same-session children keep their existing compact single resource line. These are presentation changes, with no changes to attribution, category keys, measurements, action targets or totals.

The native label view is renamed `MenuBarContributorLabel` to match its session and workload responsibilities. Guards cover long executable/CWD pairs at 40/80/120 terminal columns and short/normal heights, native compact executable groups, and exact child IDs beneath a corroborated root. Synthetic native images were visually inspected; physical interaction, accessibility and user workflow acceptance remain pending.

Validation on 2026-10-26: the full debug suite passes once after the final code changes—312 Core, 230 CLI/presentation, 138 native, 33 actions, four PTY and five preview tests. Strict formatting, documentation links and generated-preview drift checks pass. No optimized rebuild or native performance experiment was run for this presentation correction.

### Process viewport under coverage pressure — 2026-10-26

Source review found that the secondary process view allocated its header, wrapped coverage and footer before reserving any process rows. At eight terminal rows, even a selected process could disappear entirely; several simultaneous coverage notes could also exceed the viewport. The overview already reduced its chrome to protect the selected responsibility block. A deterministic regression using populated flat/grouped process snapshots reproduced the process-view failure at 40, 80 and 120 columns. An initial fixture had only overview records and no process findings; it was corrected and rerun against the original renderer before accepting the red result.

The process renderer now shares one pane allocation with detail scrolling, reserves a complete selected identity/resource block, and reduces coverage to counted warnings/notices when necessary. The shared count formatter also serves the overview. A bounded source review caught pending-filter and paused-time omissions in the first compact-header version; those contexts remain visible, including requested unfiltered state while the snapshot still reports active thresholds. Explicitly maximized details remain an intentional exception to process-row reservation. This is a layout correction, not evidence of native interaction or sampling performance.

Validation on 2026-10-26: the full debug suite passed (751 tests). A final notice-only correction then moved paused notices out of the timestamp line into the optional help row; its regression failed first, and all affected CLI/presentation (236), PTY (four) and preview (five) tests passed afterward. Core/native/action code did not change in that last correction. Formatting, documentation and generated-preview checks passed. No optimized rebuild or native experiment was run.

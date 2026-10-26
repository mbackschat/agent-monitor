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
| FEEDBACK-04 | Overview distinguishes expandable rows and leaves; process rows lack an equivalent leading details affordance. |
| FEEDBACK-05 | Resolved by the hierarchy follow-up below: column labels use `.muted`, and session rows retain `.heading`. |
| FEEDBACK-06 | At the reviewed checkpoint, wide grouped children omitted CWD and native rows used group context. The follow-up below addresses this omission; it does not prove the retrospective screenshot cause. |
| FEEDBACK-07 | Native menu help exists, but `?` is absent from [shared shortcuts](../../Sources/AgentMonitorPresentation/ReportShortcut.swift) and [terminal input](../../Sources/AgentMonitorTUI/TerminalReport.swift); the binding remains an idea. |
| FEEDBACK-08 | Process footer still lists scroll/size controls without an explicit Details scope label. |
| FEEDBACK-09 | The process footer now advertises `i details` and `0 hide`; the minimized divider uses `i/= show`. Physical discoverability remains part of the user smoke check. |
| FEEDBACK-10 | Process split-pane heading still shows `Details N%`. |
| FEEDBACK-11 | Selected/unselected pins still use `@`/`+`. This is a presentation concern; no shared pin-state defect was established. |
| FEEDBACK-12 | Diagnosis implements Page Up/Down. Proposed Space/Shift+Space and endpoint jumps remain unapproved; `t` already has a browsing meaning. |
| FEEDBACK-13 | Bracket scrolling follows an empty-modifier guard; Page Up/Down does not route to process details. Actual German-keyboard event delivery is still unverified. |


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

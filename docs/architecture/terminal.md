# Terminal presentation and host

SwiftTUI renders shared presentation state and handles terminal input. This guide defines layout, navigation and host constraints; the [terminal usage guide](../usage/terminal.md) explains the controls.

[Architecture overview](../architecture.md) · [All architecture guides](README.md)

## In this guide

- [TUI contract](#tui-contract)
- [Verification boundary](#verification-boundary)
- [SwiftTUI host evaluation](#swifttui-host-evaluation)

## TUI contract

### Font fallback and chart-mode resolution

[TerminalChartSelection](../../Sources/AgentMonitorTUI/TerminalChartSelection.swift) resolves one contributor chart style at startup. Explicit `--tui-chart-style stacked|compact` bypasses detection. Auto leaves other terminal apps stacked; for Apple Terminal it uses a bounded, read-only font lookup on the tab matching stdout's TTY, gated by existing AppleEvents authorization without requesting consent. The fixed local script reads only tab TTY/current font, never contents, default profiles or remote helpers, and has an inner one-second/outer two-second deadline.

Multiplexed or SSH sessions skip lookup. Normalized Menlo, Source Code Pro, Monaco and Bitstream Vera Sans Mono family prefixes retain stacked charts; Meslo and unknown/unavailable fonts fall back to compact. This is a compatibility heuristic, not a terminal rasterization guarantee; the explicit style handles custom spacing and other fonts. It neither changes font/settings nor polls them during monitoring. Shared presentation receives only the resolved style. Compact mode preserves the range, samples, missing/zero/above-range markers and numeric values, uses eight glyph-height steps for all contributor/overall charts, and never gives its full-block glyph a whole-cell background. Stacked mode retains 24 steps and full-cell interiors. Native chart drawing and the already single-row process history are unaffected.

Input retention remains an open boundary: discarding paste in the host wrapper does not bound the pinned reader's raw/partial-paste storage, AsyncStreams or runtime event batches. With the composer removed, paste no longer mutates action state from the producer. The [source findings](../research/terminal-ui.md#ordered-input-and-retention-boundary--2026-10-26) and [on-hold dependency contract](../proposals/bounded-terminal-input.md) describe the remaining upstream storage gap; no backpressure fix is claimed. The user [rejected maintaining a SwiftTUI fork](../decisions/swifttui-fork.md); the dependency remains official upstream.

### Process rows and constrained widths

The process table uses leading `▸`/`▾` controls for collapsed/expanded session rows, matching the overview. Process leaves show `i` for inspection rather than a child-disclosure arrow. All wide process rows reserve the same control column as groups so numeric columns align, including pinned groups in flat mode. Column labels use muted styling; session rows keep the heading role. In both TUI views, `>` marks selection independently of the adjacent `★` pin indicator, including missing placeholders and NO_COLOR output. Narrow process blocks place the pin on the identity line and repeat selection on the resource line.

Below 85 columns, the secondary process view uses complete two-line blocks: provider/session identity and executable or group disclosure first, then PID/member count, CPU, memory and compact CWD. Numeric formatting, partial-value markers and pin/selection identities are unchanged. The viewport keeps the selected identity/resource block complete when the pane can fit it; unselected blocks may be clipped at its edges. Insufficient height for the selected block shows a resize hint. Full paths and evidence stay in details. Wide flat process tables reserve aligned executable, provider/session and CWD columns from the remaining width after numeric fields; no compact fallback removes CWD.

`[past]` belongs inside the executable cell, so historical rows preserve column alignment. Every clipped field has an explicit ellipsis, and terminal context remains in details. Wider grouped process tables retain single-line resource columns and reserve space for executable, compact CWD and provider/session identity before truncating individual fields. A scrolled-away group heading must not remove the child’s ownership context. Native directory truncation preserves the leading components that distinguish matching suffixes. Attribution evidence remains in details.

`ProcessDirectoryLabels` shares missing/shared-runtime handling and disambiguated path suffixes with native process rows; the native row index builds these labels once per displayed projection, not per row command. Full directories remain in details and native tooltips.

### Default view and inspection

The default live view is the shared [contributor overview](contributors.md#contributor-overview-and-recent-activity). `v` explicitly switches tables; from a selected current worker it preserves that worker and process-view grouping. `g` enters process inspection and changes grouping. `c`/`m`/`o` sort the current view; `n` sorts by PID only in process views. `a` switches main/all contributors, arrows navigate/fold, `i` toggles selected details, `.` pins the owning session and u/d, Ctrl-U/Ctrl-D and Space (down) page by half the active viewport; Page Up/Down use a full page. Return opens Details in place without changing the table, selection or grouping; repeated Return leaves it open.

### Diagnosis, focused details and minimum size

`I` starts a separate finite CPU diagnosis, including from a frozen report. Its fixed result replaces only the viewport, with ↑/↓ and Page Up/Down scrolling, `x` Cancel, Esc Back, `I` Run again and ordinary quit controls. Action review prevents starting diagnosis; while it is visible, report/action keys cannot mutate the live view or execute actions. The TUI mirrors the shared controller’s published display state into `LiveReportState.diagnosis` for SwiftTUI invalidation. Its separate `diagnosisOffset` belongs to the viewport: controller publications preserve it within a phase, while phase changes reset it. Collection and history continue independently.

Below 40×8, starting/rerunning is disabled while cancellation, Back and quit remain available. The shared footer retains view/group switching, Help, pause/resume and quit; expanded layouts add navigation, sorting and diagnosis hints. Complete controls remain in contextual Help. The contributor overview removes optional header chrome before sacrificing a complete selected identity/resource block; current filters remain visible at the supported minimum size. The collecting state and guide explain duration and lookup cost. Shutdown cancels and drains the diagnosis controller.

### Mouse input and terminal copying

Leave mouse reporting disabled through SwiftTUI's public host configuration so the terminal owns drag selection and copying. TUI navigation remains keyboard-driven. The PTY smoke guard rejects mouse-reporting enable sequences in both color and NO_COLOR modes.

### Launch contract

Launch explicitly with `--tui`; accept the user's suggested `-tui` spelling as an alias. The existing default text report and JSON mode retain their behavior.

### Refresh and output constraints

Use the terminal window and refresh in place. TUI mode watches continuously unless an explicit `--samples` limit is supplied; `--interval` is the fixed interval when adaptation is off and the visible maximum when enabled. Reject simultaneous TUI and JSON output or a noninteractive output stream with an actionable message.

### Process-table information

Show observed processes passing the selected display filters in a compact table: process/PID, CPU, footprint, provider/session abbreviation and compact workload CWD; terminal context is available in details. Preserve explicit unknown and ambiguous labels. Highlight exceeded resource values and the selected row; meaning must also be readable without color.

### Process ordering

Stable arrival order is the default; `o` selects it. Offer CPU, footprint and PID sorting through `c`, `m` and `n`; `r` reverses numeric sorts and has no effect on Stable order. Show the active sort and applicable direction. Use stable process identity as a tie-breaker; preserve selection and disclosure by PID plus start time when sorting or refreshing, rather than by row index.

### Selection and Details navigation

↑/↓ selects a row; → expands and ← collapses children only. Process leaves do not expand. `i` independently shows/hides the selected process details containing the full session ID, directories, runtime, ancestry, and attribution evidence.

Keys `[` and `]` scroll visible details by one line; u/d and Ctrl-U/Ctrl-D use half the visible pane height; Space pages down; Page Up/Down use a full page. Paging and vertical arrows follow Tab focus in contributor and process views.

Opening Details focuses it; Tab returns navigation to the table without closing the pane. Scrolling never changes the hidden inspector.

Full arguments are captured for reports only with `--commands`; `x` requests a bounded live read for the active process inspector.

`q` or Ctrl-C exits and restores the terminal.

### Details sizing

Separate the details pane with a full-width rule and allocate its height from a remembered content-area ratio, independently of row counts, text length, or disclosure content.

Start minimized; `i` opens at 50% initially. `-`/`+` adjust by five percentage points within 10–90%; `i` closes, `M` maximizes, and `=` restores the remembered ratio.

These modes do not overwrite the ratio. The divider labels the requested ratio as `pane N%` to distinguish it from CPU usage.

Minimum pane heights take precedence in small terminals.

Pad each pane to its allocation and constrain each rendered line to one terminal row.

Open details follow explicit row selection; disappearing processes clear content without moving the divider.

### Terminal cell measurement

Measure report-table padding, clipping, detail wrapping and action-panel wrapping in terminal cells, preserving whole grapheme clusters. `TerminalCells` matches the pinned SwiftTUI width classification without importing a terminal framework into presentation; renderer-comparison tests guard that agreement. Native SwiftUI layout remains independent.

### Viewport, scrollbar and footer

Share report headers and core footer wording across contributor, grouped-process and flat-process modes. The header leads with active sort/direction and view identity; cadence and update count follow.

Technical read-failure summaries stay in Diagnostics; its footer shortcut carries a warning/notice badge.

Keep the selected row block visible and pad short Details to its allocated height so the footer remains at the screen bottom. Tables and reference/Details pages show bounded visible ranges when overflowing.

Each TUI table retains one row-identity/line-offset viewport anchor.

Paging moves the viewport and keeps selection visible; arrow selection reveals the selected block.

Refresh, disclosure and resizing resolve the anchor against current rows and clamp it to the available content.

A muted right-edge track and proportional, nonbold thumb measure rendered lines, including wrapped context, section dividers and expanded children; endpoint arrows signal content above/below.

The rail appears only when content overflows and at least three body lines fit; smaller panes retain the range indicator.

A two-cell gutter keeps table columns stable as overflow changes.

The Mac tables retain native scrolling; text and JSON have no interactive viewport.

Optional header rows yield to identity and controls at minimum height; filters remain visible.

Page sizes derive from actual pane allocation, not a fixed number of rows.

### Minimum-height priority

At supported minimum heights, the process view reduces optional header/history chrome before sacrificing the selected process or group's complete identity/resource block. Coverage may become a counted warning/notice summary with an explicit resize hint; active or pending filters and paused snapshot time remain visible. Split/minimized details yield their space to that block, while explicit maximization still gives the space to details. Rendering and detail-scroll limits use the same pane allocation.

### Resize and qualification

Handle resizing and preserve selection across updates. Disclosed shared-daemon associations must retain the launch-origin qualification.

### Coverage and diagnostic disclosure

[CoverageStatus](../../Sources/AgentMonitorPresentation/CoverageStatus.swift) supplies shared warning/notice content. Mac and TUI expose its severity on the footer Diagnostics control and place detailed notes on the Diagnostics page. Text output prints the notes, or “No read failures or overruns” when none apply. The interactive badge keeps coverage changes from shifting selected table rows.

Warnings precede notices:

| Severity | Content |
| --- | --- |
| Warning | Read failures: denied access, changed identity or other native failures on a listed same-user PID. Also unidentified/latest-scan gaps, acquisition overruns and maximum gap, collapsed detail, exclusions and unavailable memory. |
| Notice | Lookup-unavailable observations (ESRCH), publication coalescing and released read-gap detail. ESRCH is presented as an expected polling limit; it does not establish normal exit. |

Each note’s definition is its tooltip. Native coverage disclosure uses a metric grid, a retained-time bar and a compact failure-category table; cell tooltips explain definitions. TUI coverage details use aligned metric columns. The time bar represents retained history, never completeness of process coverage. Background limitations live in Help; disclosure never hides material gaps.

## Verification boundary

Core tests continue to use deterministic observations and native measurement checks. Validate session cadence, cancellation and errors with controllable inputs. Presentation tests cover selection identity, disclosure, unknown/ambiguous states, and narrow layouts. A real terminal test must verify refresh, resizing, input responsiveness, and terminal restoration. Measure TUI overhead separately from the existing collector result.

The isolated SwiftTUI runtime passed terminal interaction checks; [TUI research](../research/terminal-ui.md) records the host behavior and measured probe overhead behind the adoption decision. Integration has dedicated presentation tests and a PTY journey. The native menu bar app consumes the same contract with separate SwiftUI rendering and AppKit lifecycle ownership.

## SwiftTUI host evaluation

The completed [isolated probe](../research/terminal-ui.md) used SwiftTUI 0.14.0’s public `RunLoop` with a `TerminalHost`, input reader, signal reader, state container, and focus tracker. This bypasses the high-level scene launcher’s mandatory discovery socket without modifying upstream code. SwiftTUI still owns raw mode, rendering, focus, input, resizing, and cleanup; the application owns the runtime lifetime. No browser or discovery service starts.

The monitor uses the same public host with neutral presentation state confined to the main actor. SwiftTUI is declared as an exact remote package dependency in the main manifest. `swift build -c release` compiles the unchanged upstream sources with standard compiler optimization; no custom framework build or fork is maintained.

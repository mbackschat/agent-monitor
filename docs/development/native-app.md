# Build and validate the Mac app

Build the Mac app from source, validate it with synthetic inputs, and hand physical interaction checks to the user. Start with [check selection](../development.md#choose-checks-for-the-change); the specialist probes below are not routine acceptance prerequisites.

[Development guide](../development.md) · [All development references](README.md)

| Task | Procedure |
| --- | --- |
| Build or launch the local bundle | [Build and coverage details](#build-and-coverage-details) |
| Check native behavior without desktop automation | [Headless validation](#default-headless-validation) |
| Hand off physical interaction checks | [Mac smoke test](#manual-macos-smoke-test), [TUI workflow](#manual-tui-workflow-check), [terminal focus](#manual-terminal-focus-check) |
| Investigate measured costs | [Row/grouping probes](#row-and-grouping-measurements), [collection probes](#collection-cost-probes) |

## Default headless validation

Headless validation is the default, as decided on 2026-10-16. Use deterministic core and presentation tests, injected process/action services, native model tests and synthetic offscreen renders. Test real composition across layers where wiring affects behavior. Control sample progression and clocks instead of using elapsed sleeps as test synchronization. Routine tests must not run real harness listings, send live messages, signal user workloads or drive desktop apps.

Mount hosted content with `mountOffscreenNativePreview` before bitmap capture so render checks use an owned window’s backing scale and completed layout. Reuse an existing host window when present, keep a newly created window alive through layout and capture, and close only that window afterward. Geometry and pixel assertions must not be weakened to accommodate unattached captures.

The two native focus/shortcut checks require **System Settings → Keyboard → Keyboard navigation** to be enabled, as reported by `NSApplication.isFullKeyboardAccessEnabled`. They fail with an explicit prerequisite message when it is off. CI enables this setting on its disposable runner before launching tests; local checks must not change the user’s preference automatically. The chart pixel guard explicitly renders at 1× and 2× with odd/even widths and samples the bottom pixel row, including bars only one point high.

Run the existing suite with synthetic render outputs enabled:

```sh
mkdir -p .build/design-studies
TZ=UTC MENUBAR_PREVIEW_PATH="$PWD/.build/design-studies/panel.png" MENUBAR_ICON_PREVIEW_PATH="$PWD/.build/design-studies/icons.png" MENUBAR_OVERVIEW_PREVIEW_PATH="$PWD/.build/design-studies/overview.png" MENUBAR_REFERENCE_PREVIEW_DIRECTORY="$PWD/.build/design-studies" swift test --no-parallel
bash scripts/menubar.sh build
plutil -lint '.build/Agent Monitor.app/Contents/Info.plist'
codesign --verify --deep --strict '.build/Agent Monitor.app'
```

During iteration, append `--filter AgentMonitorMenuBarTests` or select the affected tests; use the complete suite for a change spanning collection, attribution and native state. CI enables the same synthetic renders and retains them for review. Inspect the light/dark panel, hierarchical table, icon strip, Help and Diagnostics for clipping and contrast after visible changes. These generated files are ignored validation output, not replacements for the optimized README assets. Rendering needs AppKit on macOS, but no desktop clicks or Computer Use permission. Automated checks do not use OCR or require an OCR installation.

### Assertions and evidence limits

Test identity, directory, metric and argument values through the production presentation values, native owner-label logic and controllers.

Check wrapping with the [text-layout recorder](../../Tests/AgentMonitorMenuBarTests/NativeTextLayout.swift), which observes SwiftUI’s public `Text.Layout.isTruncated` and line counts; its negative control distinguishes a deliberately truncated field from a wrapped one.

Use native bounds and scroll offsets for geometry/navigation and bitmap checks for colors and spacing. These checks do not transcribe pixels, establish every glyph’s legibility or prove physical accessibility/input delivery; inspect retained renders for actual appearance and keep the user smoke checks separate.

Offscreen SwiftUI accessibility children were empty in the tested harness, so they are not an equivalent text oracle.

### Diagnosis states

Set `MENUBAR_DIAGNOSIS_PREVIEW_DIRECTORY` to an existing output directory to render collecting, completed, failed and cancelled diagnosis states in light/dark appearance. The diagnosis tests inject a finite fake reader and controlled completion gates; they never use real session listings.

Interactive diagnosis checks use the shared controller with controlled completion gates, a fake finite reader in the owned TUI fixture, and offscreen native states. They cover cancellation/publication, cleanup before rerun, pause preservation, minimum viewport behavior and shutdown restoration without provider listings.

For a targeted user check in both interfaces, start diagnosis from a paused report, cancel and return, rerun to a fixed result, scroll full identities and confirm Back preserves pause. In native, additionally dismiss/reopen during collection and compare drag detachment with detached-window closure.

Check keyboard/VoiceOver delivery and time Cancel against real blocking reads separately; headless gates cannot establish responsiveness or diagnostic effectiveness. Measure diagnosis plus live collection with owned workloads before making overhead claims.

## Manual macOS smoke test

The user runs this small integration check; Computer Use is disabled. Do not request or enable desktop automation as a routine review prerequisite. Run it after changes to AppKit wiring, focus/input, menu tracking, popover lifecycle or packaging; ordinary core changes use the headless checks unless a concrete integration risk remains. Keep the result pending until the user supplies it.

Quit any already-running Agent Monitor through its status menu, then run `bash scripts/menubar.sh run` from a terminal. This uses normal local monitoring; provider listings and messaging remain disabled. It does not require creating agent sessions or sending messages. Use existing rows if available; otherwise lower thresholds through View options and mark row-specific checks skipped if there are still none.

### 1. Open and dismiss

Left-click the icon, confirm the panel anchors to it and fits the screen, click outside, then reopen. Repeat quickly; there should be one responsive panel with live updates and no error.

### 2. Menus during refresh

Open View options on the first click, hold a submenu open across a refresh, select another panel size and confirm checked values and anchoring. Right-click and Control-click the status icon, then verify ordinary left-click still opens the panel.

### 3. Keyboard and rows

Open the panel and confirm arrows immediately target the table, including after waiting for the first sample. Tab to View options and ensure a refresh does not steal focus.

Use Tab to focus both a session header and a process header, then repeat ←/→ to collapse/expand each without toggling on repeated presses. Check Shift+←/→ on a top-level row and on a child: collapse all groups or only its parent, respectively; child collapse must focus its parent.

Navigate with ↑/↓, pin and unpin with `.` (also with Caps Lock enabled), and pause/resume with `p`.

Click row text and both metric cells to select without changing disclosure; click the count/chevron to expand/collapse. Verify unpinned controls reveal on row hover or their own keyboard focus, pinned controls stay visible, and information/action controls do not toggle children.

Click each table header twice and compare its indicator/order with View options. Scroll in both directions and confirm body text never obscures the header; offscreen captures do not settle live compositing.

Return/Space should activate the focused native control. The paused state must stay visible and the panel height must remain stable as rows change.

When checking disclosure changes, raise both resource thresholds to hide an expanded row, then restore them; its expansion should return unless you chose another inspection while it was missing.

### 4. Detach and return

Drag the popover’s top edge away while paused, during action review without confirming the action, and while diagnosis is collecting. Confirm the visible panel retains its state and open-panel sampling behavior.

Drag its top/bottom edge through several heights, return to a preset, then close/reopen; verify height, selection, disclosure and pause survive without replacing the table.

Close the detached window and reopen from the menu bar: the ordinary close lifecycle must run, diagnosis must be cancelled/discarded and the reopened panel must show the live report. Injected delegate notifications do not establish that AppKit delivers the expected close notification.

### 5. Quit

Choose Quit in the status menu and confirm the icon disappears. Report the tested commit, macOS version, pass/fail/skipped for each step and a short reproduction for failures; redact workload identities in any screenshots.

This smoke test does not establish process termination or terminal Automation, VoiceOver, multiple-display/Space behavior or sustained energy cost. Those remain targeted checks below, not prerequisites for every edit. Actual signal tests require disposable owned targets; do not use real workloads to fill a coverage gap.

Targeted follow-ups, tracked by MENUBAR-01/03 in [PLAN](../../PLAN.md#existing-validation-follow-ups):

- Compare simultaneous sessions/CWDs/executables, nested CPU/memory ordering, recent departed contributions and coverage disclosure at narrow and wide sizes; watch shifting directory suffixes and truncated common prefixes.
- Verify five-second display updates and close/reopen with live and static icons. Check Sampling mode, maximum, advanced minimum/window/multiplier choices and disabled invalid combinations while a submenu stays open across refreshes; compare maximum/adaptive behavior through pause and panel dismissal/reopening. Native cost/cadence, ten-minute closed-panel CPU/wakeups and App Nap measurements require a separate explicit request and remain separate from CLI results.
- Check Help/Diagnostics scrolling and Done/Escape without changing the selected row, then diagnosis Cancel/Back/Run again with blocking reads, plus continued collection and cancellation after detachment; assess concurrent diagnosis cost separately.
- Verify `y`/Copy PID, contextual actions, pin hover/focus and Unpin all, native disclosure and row Details targets, VoiceOver meanings and modifier handling. Exercise real actions only with disposable targets.

## Manual TUI workflow check

At narrow and wide sizes, compare the main overview and secondary process view against the [product contract](../product.md). The [dated feedback triage](../research/terminal-ui.md#feedback-triage--2026-10-26) distinguishes implemented overview behavior from remaining process-view defects.

Check leading hierarchy, compact per-process CWD (including matching suffixes and long paths), details versus folding, a discoverable close action, scoped scrolling, pin symbols, **? Help**, **D Diagnostics** and return to the same paused selection.

Verify `u`/`d`, Ctrl-U/Ctrl-D and Space/Shift-Space half-page navigation, plus Page Up/Down, in the actual terminal. Check modified-key delivery on the German keyboard, including terminals that send identical bytes for Space and Shift-Space; source checks cannot prove which key/modifier events arrive. Check diagnosis Page Up/Down separately. Top/bottom alternatives remain ideas, not shipped controls.

## Build and coverage details

Build with `bash scripts/menubar.sh build`; the default is an optimized release build with debug-symbol generation disabled. Use `AGENT_MONITOR_BUILD_CONFIGURATION=debug bash scripts/menubar.sh build` for an unoptimized local build, or `swift run agent-monitor-menubar` for normal debugger symbols.

### Bundle contents and launch

The application icon is compiled from the [editable source](../../Resources/README.md) during bundle assembly. `python3 scripts/test_macos_bundle.py` uses the installed Xcode icon compiler, catalog inspector and icon decoder with disposable bundles; it covers real source compilation and rejection of missing, corrupt or incomplete resources. Follow the [release icon review](../macos-release.md#required-app-icon-review) for appearance and Finder checks. Native image services may require running these tools outside a restricted sandbox; they do not launch the monitored app or access signing credentials.

The local ad-hoc bundle is `.build/Agent Monitor.app`; its resources include the presentation schema bundle and native logo bundle, and retain the project license and [third-party notices](../../THIRD_PARTY_NOTICES.md), including the full MIT terms for the shared terminal-width code. Use `bash scripts/menubar.sh run` to launch with the shell PATH, or `swift run agent-monitor-menubar` for direct executable development.

The menu bar app has a local source build and a separate [signed release ZIP](../macos-release.md). It is not included in the CLI archive or Homebrew formula. It adds no third-party dependencies. CI builds the local app bundle and checks its property list, ad-hoc signature and bundled license/notice copies.

Run `swift test --filter AgentMonitorMenuBarTests` for lifecycle, controlled collection, fake-action, layout, pause/pin, task ownership, menu and status-menu regressions. It uses injected readers, clocks, actions and synthetic reports; it sends no messages or signals to live workloads. The production `MenuBarCollection` is tested with `MonitoringSession` and injected native process readers. Offscreen renders cover compact layouts, appearance changes and panel geometry. Simulated delegate tracking and source-call counts do not establish physical input delivery, live submenu tracking or desktop behavior.

### Row and grouping measurements

Native row-index regressions cover reuse/invalidation across displayed data, selection, history, interval, sorting, grouping, pins and disclosure, plus removed/reused identity rejection. Frozen pending samples retain the displayed action lookup until Resume.

For the synthetic row-command benchmark, set `MENUBAR_ROW_MEASUREMENT_PATH` and run `swift test --filter measureNativeRowCommandProjection`; it starts no collector or provider. `MENUBAR_ROW_RENDER_PATH` with `--filter measureNativeRowRendering` separately measures offscreen initial layout and refreshes. Keep predicate timing separate from full rendering and live CPU claims; see [retained results](../research/menu-bar-load-cost.md#native-row-command-stall--2026-10-24).

For an opt-in grouping microbenchmark, run `MENUBAR_GROUPING_MEASUREMENT_PATH=/tmp/native-grouping.json swift test --filter measureNativeGroupingProjection`. It compares two reads with one local read of the production grouping getter across synthetic workloads. The output measures that expression only; it does not establish whole-app CPU usage or scrolling performance.

### Collection-cost probes

The core load summary is tested independently of filters, including zero/missing resources and unrelated-process exclusion. Icon/status tests cover fixed capacity, geometry, count deduplication and qualified ranges; the icon has no numeric badge. The read-only collection-cost probe runs four 15-second samples; run it **alone** so other tests in the same process do not contaminate CPU accounting:

```sh
MENUBAR_LOAD_MEASUREMENT_PATH=/tmp/agent-load.json swift test --filter measureNativeAgentLoadSampling
```

For the smaller optimized core-only probe, without building the UI dependencies:

```sh
swiftc -parse-as-library -O -swift-version 6 -package-name agent-monitor Sources/AgentMonitorCore/*.swift Sources/AgentMonitorCore/AttributionAdapters/*.swift Tools/LoadProbe/LoadProbe.swift -o /tmp/agent-load-probe
/tmp/agent-load-probe
```

Pass `--history` to the optimized standalone probe for four sequential 40-sample runs at a one-second table interval, with summaries disabled/enabled/enabled/disabled. It reports the actual number of summaries alongside CPU time; run it alone and retain compiler/revision provenance when comparing results.

This development-only probe is not a package product or a release component. Both probes use local-only production collection and record process CPU time and elapsed time without saving process identities or paths. This debug test-harness measurement includes native attribution/summary collection, but excludes provider resolution and menu bar drawing and is not an app wakeup or battery measurement.

For review PNGs and release-only WebP updates, follow [native screenshot generation](previews.md#native-release-screenshot).

History tests cover cadence, filter-independent totals, peaks, projection, bounded storage, missing-vs-zero values, duplicate/rolled-back timestamps, Pause/Resume, the 28-point strip and range-menu state. Synthetic views and PTY input checks do not establish sustained CPU/wakeup cost or display legibility.

Action tests use fake termination/focus services and disposable owned processes. Native tests cover offline messaging refusal, termination/focus review and task ownership through dismissal/shutdown; shared and CLI guards ensure messaging opens no panel and performs no process lookup or confirmation.

The PTY action journey verifies bracketed paste cannot become commands or confirmations. It uses an opt-in record of fake termination calls in a test-owned temporary file, an ordered Escape acknowledgment for paste, and an undersized-through-exit case; an elapsed sleep is not proof that input was dispatched before resizing.

Removed provider transports and composers have no retained fake implementations or protocol tests. Diagnosis copy tests inject clipboard writers. Pin and action guards reject stale, hidden, reused or ineligible targets. They never write the user's clipboard or message live agents.

Keyboard/disclosure tests cover modifier handling, shared TUI mappings, repeated expand/collapse, regrouping, reused PIDs, hidden targets, pinned rows and missing-detail recovery. They do not establish physical input, clipboard, focus or accessibility delivery in the running popover.

The extended user smoke checks remain the place to assess detached-window lifecycle, live submenu/input behavior, VoiceOver, actual terminal focus, first Automation consent and display-specific legibility. Use disposable owned targets for signal checks; production messaging remains unavailable. Offscreen tests do not establish these desktop behaviors; production signing, Gatekeeper, installation/upgrades, login registration, multiple displays/Spaces and menu bar auto-hide remain unvalidated.

## Manual terminal-focus check

With disposable Terminal.app tabs, check selection in a background window, minimized window, another Space, full screen, and when monitor and target share a window. Record which activation route macOS honors and the first Automation prompt, including the controller named by the prompt. Tab selection was user-confirmed on 2026-10-15; these remaining cases are tracked in [PLAN.md](../../PLAN.md#open-follow-ups). Fake-adapter tests do not verify desktop activation. The [terminal research](../research/terminal-focus.md) explains the platform limits.

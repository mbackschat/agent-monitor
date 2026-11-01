# Native app lifecycle and interaction

AppKit owns the status item, popover and window lifecycle; SwiftUI owns native content. The app reuses shared collection, presentation and verified-action services. Headless tests do not establish physical input, anchoring or live Automation delivery.

[Architecture overview](../architecture.md) · [All architecture guides](README.md)

## Common changes

| Change | Contract |
| --- | --- |
| Popover, detachment or resizing | [Lifecycle](#diagnosis-and-detached-panel-lifecycle), [summary sizing](#summary-only-sizing), [height resizing](#height-resizing-and-persistence), [dimensions](#panel-dimensions) |
| Focus, keyboard or clipboard | [Focus](#focus-and-first-sample-selection), [navigation modifiers](#navigation-modifiers), [keyboard routing](#keyboard-routing-and-clipboard) |
| Sorting, pause, pins or options | [Stable order](#stable-process-ordering), [Pause](#pause-and-latest-pending-sample), [pins](#pins-and-population-accounting), [persistent menu](#persistent-options-menu) |
| Background collection or status icon | [Collection lifecycle](#livestatic-collection-lifecycle), [summary](#observed-agent-summary), [icon](#icon-scale-and-accessibility) |
| Rendering or performance work | [Native decoration](#reading-surfaces-and-native-decoration), [cache invalidation](#attribution-cache-and-invalidation), [profiling](#profiling-bounds-and-interpretation) |

## In this guide

- [Native menu bar app](#native-menu-bar-app)
- [Reusing unchanged collection context](#reusing-unchanged-collection-context)
- [Acceptance cost instrumentation](#acceptance-cost-instrumentation)
- [Native interaction contract](#native-interaction-contract)

## Native menu bar app

### Bundle and distribution

Local builds assemble a fresh `.app` with the shared release version, both resource bundles and license notices, then apply an ad-hoc signature. Direct release ZIPs require Developer ID signing with Hardened Runtime, the Apple Events entitlement for terminal focus, Apple notarization and a stapled ticket. Release verification checks the extracted bundle before upload and again after download. The [Mac release workflow](../macos-release.md) owns credentials, commands and first-install validation; packaging does not add a collector, runtime network access or a login item.

### Process-view row index

The legacy process/session inspection view retains one immutable `MenuBarRowIndex` for the displayed report projection. Shared `ReportProjection` owns child membership/order; the native index adds singleton flattening, visible-row lookup, process lookup and group-focus candidates. New displayed samples, grouping, sorting, pins and session disclosure replace it; selection, interval and history-only changes do not. Paused pending samples cannot change action eligibility. Row/context-menu predicates use this index without regrouping or sorting the whole table. Actions still recheck current visibility and UI state at invocation and perform their independent fresh native verification. See the [measured row-command stall](../research/menu-bar-load-cost.md#native-row-command-stall--2026-10-24).

### Diagnosis and detached-panel lifecycle

The **Diagnostics → Diagnose CPU** button starts the shared finite run without confirmation, including while the live view is paused. Help discloses three one-second waits plus native scans and metadata reads. The diagnosis occupies the existing scroll area with Cancel/Run again and a fixed Back control; it does not replace live snapshots, history or icon input. Action review blocks starting diagnosis, and diagnosis has no process actions. Drag detachment is not dismissal for any panel state: the visible detached panel retains action review, pause state, selection, open-panel sampling cadence and any diagnosis run.

Popover dismissal and detached-window closure use the ordinary close lifecycle, including discarding and cancelling diagnosis. The delegate distinguishes AppKit’s detach-to-window close reason from standard closure, as defined by `NSPopover.h`; actual detached-window close notification delivery remains a user-run smoke check. Quit drains diagnosis alongside ordinary collection and actions. Collection keeps one task handle until cancellation has drained; repeated restart requests coalesce into the latest desired state rather than retaining a chain of replacement tasks. Dismissed actions remain busy until their owned task finishes, so reopening cannot admit overlapping action work or orphan a task that shutdown must join.

The header keeps a fixed 32-point leading inset in both anchored and detached states, leaving the upper-left close-button area clear before dragging starts. The logo and title move right; the trailing buttons retain their existing right margin, and no vertical space is added. Detachment does not change content insets or reflow the header; AppKit’s did-detach callback runs only after release, so it cannot make room for the close button during dragging. The header uses the bundled Agent Monitor logo, decoded once and reused across refreshes; the status icon remains the monochrome load indicator.

### Platform reference and ownership

Apple's interface guidance is the platform baseline. The user selected iStat Menus as the main Mac resource-monitor reference on 2026-10-24; btop/htop inform terminal summaries, aligned metric columns, meters and keyboard navigation. CodexBar, RepoBar and Trimmy remain secondary comparisons for native density and disclosure. The contributor hierarchy and action review justify the complex-content exception to Apple's preference for a menu. Keep system typography and semantic colors, and preserve shared core/action ownership. Reference observations and their limits are recorded in [native menu design research](../research/native-menu-design.md).

### Status item and detachable popover

`AgentMonitorMenuBar` hosts SwiftUI content in a transient, optionally detachable AppKit `NSPopover` anchored to a fixed-width `NSStatusItem`. It is an accessory app; `popoverShouldDetach` enables AppKit’s implicit detached window using the existing content controller. Closing that window uses the normal popover close lifecycle; there is no second collector or custom window implementation. Native tables, sorting, resource summaries and action review replace terminal cell layout.

### Process disclosure, density and identity

In the legacy process inspection view, disclosure headers are full-width buttons; details and action controls stay outside the toggle target. `MenuBarRowDisclosure` gives the native style an explicit group count or process kind. Groups and processes show a leading right-facing chevron when collapsed and a down-facing chevron when expanded; process chevrons are smaller. The focus outline identifies keyboard focus independently of disclosure. The trailing group count badge and process info symbol share a minimum 32 × 20-point slot inside the row toggle. Counts can widen to preserve all digits.

Compact labels, one-point vertical padding and two-point row gaps keep the inspection list dense; accessories are decorative parts of the full-row button, not separate click targets. The separate pin button uses a 24 × 24-point desktop target. Child indentation is 24 points, and accessibility values distinguish showing processes from showing details. Counts still cover the group’s complete observed population, including individually pinned members. An unpinned session with one observed process whose row passes the filters renders directly as a process row with project/session context; multiple observed processes and explicitly pinned sessions retain a group header.

Process summaries retain one resource line with executable, compact workload CWD, PID, CPU and footprint. Standalone rows (flat, individually pinned or flattened singleton) add a compact provider/session line using the process’s last point attribution, never a containing root’s identity. Only exact point evidence permits a session ID; shared, uncertain and unresolved ownership remain explicit. A changed-label qualifier warns that window CPU includes earlier labels.

Group children with the same exact session inherit the visible heading and keep one-line density; children with a different session, including corroborated root/thread groups, retain their own provider/session line; session summaries share the adaptive session label with the overview. Process rows retain the PID and groups retain their observed count. Full paths, session IDs and attribution context remain available in tooltips and expanded details.

### Summary-only sizing

Collapsing the whole contributor table fits the Mac panel to the summary’s natural content height. The saved preset/custom expanded height remains unchanged and returns when the table reopens or another full-height view is shown. The summary also refits when visible notices change. The table stays mounted; section folding alone does not resize the window. Height selection and dragging are unavailable in summary mode. Attached popovers follow SwiftUI intrinsic sizing; the detached sizing controller owns the temporary bounds and preserves the top edge, without competing automatic hosting size constraints.

Whole-table collapse and expansion request a brief 0.18-second ease-in/ease-out native resize; Reduce Motion makes it immediate. Detached animation keeps the top edge fixed and suppresses persistence of intermediate heights. Attached popovers use AppKit’s content-size animation hint, so AppKit controls their final pacing. Dragging and notice-only refits remain immediate. TUI folding keeps the user’s terminal dimensions; text and JSON have no window sizing.

### Height resizing and persistence

The implicit detached popover window remains AppKit-owned. Its hosting root adopts flexible height bounds and the window gains the resizable style, constrained to the 620-point width and screen height. A visible bottom resize grip provides height dragging in both anchored and detached presentations, using screen-coordinate deltas and a native resize cursor; accessibility increment/decrement adjusts the height too. The grip clamps to Compact height or the smaller screen limit. Detached grip/preset resizing preserves the top edge. Resize notifications remember a session-local custom height; preset selection clears that override. Closing restores the anchored host’s intrinsic sizing, while reopening preserves the chosen height.

Neither dragging nor preset changes replaces the table. Physical native edge hit-testing is not established by programmatic window-size tests; the explicit grip does not depend on it.

### Reading surfaces and native decoration

The contributor overview uses the retained hierarchical SwiftUI ledger described under [constrained overview presentation](contributors.md#constrained-overview-presentation). Its table sections use opaque soft-gray/charcoal reading surfaces with a subtle border and inner highlight; the inspector retains its system reading background at 92% opacity. Alternating tinted and unfilled subtree bands, gaps and headings separate contributors. The surrounding popover chrome retains the system appearance. The overview owns its scrolling and keeps its bottom inspector outside the table, so disclosure does not recreate the control. The existing native drawing bridge uses group-row geometry to fill and outline each section and clip drawing to those rounded panels.

This also suppresses alternating filler stripes between panels and in unused viewport space. Row reconciliation, layout, bounds and appearance changes update the decoration without changing row ownership, input, delegates or scrolling. During native row transitions, panel edges and the clipping gap follow rendered boundary-row positions, including Core Animation presentation frames, rather than final layout rectangles. A view-bound display link tracks only the short transition after geometry changes and stops afterward; it adds no separate animation and is disabled under Reduce Motion.

SwiftUI SDK 27 provides no section-spanning background modifier for `TableRowContent`, so the retained SwiftUI table still owns all content and interaction. Workload context and retained-presence annotations are separate structured parts: Mac pairs current counts with a trailing `circle.fill` and past counts with a trailing `archivebox`; past counts use 8-point regular type and secondary contrast below the 12-point current count in a fixed 38 × 28-point stack, and remain visible under the historical-row filter. The disclosure button is fixed at 62 × 32 points with its chevron vertically centered beside the counts.

The current line includes zero; when the archived line is absent, the current count is vertically centered without resizing the button; unavailable presence shows a centered em dash. Both displayed counts cap at `99+`; tooltips and accessibility retain exact numbers. Past counts exclude current members and processes whose ownership changed; unavailable presence never becomes a zero count. Entirely historical rows retain lighter italic headings and subdued metrics/history in selected and unselected rows; paths and action controls retain readable contrast. Eye-slash means current presence unavailable, and a branching arrow means changed ownership.

The Recent contributors group uses a tray instead of a clock. Each symbol’s tooltip and accessibility label explains the state, its evidence limit and the relevant Details/Diagnostics route; absence never claims confirmed exit. Terminal text retains an explicit status. The native path truncation never spans status text. Empty action menus are omitted; current presence and membership, not zero resource values, govern historical styling and action eligibility.

### Presentation ownership

This native projection does not change grouping identities, totals or the TUI hierarchy. The view consumes `LiveReportState` and `SessionGrouping`; direct row selection is a neutral presentation operation shared with keyboard navigation. No provider recognition or process collection lives in the view. The native row index reuses the neutral `ReportProjection` for process/session labels and pinned/unpinned rows. Row stacks are lazy so offscreen controls do not all have to be constructed before the panel can respond. All observations remain in the model and resource totals.

### Focus and first-sample selection

Native focus is view-owned through `MenuBarFocus`, which distinguishes the contributor table, process-row headers, pin controls and inspection controls. Inspection transfers focus to Back or Cancel/Done; returning requests report focus while preserving the selected identity. The retained overview never uses disappearance/remount as a focus signal. `MenuBarInitialFocus` resolves a preferred process row or a first-row/loading fallback when the process view mounts. Waiting for the first sample targets a row only while focus still identifies the table; explicit navigation cancels that request and ordinary refreshes do not reassign focus. AppKit still owns the popover/window lifecycle.

### Overview focus

Contributor overview focus belongs to the native table; static totals and diagnostics are not focus targets. Inspection and pin shortcuts use its selected identity. Changing contributor selection closes existing details instead of retargeting them.

### Navigation modifiers

Native row focus follows process/session identities; up/down traverses the native projection, including flattened singletons, while ←/→ collapses/expands the focused row without toggling on repeated presses. Disclosure and single-key shortcut gates inspect Command, Control, Option and Shift rather than requiring empty event flags: numeric-keypad flags on macOS arrows and Caps Lock state must not suppress those commands. Modified shortcuts remain ignored except Shift for `<`/`>` and the scoped bulk session command on Shift+←/→.

### Collection composition

`MenuBarCollection` composes the native model's source with `MonitoringSession`; the app delegate and headless composition tests use that same wiring. Process reading and time are injectable, with native production defaults. Each collection creates its reader at startup and forwards live display thresholds and the acquisition interval to the core. Local marker/ancestry attribution runs automatically; Internet-capable provider listings are disabled.

### Panel dimensions

The native panel keeps a user-chosen height through sampling, disclosure, pausing and action review. Compact, Standard (default) and Tall select 420, 560 and 720 points; width stays 620 points. The choice lasts until quit. On opening, the host caps the height to the current screen's visible height minus 40 points. Report or action content scrolls in the remaining space between fixed header and footer controls. Root geometry changes update the popover size, with unchanged sizes ignored. The hosting view retains intrinsic sizing and is fitted before assignment to avoid an initial zero-size popover. `MenuBarLayout` and `MenuBarPanelSize` own these dimensions; the same content size applies to the implicitly detached popover.

### Stable process ordering

`LiveReportState` defaults to Stable order for the native and terminal process views. Process lifetimes and session identities have separate bounded rank maps: surviving identities keep their relative order, departed identities are removed, and new identities append. Initial and simultaneous arrival batches use descending CPU with deterministic identity tie-breaks. Switching to Stable order captures the current sort order; switching away enables the chosen resource/PID sort, and reverse is a no-op while stable. Pins remain above the ordinary list, without changing those ranks; stable children append within sessions, including pinned sessions.

Pause reconciles only when its held sample is displayed, grouping switches preserve both rank maps, and native dismissal preserves ranks for reconciliation on reopening. No ordering state enters monitoring or JSONL.

### Pause and latest pending sample

Both native and terminal inspection reuse `LiveReportState.toggleFreeze`: Pause holds the displayed snapshot, including values, membership and automatic ordering, while collection retains only the latest pending sample. Resume applies that sample immediately. Explicit sorting and disclosure remain available; action services still verify live identities. Native Pause/Resume (`p`) is in the fixed header with the displayed sample's timestamp while paused; it is unavailable before a baseline or during action review. Reopening starts live. TUI `p` uses the same semantics, with the paused timestamp and resume key first in the header so narrow supported terminals retain them. There is no implicit hover pause.

### Pins and population accounting

`LiveReportState` owns ordered `ReportPin` identities and labels. Pins bind processes by PID plus start time, and groups by the existing provider/session or unresolved-process identity. `ReportProjection` resolves pins against the displayed snapshot, emits explicit unavailable placeholders, then the normally sorted remaining rows. Pins neither retain executable action state nor expand the sampling scope. Pin order survives sort/refresh/grouping changes; pinned group children use stable arrival order in Stable order, and PID/lifetime order in other sorts. Individually pinned children are removed from group child rows, and pinned groups own their members even in flat mode.

Group totals remain derived from the complete observed findings, not the projected rows. Window agent summaries sum only contributions with agent point evidence; a row whose label changed remains visible without assigning its unknown CPU to agents. Current agent memory uses the final point attribution; grouped CPU uses the frozen labels of each accepted contribution, while the actionable child remains under its latest observed owner. Missing pins cannot execute actions and remain until explicit unpin or quitting the monitor; returning exact identities restore live rows. TUI `.` toggles the selected pin, `p` pauses and `n` sorts by PID.

Native live rows and unavailable placeholders share the same compact pin control, so sampling state cannot change its icon, size or action label. Native controls use a pin button, context menu and `.` command scoped to the focused row; Return and Space retain native control activation. Pin commands require the exact currently visible row and no open action panel, including explicit removal of unavailable pins. They never fall back to a stale selection or a hovered row. Keyboard pinning restores focus to the same identity after it moves between pinned/unpinned containers, when that identity remains visible.

Pin admission is bounded separately for the process view and overview: at most 256 pins and 64 KiB of retained identity/label text. Admission counts the normalized session identity in the overview and both identity and placeholder label in the process view. A refusal is visible; existing pins are never evicted. Removal precedes admission checks and requires no live measurement. Removing an absent overview pin also deletes its placeholder immediately. Shared `unpinAll()` clears both sets, including when no rows or snapshot are available; TUI `U` and the native View options command use it.

These are logical retention allowances, not a process-wide heap ceiling.

### Process action menus

Native row menus share Pin/Unpin, Focus terminal, Message and Terminate commands. Missing targets and action-ineligible rows retain disabled menu items. Groups permit only terminal focus when they resolve to one runtime; termination requires a process row and Message is always disabled. Expanded buttons use the same eligibility checks. The action service exposes snapshot-only focus eligibility using the same prerequisites as execution, while fresh target verification remains mandatory at execution. Menu opening performs no provider calls or native reads.

### Arrival highlighting

`MenuBarArrivals` compares process lifetime and session-group identities in successive displayed snapshots, independently of sorting, disclosure and pin containers. The initial snapshot establishes a baseline. Newly entering identities get individual monotonic three-second deadlines; unchanged identities retain their original deadline, departed identities are removed, and returning identities count as arrivals. Each new process also starts or renews its parent session header’s deadline, whether collapsed or expanded; the child retains its own deadline. A single cancellable task sleeps until the earliest expiry, with no recurring timer or process reads.

Dismissal resets the baseline and cancels expiry; Pause delays arrival detection until the held sample is displayed on Resume. Only row headers receive the semantic grayscale background, avoiding stacked group/child shading. A short opacity fade is local to that background and disabled by Reduce Motion.

### Persistent options menu

The native View options menu exposes the shared grouping, sort/direction, threshold and interval state, plus live-icon mode and a compact keyboard-help toggle. An AppKit pull-down button owns a persistent menu, populated at creation and refreshed through `NSMenuDelegate.menuNeedsUpdate` before opening. Menu commands with exact existing keyboard equivalents display native shortcut labels. Cycling view/history choices label only the destination of the current shortcut, while chart/filter/interval parent tooltips describe their cycle or step keys; arbitrary preset choices do not invent shortcuts. Snapshot-driven SwiftUI updates never mutate that control or its tracked menu items; delegate tracking callbacks only gate updates.

Grouping and sort choices are flat checked items. CPU/footprint thresholds sit under Display filters, separately from Sampling’s live-icon and acquisition controls; filter tooltips explain that observed totals and recent activity stay unchanged. Value submenus include the current value when outside the presets. Native maximum-interval presets reuse the shared TUI steps with an additional 15-second choice. Sampling also exposes explicit maximum/adaptive modes and advanced minimum, rolling-window and closed-panel-multiplier menus; invalid combinations are disabled. Direct setters update neutral presentation state and the running collector. Help renders inside the existing scroll area; it creates no window and does not resize the panel.

The native source receives an async threshold reader and `LiveInterval`, like the TUI source; settings change the existing `MonitoringSession` without a collection restart. Native dismissal clears snapshots, pause, selection and executable action state while preserving pins, grouping, sort/direction, thresholds and all sampling settings in memory until quit. Live mode retains only the latest collected snapshot for immediate display on reopening; static mode resolves missing pins after a fresh baseline.

### Status-item context menu

`MenuBarDelegate` routes right mouse-up and Control-left mouse-up to an AppKit context menu; ordinary activation retains the popover toggle. Opening the menu closes the popover through its ordinary close lifecycle. `MenuBarStatusMenu` snapshots the current indicator text for that opening and reuses `MenuBarOptionsController` for checked options without the pull-down button’s title item. Background samples do not mutate the tracked menu. Open/Quit commands execute after menu tracking returns, avoiding a dismissal race with a newly opened popover. Status information does not rely on hover tooltips, and the menu adds no sampling timer or process reads.

### Live/static collection lifecycle

`MenuBarModel` owns main-actor UI state and cancellable collection/action tasks. Live icon mode is the default: launch starts one `MonitoringSession` at the context maximum when adaptation is off, or the minimum when enabled. The former 250 ms first-sample cap is removed. Initial native/CLI/TUI settings still request 100 ms, with adaptation off and multiplier one. [Adaptive acquisition](acquisition.md#adaptive-acquisition) owns settings, visibility and timing rules; all changes wake the existing collector. CPU averages its actual measured window, and opening does not invent a short-window sample from a long-window baseline. Dismissal clears report inspection/action state but keeps live collection and the latest snapshot.

Static icon mode cancels collection while closed and restarts from a fresh baseline on reopening. Cancelled tasks drain before a replacement collector runs; collection and action generations are separate so dismissal can invalidate actions without rejecting background samples. Quit cancels and drains both. No animation or independent polling timer drives the icon. Collection failure clears the live icon's measurements; opening retries collection. Cancellation cannot interrupt a synchronous native read already in progress. Physical app CPU/wakeups remain a measurement gate.

### Observed agent summary

`MonitoringConfiguration.collectAgentLoad` opts into a UI-independent `AgentLoadSummary` on the [resource-history cadence](contributors.md#resource-history). Background refresh enriches observed same-user lifetimes through existing attribution adapters and preserves scoped `observedFindings` separately from threshold-filtered `findings`. The optional summary computes agent-associated CPU and footprint totals from those observations. No second sampler or provider recognition path is introduced. Unrelated processes are excluded; shared runtimes count once and missing resource measurements remain explicit. Native and TUI collection enable this summary for the shared history strip; text/JSONL collection keeps the optional history summary disabled; report JSONL version 1 exposes both flat process projections. Summary totals describe observed agent-associated processes, not guaranteed complete system usage or provider-reported working/idle state.

### Icon scale and accessibility

The native icon draws three thick template bars in a fixed 18 × 18-point image inside a square status item. Observed agent CPU divided by logical processor capacity fills no bars at zero, one below 25%, two from 25% to below 50%, and three at 50% or more. The fixed scale never normalizes to recent peaks. Bars derive from unfiltered `MonitoringSnapshot.observedFindings`, using the displayed snapshot while open and the latest collected snapshot while closed; Pause holds that input and Resume refreshes it.

Status text and accessibility carry raw CPU, footprint, the qualified current-window census, applied thresholds, sample time and missing-data qualifications. The projection adds no native reads and does not depend on the optional scalar-history summary. Startup, unavailable CPU and static mode use unfilled bars; status text explains availability. Static mode disables closed-panel collection. SwiftUI/AppKit use semantic colors and untinted template images, without an app-specific appearance override or polling. Never widen the status item or invert bars as an event cue.

### Action cancellation and uncertainty

The panel reuses shared action review and `SessionActions` services for verified termination and terminal focus. Confirmation targets frozen process lifetimes, whether one process or the reviewed current members of a contributor. Closing cancels owned action work; quit awaits completion. Cancellation can have an uncertain outcome, which is retained for the next opening without automatic retry. Terminal focus can itself dismiss the transient panel. Messaging remains visibly unavailable and has no native composer or saved-draft flow. Live Automation behavior from the bundle is not established by fake-service tests.

### Local packaging boundaries

The source-build script defaults to an optimized release build and assembles an ad-hoc-signed, unsandboxed local bundle with `LSUIElement` and an Automation usage description. This is separate from CLI release packaging; signing identity, notarization, Finder/login PATH discovery, login items and production installation are deferred. App and TUI collectors are independent; there is no IPC or background service.

### Keyboard routing and clipboard

`ReportShortcut` defines shared TUI/native browsing keys and their neutral state transitions. Hosts keep interval wakeups and process actions local; ordinary sorting/history changes do not wake the collector. Native report commands use one window-local `performKeyEquivalent` route, so focusing a disclosure button, picker or toolbar control cannot disable browsing shortcuts. SwiftUI `onKeyPress` depended on focus ancestry; standard unmodified `keyboardShortcut` registrations intercepted editable text in the offscreen regression. The AppKit bridge accepts only registered single keys, declines editable text/field editors and sheets, and leaves arrows, Space, Return and modified system commands to native controls.

Details close buttons use the standard cancel shortcut so Escape also works from toolbar focus. The host blocks report commands during diagnosis, reference pages and every action phase. Process-row actions still require the exact visible focused identity; overview actions use its selected contributor. Pinning restores focus after the replacement row mounts. Row headers handle ←/→ as explicit collapse/expand commands, and disclosure bindings honor that requested state rather than toggling. `y` and Copy PID write only the visible individual process’s numeric PID; groups, missing pins and reused/stale identities are rejected. Clipboard writers are injected in tests.

AppKit menu tracking retains normal menu-key handling. TUI already dispatches report keys through its host handler independently of pane focus; text and JSON have no interactive focus. See [native keyboard regressions](../../Tests/AgentMonitorMenuBarTests/MenuBarKeyboardTests.swift) and the [Mac interaction review](../development.md#mac-interaction-review).

## Reusing unchanged collection context

### Attribution cache and invalidation

The acquisition worker observes every same-user process on each scan; its default fixed period is 100 ms, with optional [adaptive acquisition](acquisition.md#adaptive-acquisition). `Monitor` caches only resolved attribution and its marker, keyed by exact lifetime. A reverse parent index invalidates a changed node and its descendants, including paths through departed ancestors retained for live children. Graph, detected-exec, terminal and metadata changes invalidate affected results. A separate runtime generation invalidates attempted detached lookups, including zero-match and ambiguous results, when runtime membership or context changes.

Cache entries do not retain resource readings or evidence timestamps: CPU, footprint and primary-point times are rebuilt from the current scan/state. Each ingest mutates its lifetime node in dictionary storage and returns only the parent/context changes needed for graph and cache invalidation, avoiding copies of the complete metadata-bearing node on stable scans. Value copies of a monitor keep independent invalidation state. New resolution inputs must extend invalidation and the cached-versus-uncached regression oracle. Cache equivalence follows Swift value equality, including canonical Unicode equivalence; it does not promise byte-for-byte preservation of metadata spelling.

The oracle covers multi-level ancestor mutations and seeded sequences of lifecycle, metadata and copy operations. Window collection does not sort rows that will be sorted again at projection; ordinary interval reports retain their ordering. Accounting rows are assembled in the same pass that obtains each cached or freshly resolved attribution, sharing the row constructor and ordering rule with uncached inspection. This removes redundant lookups without adding cache state or changing invalidation.

### Category reuse and storage charges

Accounting reuses the prior category only while attribution, executable, workload directory, runtime role and current corroborated root agree. It still ingests every accepted delta, exclusion and memory observation. Storage charges for observation/run context update when their retained fields change; merges and pressure compaction recount retained storage. Charges compare UTF-8 byte lengths, since Swift's canonically equivalent strings can have different storage sizes. The regression oracle walks all retained records independently and compares its result after updates, recovery, merges and collapse. The transactional copy used for rejected-admission rollback is preserved. Evidence-kind sets are not copied merely to insert an already-present kind.

## Acceptance cost instrumentation

### Profiling bounds and interpretation

The opt-in package-level `PipelineProfile` measures synchronous stage CPU and wall time, bounded duration samples for nearest-rank p50/p99, and dedicated acquisition/metadata/publication thread CPU. Stages and worker names are fixed enums; the sink accepts no process identities or observation payloads. Ordinary clients do not enable it. Every defined diagnostic counter is emitted, including zero values. Fixed numeric counters record cache hits and misses at each accounting-row lookup, plus detached-runtime generation changes; cache counters exclude incidental non-collection lookups and contain no identities. Thread clocks never cross a suspension; worker lifetime CPU is finalized before shutdown returns.

Stage, job and thread totals overlap and must not be added together. Samples beyond the cap preserve exact totals/maxima but make percentiles unavailable. Recent-history publication is timed separately from closing a unit because publication compacts the retained range. Collector-wide CPU plus any local-helper CPU remains the acceptance metric, including uninstrumented bookkeeping.

## Native interaction contract

### Sort and activation contract

The contributor table’s native sortable headers and options menu share the overview sort field/direction; both survive collection run and scope resets. Contributor sorts by displayed title, CPU by measured current-window CPU and Memory by current footprint. Explicit sorting orders main sessions and nested children within their groups; pins remain first and synthetic summary groups retain their trailing section order. Existing descending-resource refresh hysteresis remains in force for children; alphabetical and ascending order refresh exactly. Row-body activation selects only; process-count/chevron and native disclosure controls toggle children through shared disclosure policy. Keyboard navigation, native disclosure and row information remain separate actions.

### Reference pages and contextual help

Synthetic group symbols distinguish recent contributors, remainder, uncertainty, shared runtimes and released detail from provider/session identities, with an accessible summary-group label. The Other observed work heading and summary rows expose an adjacent information-circle button that opens the corresponding shared glossary entry, including that Recent contributors may still contain running processes. The existing reference scroll view targets that entry; closing it clears the topic and returns table focus, while the footer and menu open the glossary from its beginning.

The footer retains three separate controls—one standard SwiftUI HelpLink, a Keyboard shortcuts button and a Diagnostics button—with concise action tooltips; labelled options-menu entries also expose a separate Keyboard Shortcuts page. Diagnostics uses a labelled Measurement limits disclosure rather than an inert help symbol or a duplicated explanation. One optional native reference-page state owns presentation/dismissal; coverage badges belong to the existing Diagnostics button. Information, pause/resume, Show all, View options and Quit use compact symbols while menu and decision labels retain text.

The [Mac interaction review](../development.md#mac-interaction-review) requires an action inventory and production input evidence before acceptance.

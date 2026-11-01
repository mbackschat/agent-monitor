# Contributor overview and resource history

The contributor overview answers which coding-agent sessions and workloads account for observed CPU and memory. It shares one hierarchy, bounded recent history and inspection model across Mac and TUI. Current values, retained work and unavailable measurements remain distinct.

[Architecture overview](../architecture.md) · [All architecture guides](README.md)

## Common changes

| Change | Contract |
| --- | --- |
| Totals, ranking or remainder populations | [Eligibility](#eligibility-ranking-and-retention), [count populations](#view-choices-and-count-populations), [statistics](#statistics-and-lifecycle) |
| Session, executable or directory labels | [Hierarchy](#hierarchy-and-directory-identity), [invocation labels](#observed-invocation-labels), [executable changes](#executable-grouping-and-interval-changes) |
| Charts or retained memory evidence | [Contributor lanes](#contributor-lanes-and-temporal-spans), [scalar history](#scalar-aggregate-history), [category fields](#frozen-category-fields-and-memory-extrema) |
| Selection, disclosure or actions | [Inspection boundaries](#disclosure-and-inspection-boundaries), [retained table](#retained-swiftui-table-ownership), [exact process actions](#exact-process-inspection-and-action-menus) |
| Retention, scope or pause | [Immutable history](#immutable-compact-history), [scope](#scope-membership-and-current-context), [retention limits](#retention-limits-and-immutable-inspection), [lifecycle](#reset-pause-and-panel-lifecycle) |

## In this guide

- [Resource history](#resource-history)
- [Contributor overview and recent activity](#contributor-overview-and-recent-activity)
- [Ownership and executable hierarchy](#ownership-and-executable-hierarchy)
- [Constrained overview presentation](#constrained-overview-presentation)
- [Immutable compact history](#immutable-compact-history)
- [Statistics and lifecycle](#statistics-and-lifecycle)

## Resource history

Normal collection uses bounded working state, a rolling detailed recent window and a bounded scalar chart. None is an implicit recorder or disk archive. [Diagnostic recording](../proposals/diagnostic-recording.md) is separate, unimplemented and off by default: its off state must not create capture files, serialize scans, retain recorder queues or accumulate a second in-memory history. Explicit output/export is user-directed. Enabling recording requires an explicit Start; closing/reopening a view or using Pause never enables it.

### Contributor lanes and temporal spans

[ContributorActivity](../../Sources/AgentMonitorPresentation/ContributorActivity.swift) owns per-contributor CPU lanes for the overview. Recent snapshot publication retains at most twelve temporal spans of whole accounting units; existing record/text accounting charges every span. Before pressure eviction, publication tries six, three and one span, prioritising retained measurements over plot resolution. CPU, attribution, extrema, coverage and recovered CPU preserve their existing semantics. A contribution crossing span boundaries forces those boundaries to merge in the chart; older-opening recovery stays outside the plotted range. Values are CPU-seconds divided by the entire span duration, not interpolated scan samples or peaks. [ContributorChartRange](../../Sources/AgentMonitorPresentation/ContributorChartRange.swift) holds one shared fixed display range.

Native and terminal entrypoints read [ProcessorTopology](../../Sources/AgentMonitorCore/ProcessorTopology.swift) once at startup using `hw.logicalcpu_max`, `hw.nperflevels`, and every level’s `name` and `logicalcpu_max`. Recognized `Performance` and `Super` populations determine the default × 100%; `Efficiency` is excluded. Every level must have a known name and positive count, and their sum must equal the full count. Missing, unknown or inconsistent topology falls back to all logical CPUs; level order or chip names never imply a split. Maximum counts prevent power-mode changes from changing the default. Without injected topology, deterministic hosts initialize once from the first recent snapshot’s logical count.

Activity, arrivals/departures, pause, sort, pinning, run/scope resets and view changes cannot rescale it. The Mac View options menu and shared `b` shortcut select hardware default or an explicit fixed range, including full logical CPU range; the choice survives collection resets but is not persisted between launches. This is a readability range, not equivalent computing power or evidence that particular core types are occupied. Equal-width bars show whole interval averages in chronological order, not a linear elapsed-time axis. Each average uses its own actual duration.

Mac row-chart tooltips briefly explain the averages and gaps; the TUI header shows the shared fixed scale, with interval semantics explained in Help. The Mac overview has no permanent chart caption below its table. Mac bars align to physical pixels so rounding cannot alternate their widths. Above-ceiling values retain their data and show an orange cap in Mac or warning-colored full-height terminal bars/caps. Monochrome terminals use ↑; it marks overflow, not a rising trend. Mac and TUI Details do not repeat the row chart or expose its interval-value inspection.

No additional data is retained solely for a chart; the proposed contributor-hour history was withdrawn under this constraint. Mac contributor and process Details offer Copy all, exporting complete already-available text, including full paths and collapsed attribution evidence; copying does not read new arguments. Process counts use an aligned Item / Value / Meaning table; deeper attribution evidence starts collapsed under Attribution details and uses the same explained table. An accepted zero differs from an unmeasured gap. Qualified spans have a visual cue; material gaps remain in coverage. Current memory has no historical lane.

Pinning and sorting rebuild summary lanes even while paused, so their membership and sums agree with the visible tree.

### Scalar aggregate history

[ReportHistory](../../Sources/AgentMonitorPresentation/ReportHistory.swift) owns UI-independent scalar history from `MonitoringSnapshot.agentLoad`. It retains at most 3,601 one-second buckets, with per-metric peaks inside each bucket and a separate latest value. It never retains process identities or snapshots. Time-window projection produces right-closed peak buckets over the last 600 or 3,600 seconds (so 40 observations 15 seconds apart fill 40 distinct 10-minute bins), leaving empty/unavailable buckets unfilled. Snapshots without a summary leave the history unchanged; duplicate summary timestamps are ignored; a backwards wall-clock jump starts a new timeline. CPU/footprint require complete measurements within the observed summary; heavy count requires both resources complete. Table thresholds, grouping, sorting, pins and unrelated-process visibility never redefine the history population or heavy thresholds.

### History, pause and collection resets

`LiveReportState` owns the collected history, selected metric/range and a frozen copy for paused inspection. Normal receipt records history before holding a paused snapshot; Resume reveals the intervening samples. Collection reset preserves history and choices while clearing paused inspection. The native host also records closed-panel samples after its collection-generation guard. History advances only on summary-bearing samples, with no timer, persistence or extra native/provider reads of its own. Every report enriches all observed lifetimes, independently of display thresholds, and includes a fresh summary when requested; `agentLoad == nil` means no summary was collected, not zero load or a collection error.

The native icon derives its values independently from all observed agent findings at each displayed sample. Collection-cost evidence belongs in research, not an assumed zero-cost claim.

### Aggregate strip presentation

The secondary process view spends one TUI header line on the aggregate strip, including `h` metric and `t` time-range hints. Native presentation uses a 28-point strip inside the fixed-height scroll content, semantic grayscale bars over a persistent subtle baseline and the existing persistent AppKit options controller in a history-menu placement. That menu has checked metric/range choices and retains its items while tracking. Its title changes only outside tracking when the selected metric/range changes. The native current-value label says “No data” for an unavailable measurement, with explicit empty-history accessibility text; measured zero retains its numeric value. Both views scale bars from zero to the visible peak, at least 1; peak compression preserves short observed bursts without inventing measurements between samples.

Text/JSONL, TUI and native live collection default to a 100 ms requested start-to-start period; acquisition overruns delay the next scan, while resolution and presentation run independently. Explicit intervals override these defaults. Closing the native panel applies its configured maximum multiplier; the default multiplier of one preserves the selected cadence. See [adaptive acquisition](acquisition.md#adaptive-acquisition).

## Contributor overview and recent activity

Overview totals align with the contributor CPU and memory columns beneath their headings. The native header owns sorting, totals, the overall lane and process-count context outside the collapsible table; header and row metric widths share one definition. In a sufficiently wide TUI, the three existing summary lines hold metric headings, totals and Recent CPU at the right while the chart stays in its lane. Narrow or short terminals retain the inline summary. Accounting and history populations are unchanged.

The overall CPU lane derives from the existing `ContributorActivity` process/category leaves, including collapsed-detail categories, rather than summing visible groups or parents and children. It uses the row lanes’ same spans, scale, gap and qualification semantics and retains no separate history. Filtering, pinning, sorting and folding cannot change its population. It is monitored contributor CPU, not host CPU. Mac aligns it with the row chart column; TUI displays it at graph-capable sizes.

### Sections and folding

`ContributorTableSection` partitions presentation into Pinned, Sessions and Other observed work in both interfaces. Section folding and whole-table folding are independent of child disclosure and measurement filters. Folded rows are excluded from navigation and action targets; their selected identity and open children survive refresh while still eligible. Folding hides Details. Native `Section(isExpanded:)` keeps headings nonselectable; the retained table stays mounted when hidden. TUI places P/S/O and the disclosure state directly in the section dividers, retaining folded headings without making them selectable, and leaves the table visible. Totals, coverage, overview controls and the overall lane remain outside whole-table folding. Text and JSON retain their flat, noninteractive output.

### Main contributors and quantified remainders

The native app and TUI default to **Main contributors**, a shared quantified disclosure of the collector's population. Resource threshold filters remain off by default and never change totals or history scope. Lower contributors collapse into a remainder carrying their distinct lifetime count, current CPU/memory, recent CPU-seconds and missing/filtered measurements. **Show all** opens the recent/remainder sections; sessions and executable groups retain explicit disclosure. An always-visible **Unresolved / uncertain** summary and separate adapter-recognised shared runtimes preserve unattributed work. Section CPU/memory partition their stated populations; historical session membership counts are not additive. Zero CPU is not evidence of termination: an idle memory-heavy session can remain a main contributor.

### Eligibility, ranking and retention

[ContributorOverview](../../Sources/AgentMonitorPresentation/ContributorOverview.swift) owns the same selection, statistics, pins, disclosure and navigation for both hosts. Individual entries are the union of the top five exact session/root groups with combined CPU **strictly above 25% of one core** and the top five with **100 MB** current footprint or more.

The main list and every child list (executable groups, process lifetimes and summary-section contents) follow one refresh rule for the selected metric: surviving rows keep their positions and newcomers arrive in descending order, but a row moves above any row it exceeds by more than **120%**, so no row stays below one it exceeds beyond that band. Ties fall back to the other metric, then identity. Explicit CPU/memory ordering sorts every level exactly without leaving the overview. Selection uses the same band: a challenger replaces an eligible incumbent only above **120%** of its ranking metric, with provider-qualified identity breaking ties.

A session with at least **0.5 recent candidate CPU-seconds**, a **100 MB sampled worker footprint**, or a main-list departure within 60 seconds remains discoverable in **Recent contributors**. Other exact sessions enter the quantified remainder. Pins promote the owning session once; they do not duplicate section totals. These are initial relevance defaults, not measured optimal constants or a hard population limit.

## Ownership and executable hierarchy

### Hierarchy and directory identity

The hierarchy is corroborated root → exact thread/session → contributor (display name × frozen workload directory) → exact process lifetime. Redundant single-thread levels collapse. Session rows lead with provider and the first eight session-ID characters, followed by a compact directory summary (one path, or a count); the full ID and directories are in details. Compact paths extend matching suffixes among observed non-runtime workload directories until the labels distinguish them; full paths remain available in inspection. Contributor headings show the executable without a lifetime-count multiplier; current process counts remain separate and recent worker populations remain in Details.

Rows show their directory unless the owning session has only one; an unreadable directory reads “CWD unavailable”. Lists longer than four show the top three and one “+N more” row with the hidden rows' merged statistics, opened automatically when the selection is inside it. [SessionCorroboration](../../Sources/AgentMonitorCore/SessionCorroboration.swift) owns the root rule used by both live grouping and acquisition-time history: present-day corroboration cannot regroup past work after a root runtime leaves. Provider/runtime-only, unknown and genuinely conflicting evidence remain distinct from exact session candidates. Project directories provide context, never ownership.

### Observed invocation labels

An adapter may supply an observed embedded-workload invocation label from the already captured `argv[0]`, independently of full command capture. Claude supplies this only for a recognised Claude executable invoked under another basename; other executables keep their native name/basename. Empty, control-containing or over-160-scalar names are rejected. `HeavyProcess.invocationName` supplements the native `name` and `executable`; it is neither executable identity nor ownership evidence. The invocation label is frozen in recent and collapsed categories, so a later invocation observation cannot rename earlier CPU. JSONL schema 1 carries it as an optional field. Native/TUI process labels and contributor groups use the observed label; inspection retains the underlying path.

### Terminal field roles and hierarchy

The TUI contributor ledger styles fields within a line: blue bold identities, blue borderless history, cyan bold values in the active CPU/memory sort column, and normal-contrast directories/counts. The other resource values remain bold; the sorted header has a direction arrow. Attribution headings use the ordinary identity style in TUI and a neutral question-mark folder icon in Mac; their explicit wording distinguishes unknown ownership from warning-colored chart overflow and measurement gaps. The cadence/update/chart-range text uses the subdued footer-hint style in contributor and process views; chart glyph colors remain independent.

Selection uses reverse video for the headline and CPU/memory cells with the persistent `>` marker; charts remain unhighlighted and context retains its own emphasis. Selected resource cells use selection styling ahead of the active-sort accent; unselected resource cells retain that accent in contributor and process tables. Section rules and connected `├─`/`└─` branches distinguish groups without color. Ancestor trunks continue through count and wrapped-context lines only while siblings or displayed children remain. Synthetic groups show their population once. At 100 columns or wider, context wraps within the contributor column; below 100 it retains full-width flow.

Viewports of at least 20 lines separate sibling contributor blocks with a spacer, carrying any continuing ancestor guides across it. Concise retained-state labels stay in the row; full ownership-change explanations remain in Details. Grouped/flat process tables carry the same identity and sorted-resource roles. Contributor and process Details retain colored field labels through wrapping and clipping, with normal-contrast values and targeted resource/uncertainty accents. These are terminal presentation rules, not changes to attribution, membership or JSON fields.

### Disclosure and inspection boundaries

Overview folding and inspection are separate. Parent expansion reveals children only; process leaves use a dot. Shared typed `InspectionField` values supply aligned terminal details and the native bottom inspector, including population counts, identity, directories, interval coverage and memory evidence. TUI `i` and Return, and native `i`, the selected row’s **ⓘ** button or its context menu open inspection explicitly. TUI Return opens the current view’s Details without changing the table or toggling an already-open pane. Explicit `v` view switching can carry a selected current worker into process inspection, preserving grouping. Column headers do not target selected rows.

Native inspection leads with resource values and agent/session, directory and executable context; population counts and measurement evidence have their own disclosure. Inspection fields explicitly reset inherited row line limits and size values vertically, so full directories, executable paths, identifiers and arguments wrap and remain selectable inside the bounded scroll area. Compact row labels may abbreviate context; inspection values must not ellipsize it. It does not add evidence rows to the contributor list. Refresh/filter changes that remove the selected row close details rather than retargeting them; native keyboard focus moves into the inspector until it is closed.

Current-process navigation still requires a current exact lifetime. Material coverage/pressure indicators remain visible outside inspection.

### Executable grouping and interval changes

Contributors use the case-preserving basename of the observed path, except that an adapter-recognised agent runtime is named “<provider> runtime” without a workload directory, because its basename can be a version string and its directory is not a workload directory. Different installation paths can share `executable node`, while `node_repl` remains separate when that is its basename. Full paths, available command/tool descriptions, exact identity and evidence remain inspectable. Aliases, version stripping and generic Java/Node recognition heuristics are excluded.

A CPU contribution uses its closing observation's executable. A changed path/name between its accepted counter endpoints is disclosed as **Executable changed across interval**; that does not verify exec time, and equal paths cannot rule out exec. Workers exclude only members recognised by attribution adapters as agent runtimes; unclassified services remain workers.

## Constrained overview presentation

The overview defaults to CPU order. Stable order retains the displayed order at activation and preserves surviving sibling order at every depth on refresh, including quantified remainders; newcomers append in deterministic identity order. Main/recent/remainder eligibility and measurements continue updating. Stable does not freeze population, and reverse/Ascending is inert. Explicit CPU, memory or contributor sorting restores the corresponding ordering.

### View choices and count populations

Headers show **Main contributors (X/Y)** or **All contributors (Y)**. Y counts retained top-level session groups with contributions; X counts their intersection with main and pinned groups, deduplicated. Root/thread aliases count once; missing pin placeholders and synthetic shared, unresolved and released-detail groups are excluded. Retained departed sessions and exact collapsed-only session groups still count. Expansion does not change this population. Header help names the population, and native menu labels use the same counts. `ReportView` projects the existing overview/population/grouping state into four mutually exclusive choices: Main contributors, All contributors, Processes by session and Processes. Menu choices assign a view idempotently.

Shared current-view sort and reverse commands never navigate; PID is unavailable in the overview. Menu checks use the chosen view consistently even before its recent snapshot is available. If a received snapshot has no contributor history, the controls reflect the rendered process view and contributor-view menu choices are unavailable.

### Retained SwiftUI table ownership

The native hierarchy uses SwiftUI `Table` with recursive `DisclosureTableRow` content and shared contributor IDs. The overview report remains mounted beneath diagnosis, action review and the process view; inactive content is invisible, disabled and excluded from hit testing/accessibility. Keeping its structural position preserves native selection, scroll and expansion state on return. Initial overview state is collapsed; ordinary transitions do not recreate an already-expanded table or toggle disclosure to repair it. [Dated research](../research/native-menu-design.md#retained-swiftui-table-adoption--2026-10-27) records the framework initialization defect and rejected alternatives. [Production lifecycle checks](../../Tests/AgentMonitorMenuBarTests/MenuBarContributorRetentionTests.swift) and [table guards](../../Tests/AgentMonitorMenuBarTests/MenuBarContributorTableTests.swift) cover retention, hierarchy, selection and refresh. AppKit retains application/window lifecycle ownership.

A narrow `MenuBarTableState` synchronizer uses the public backing `NSOutlineView` to restore selected identity after reparenting, release first responder while inactive; SwiftUI owns rows, disclosure, columns, layout, delegates and data sources. It checks row count and live selection/activity before applying the shared visible-row index and cancels superseded/dismantled work; a queued restoration cannot overwrite a newer selection. Opening the bottom inspector reveals the selected row within the reduced list viewport without continuously forcing scroll position. There is no custom outline-table implementation.

### Ledger layout and bottom inspector

The accepted [contributor ledger](../research/native-menu-design.md#ledger-studies-and-temporal-publication--2026-10-28) uses a whole-row upper band for identity, a CPU activity lane and aligned current CPU/memory, followed by an executable/CWD band (full-width in Mac and terminal widths below 100 columns; confined to the contributor column in wider terminals). Recent-only rows name their retained CPU and absence from current observations; unavailable current memory is not zero. The Mac table uses one column because SwiftUI has no spanning table cell; external accessible buttons sort identity, CPU and memory in both directions. Subtree-based row shading, synthetic-group symbols, native disclosure, stronger child inset and branch connectors establish hierarchy.

Top-level contributors have larger headings and a gap before them, so a new root is distinct from the previous branch’s final child. The 620-point panel reserves chart height rather than squeezing context beside it. The TUI keeps the selected row block complete when it fits; at 90 columns and sufficient height it uses a three-row CPU plot, otherwise it removes the chart before sacrificing identity, values or coverage. Full paths, identities and evidence remain in a bottom inspector. TUI Tab switches rows/details, arrows scroll only a visible focused pane, and Esc returns; detail scrolling is independently bounded.

Native table and inspector share the available content height; inspector metrics, fields and actions scroll beneath the owning identity. Inspector focus returns to the retained table on close only while the overview is active. Selecting another contributor closes its inspector rather than silently retargeting it.

### Hide no-longer-observed rows

The shared overview owns the optional `hideNoLongerObserved` presentation filter. Its default is off. Native overview options and TUI `H` expose it. Text and JSON have no corresponding interactive filter. It removes only rows whose current presence is known and whose observed members are all absent, keeping uncertain presence and mixed groups. Filtering affects the visible tree, not nodes, totals, activity or pin identities. A hidden selection moves to a visible row and closes its inspector. The Mac shows the number of otherwise-visible rows hidden by the filter and a direct restore control.

### Native disclosure and section decoration

Native contributor interaction separates selection from disclosure: row-body clicks select, while the 32-point-high process-count/chevron button and native disclosure control expand children. Count tooltips and accessibility values explicitly name currently observed processes. Root-session pin toggles appear on hover or their own keyboard focus unless pinned; a descendant’s context menu targets the owning session without changing selection. Pinned/Sessions/Other observed work are native SwiftUI Table sections with separate, nonselectable headers. Each section has a rounded neutral panel with a fine outline and inner highlight; native section spacing separates panels, and a collapsed section retains its compact title strip.

Selection belongs only to contributor rows. The native selection bridge excludes group-header rows when mapping contributor identities, and section ancestry adds one native outline level without changing shared contributor depth. A pin accent and uncertain-work symbol supplement subtree shading. The table uses SwiftUI inset alternating style to omit its separator decoration. A cell-local native appearance anchor clears the public backing row background and supplies a rectangular full-row subtree fill plus tree guides. The fill spans native cell padding at one consistent inset; guides reach row boundaries, connect at the headline and carry unfinished ancestor trunks through deeper descendants.

Decoration remains attached to the native row during motion and does not replace delegates, rows or selection drawing. Contributor disclosure buttons use the same headline offset as the guide elbow rather than the center of the multiline row. The bridge finds the standard public AppKit disclosure-button identifier and adjusts only its vertical frame, preserving its native target/action, size, focus and accessibility; section headings retain native alignment. Mac chart lanes omit ceiling outlines while retaining a common range label and overflow markers; TUI plots retain explicit ceilings.

### Exact process inspection and action menus

`ContributorOverview.inspectedProcess` binds native bottom-pane process inspection to the selected contributor and an exact lifetime. `LiveReportState.contributorProcesses` intersects the visible contributor’s current population with nonhistorical `snapshot.observedFindings`, so display thresholds do not disable an observed member. Back clears only the process destination; Close, selection changes and lost targets clear inspection. Argument requests reconcile against this destination and cannot publish after leaving it. The same reusable native process-detail view serves the explicit process browser. Contributor action menus show k/f hints only when the command is available for the exact keyboard target; other targets omit the cue.

The same rule applies to command buttons and tooltips, without preparation instructions, selection changes or competing shortcut registration on each row. Contributor action menus name an exact current target before entering the shared frozen action review; they do not borrow hidden process-browser selection or bypass service verification. Offline messaging remains disabled. TUI Return stays in Details; only explicit view switching enters the process browser.

### Process-view hierarchy

In the secondary TUI process view, explicit `├─`/`└─` branches come from the shared projection’s visible group membership, including pins and filters. Only the descriptive column carries the tree; resource columns stay aligned. `PID/#` distinguishes process PIDs from `#N` group counts. Groups name their process count explicitly, while the shared glossary distinguishes display-window population from latest-sample presence.

### Terminal controls, help and chart geometry

The TUI uses letter keys P/S/O for section folding, U for unpin-all and I for CPU investigation. Whole-table folding has no terminal binding; native 5/6/7/8 controls and shared folding state remain unchanged. Digits 1–4 only change resource filters. Contributor and process Details both honor -/+ sizing and M/= maximize/restore with the remembered 10–90% split. Only Keyboard shortcuts help emphasizes key names with color, bold and underline; view and reference-page footers use subdued neutral text. Footers use at most three lines; a horizontal rule separates the content from at most two hint lines in every report/reference/diagnosis view.

Compact footers prioritize view, Help, pause, quit and warnings; optional hints move to Help when they do not fit. Reference wrapping and clipping preserve structured shortcut, label and value styles. At widths of at least 100 terminal columns, Keyboard Help partitions whole sections into two columns with a four-cell gap, choosing the split with the shortest taller column. Styles survive composition, and paging/offset bounds use the resulting physical row count; narrower layouts remain single-column. Stacked charts retain eighth-cell steps in every row (24 height steps across three rows); only fully occupied cells receive solid backgrounds.

Partial caps must never receive a full-cell background or round up to a whole row. Font padding can still affect the physical cap/interior boundary; retain the [font study and accepted appearance](../research/terminal-ui.md#terminal-keys-text-emphasis-and-three-row-charts--2026-10-31) rather than claiming all terminal/font combinations are seamless. The overall chart shares the three summary rows, beginning at screen row zero and aligned with contributor lanes; render it only when all three rows and their summary text fit. Keep the visible-row indicator in the text column so it cannot overwrite the chart. Color fills use blue cell backgrounds and monochrome fills use reversed spaces.

Numeric percentages and retained samples remain unchanged. When contributor charts are visible, the footer adds a neutral three-line legend at the right only if every shortcut line fits with at least three columns of separation; it never adds rows or clips controls.

### Viewport, summary and diagnostics

The contributor viewport uses its full available height above selection rather than a half-height centering allowance. A following unselected block may be clipped at the bottom once its identity/resource line fits; the selected block stays complete and the range indicator reports remaining content. The TUI overview uses three summary rows: title/sort/view, cadence/chart scale, and totals with the overall chart when space permits. CPU and Memory totals are bold; the active sort metric uses the same cyan accent as its column. Stable and contributor sorting leave both totals neutral and bold. The separate section-shortcut row is omitted.

The TUI overview packs whole key hints within the terminal width, retaining quit/resume and **? Help** at constrained heights. Both interfaces retain a compact material-coverage indication. The native footer Diagnostics button carries an orange warning badge for measurement gaps or an information badge for notices, with a plain-language tooltip explaining the limitation and directing users to open Diagnostics. Technical summaries and counts appear inside Diagnostics; footer and options-menu controls open the same page. Detailed census, read failures, cadence, pressure, ownership and offline-capability explanations live in passive **Diagnostics**, separate from starting a finite CPU diagnosis.

Native diagnostics use a bounded scrollable popover; TUI **D** opens a scrollable page and **Esc** returns without changing selection or pause. **?** opens a contextual shortcut guide in both interfaces, with controls and actions filtered for the underlying view and selection. Mac uses its existing scrollable Keyboard shortcuts popover, also reachable from the options menu, and restores table focus when it closes; TUI uses a scrollable terminal page with **G** for glossary, **D** for Diagnostics and **Esc** to return. **Help & glossary** (TUI **G**) provides shared definitions from [ReportGlossary](../../Sources/AgentMonitorPresentation/ReportGlossary.swift).

Process counts mean exact lifetimes present in the latest displayed sample; recent counts cover the retained range and may overlap.

## Immutable compact history

[AccountingWindow](../../Sources/AgentMonitorCore/AccountingWindow.swift) consumes accepted scans on the collection thread after applying available timestamped enrichment. The same accumulator seals each original one-second unit for [RecentActivityStore](../../Sources/AgentMonitorCore/RecentActivityStore.swift) before display merging, with strictly increasing scan order asserted. Rejected scans do not enter history. Live history is a typed `MonitoringSnapshot.recentActivity` sidecar used by Mac/TUI; machine reports use the same compact CPU sums under report schema 1. This is in-memory reporting, not disk recording or a replay format.

### Frozen category fields and memory extrema

A compact category is **exact lifetime × frozen semantic session label/state × executable × observed workload directory × adapter runtime/worker role × corroborated root/thread**. Repeated equivalent evidence does not create a new key. A directory change opens a new category, so a contribution keeps the directory observed at its closing scan, like its label and executable; an unreadable directory forms its own category and never inherits a neighbour's. Collapsed categories release the directory with other identity detail.

Each category retains eligible within-unit CPU-seconds and accepted/excluded counts, first/last observation, latest footprint including unavailability, largest sampled footprint with scan/time/point evidence, last successful kernel peak with scan/time/evidence and later unavailability, and a bounded evidence summary. Memory maxima are accumulated at acquisition cadence, before latest-only observations overwrite spikes. Equal maxima retain the earlier observation. A last kernel peak may decrease after exec; it is not maxed across time, has no verified peak time or exec epoch, and may predate the recent range.

Within-unit sums contain only contributions whose opening scan is at or after that unit's baseline. Contributions opening earlier remain individual records with original endpoints and frozen category. Whole-unit range queries add compact sums plus crossings eligible at the retained baseline, and expose older-opening CPU separately as recovery. They never prorate an interval, add displayed percentages, or claim arbitrary within-unit cuts. The range maximum is the maximum of retained per-unit maxima; no runner-up or raw per-scan footprint archive is needed.

Closed labels are immutable. An unresolved observation followed by a resolved one keeps the earlier CPU unresolved and affects only later contributions; it is not a contradiction and does not silently migrate CPU to the later session. Actual conflicting evidence stays uncertain. The broader historical-revision contract remains gated with [diagnostic recording](../proposals/diagnostic-recording.md). Pending evidence belongs only to open work; closure without an exact label produces unresolved records.

### Scope, membership and current context

History follows the collector's configured scope: agent-associated by default, all same-user processes for TUI `--all-processes`, with existing collector exclusions. A unit retains all frozen categories of a lifetime if any category qualifies for scope, preserving mixed known/unknown work without assigning unknown CPU to a session. A later unit cannot retroactively admit an older out-of-scope unit. Final-scan presence uses the full identified scan; current context for retained lifetimes can disclose a subsequent departure from agent scope.

The store reference-counts each retained category’s lifetime as whole units enter and leave, so selecting current context does not rescan the entire retained history on every publication. Multiple categories of one lifetime keep separate references; run/scope resets and admission gaps clear the index. All-process scope needs no membership index. The index is bounded by retained category records; it does not establish a process-wide heap ceiling. Current memory always uses the final observation and label, never stale footprint merely because an identity remains present. Failed reads retain distinct PID values by status and observation counts, never invented distinct workers.

Native enumeration requests same-user PIDs. Failed listed PIDs have no verified agent ownership; coverage is collection-wide and PID reuse cannot be resolved from failures.

## Statistics and lifecycle

| Statistic | Meaning |
| --- | --- |
| Candidate CPU now | Eligible unique frozen point-labelled contributions divided by the enclosing display-window duration, in one-core percent. The actual duration is shown; coalescing may make it longer than one second. Unresolved/conflicting CPU remains separate. |
| Memory / processes now | Latest footprints and distinct identified lifetimes in the final scan under their final labels. Missing memory and unavailable final-scan context are explicit, not zero. Departed workers contribute no current memory. |
| Recent workers / agent runtimes | Distinct lifetimes with the corresponding observed adapter role during the retained range. A role change can appear in both populations; parent process counts deduplicate. |
| No longer observed | Recent worker identities absent globally from the final scan. Returns and expiry can reduce it. It is neither monotonic nor confirmed termination. A worker still present under another owner is a membership change. |
| Recent CPU-seconds | Unique eligible measured CPU in the actual retained range, partitioned by frozen point-candidate, unresolved/conflicting or shared labels. A lifetime may belong to several historical sessions; its contributions are not duplicated. |
| Largest sampled worker footprint | Largest retained acquisition reading for that worker/category, with time and point evidence. It is neither a time sum nor a verified true peak. |
| Last kernel task peak | Latest successful kernel peak reading with time and point evidence, even after departure. Peak time and exec epoch remain unverified. |
| Coverage | Actual range/run, distinct same-user-listed PID values with read failures (denied, identity mismatch or other) and exits before read, per-scan mean/max failures, exclusions, older-opening recovery, attribution uncertainty and retention gaps. Failed PIDs have no verified agent ownership. Polling can still miss entire lifetimes and final exit CPU. |

### Retention limits and immutable inspection

The target recent range is **60 seconds**, bounded by **65,536 logical records** and **16 MiB UTF-8 text**, including retained/published/frozen backing and current context. Units evict whole; the newest oversized unit is not cut to pretend it fits 60 seconds. Capacity pressure can shorten the range or make current context unavailable, which is visibly labelled. The store retains the latest loss boundary time; the qualifier clears once that boundary is outside the target range, while already-published inspection remains immutable. Published immutable projections hold charged leases; paused inspection remains self-contained while live history may develop a retention gap.

Detail strings are formatted on demand from retained typed evidence. The compact current display aggregate remains separate from the recent suffix so history expiry does not silently change a coalesced current rate. The open unit, including its separate final-scan context, is charged against the existing pipeline bounds before acceptance; it is not an unbounded raw-history queue.

### Reset, pause and panel lifecycle

Run or scope replacement discards old history and starts a labelled new range; CPU never crosses runs. Admission gaps start a new contiguous segment. Live-icon collection ingests history while the panel is closed; close/open preserves that store while clearing paused inspection and releasing obsolete projection leases. Static-icon mode stops collection on close and labels the next run **Collected since panel opened**. `resetCollection()` preserves preferences/pins and the separate collection service, not old worker inspection or stale main-list departure timestamps. Pause freezes both summary and drill-down; Resume uses the newest available projection. Exit discards in-memory history.

### Status context and deferred extensions

The Mac status icon retains its load bars and removes the unqualified numeric badge. Status text carries the full census: observed agent-associated processes in the current window, including the number no longer observed. Native and terminal overview lanes share the temporal CPU projection described under [resource history](contributors.md#resource-history); current numeric CPU and memory retain their measurement units. Compact warnings expose missing coverage beside totals. TUI group disclosure reveals children; selected worker evidence or explicit `i` details keeps explanations separate from ordinary folding. Native disclosure uses the existing panel; TUI uses the same nodes with bounded terminal rows and scrollable detail.

Current-process inspection preserves grouping, opens the containing process group and enters the existing verified action flow; historical overview rows cannot perform actions. Separate Explorer windows, retroactive revisions, session historical memory peaks and cumulative distinct totals remain [deferred extensions](../decisions/resource-overview-extensions.md).

Synthetic capacity and timing evidence is recorded in [overview validation](../research/menu-bar-load-cost.md#overview-implementation-validation--2026-10-24); native physical interaction remains a user smoke check.

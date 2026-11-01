# Review the resource overview

Use this procedure for Mac or TUI recommendations, implementation and review. Start with the shared requirements, then select the affected platform checks. For running tests and collecting evidence, use [native validation](native-app.md) or [terminal validation](validation.md#terminal-and-machine-output-checks).

[Development guide](../development.md) · [All development references](README.md)

| Review | Start here |
| --- | --- |
| Decide what the interface must communicate | [User-first presentation](#user-first-presentation), [shared information](#shared-information-and-diagnostics) |
| Trace a reported defect across outputs | [Cross-interface review](#cross-interface-issue-review) |
| Review native controls, focus and layout | [Mac interaction](#mac-interaction-review) |
| Review terminal navigation, layout and charts | [TUI interaction](#tui-interaction-review) |
| State what passed and what remains open | [Evidence and maintenance](#evidence-and-maintenance) |

Use the [monitor-ui-ux skill](../../skills/monitor-ui-ux/SKILL.md) before UI/UX recommendations as well as implementation. Choose the platform-specific checks below; shared data semantics do not imply identical controls. Scale the review to the change instead of redesigning unrelated surfaces.

Review Mac and TUI against the [product question and information contract](../product.md), not against a generic system monitor. Use deterministic fixtures with several simultaneous CPU/memory contributors, two sessions in one CWD, one session across several CWDs, repeated executables, departed workers and unavailable/uncertain data. Check that agent/session, workload CWD, executable and contribution remain understandable together before inspecting every PID. Check nested CPU/memory ordering on receipt and explicit sort, and that row selection/disclosure remain attached to identity.

Before choosing a control, state the user's task and the required selection, disclosure, inspection, sorting and focus behavior. Check the installed SDK or current primary documentation rather than recalling framework limitations. Explain why a recommended fallback is needed. For hierarchical Mac tables, consult SwiftUI's [Table](https://developer.apple.com/documentation/swiftui/table) and [DisclosureTableRow](https://developer.apple.com/documentation/swiftui/disclosuretablerow) before proposing `NSOutlineView` or custom button stacks. A small headless experiment can settle an uncertain API requirement; a screenshot cannot establish input behavior. Include siblings before and after expanded branches: the [2026-10-27 triage](../research/native-menu-design.md#swiftui-following-root-triage--2026-10-27) passed with the expanded branch last but failed when another root followed it. Keep a failed integration check distinct from a reduced framework reproduction. Historical probes and the superseded bridge were removed after [retained SwiftUI adoption](../research/native-menu-design.md#retained-swiftui-table-adoption--2026-10-27).

Run `swift test --filter 'nativeContributor|nativeOverviewUsesAnOutlineTable|queuedTableReconciliation'` for production table and lifecycle checks. Start the table collapsed, expand nested branches before a following root, and enter/leave actual diagnosis, process inspection and action review. Check native view identity, row hierarchy, selected process, disclosure, scroll position and stable viewport pixels across hidden refreshes, plus focus leaving the hidden table. Pin/unpin a selected descendant as well as sorting: the native selection synchronizer must preserve its exact identity after reparenting. Queue a native selection restoration and then select another row before it executes; the newer choice must win. The synthetic checks do not establish physical key delivery, hit testing or VoiceOver; include those transitions in the user's native smoke test.

## User-first presentation

Design around the user's decision, not the internal data model. The user's 2026-10-30 review established these acceptance rules for Mac and TUI:

### High priority: be concise in Mac and TUI

Author each tooltip or contextual hint for one immediate purpose, normally within 75 characters including any available shortcut. Use one short phrase, not paragraphs, implementation explanations or instructions repeated from neighbouring controls. Do not shorten by blindly truncating text or hiding essential uncertainty.

Put fuller definitions in Help & glossary, deeper evidence in labelled disclosures and full paths/arguments in selectable Details. In TUI, keep labels, status lines and keyboard help brief and use its existing scrollable detail/reference pages for explanations.

Audit shared help strings and inherited ancestor help as well as local literals; a short control label can still inherit a large tooltip. Review default and hover text separately.

### Lead with what matters

Before adding a field or control, state what it helps the user understand or do. At a glance, users should find the responsible agent/session, workload, resource use and any limitation that changes how they interpret it. Do not give implementation metadata the same visual weight.

### Use progressive disclosure

The default view shows the useful summary. Details adds context and comparisons; deeper attribution evidence, identifiers and diagnostic mechanics are available on demand. Do not hide the primary answer behind disclosure, and do not expose every available field merely because it exists. Material missing measurements remain visible.

### Explain at the point of use

Use plain labels with clear units and populations. Give unfamiliar terms, counts and meaningful symbols concise native tooltips and accessible descriptions. Help & glossary supplies fuller definitions; it must not be required to decipher an ordinary row.

Brief help is a tooltip, not a new click-open panel with a Close button. Follow Apple's [help-button convention](https://developer.apple.com/design/human-interface-guidelines/buttons): use one standard SwiftUI [HelpLink](https://developer.apple.com/documentation/swiftui/helplink) in the footer to open Help & glossary. Contextual information-circle buttons open relevant content; never use a help or information control symbol as an inert tooltip target. Put brief native tooltips on the relevant label or control, using [Apple's tooltip guidance](https://developer.apple.com/design/human-interface-guidelines/offering-help); longer definitions belong in the glossary or a labelled disclosure.

Status badges within buttons and uncertainty symbols describe state, not independent actions.

### Choose a visual form that answers the question

Details must add information beyond the row; do not repeat its chart at a larger size or retain extra measurements solely to populate a chart. Use charts for history and patterns, aligned tables for comparisons, and familiar SF Symbols for compact cues. Use spacing, typography, contrast and restrained color to make importance and grouping apparent. Prefer readable values and meaningful graphics over diagnostic sentences or raw field dumps; visual polish is part of correctness.

### Make the next step clear

Warnings explain the user-visible effect and offer a relevant route when one exists. Symbols and actions stay beside their subject.

Adding a shortcut or another access path must preserve existing visible controls unless their replacement or removal was explicitly requested. Before changing a control cluster, list its accepted entry points; after the change, compare the complete rendered cluster against that list, not just the new or repaired control. Treat successive requests as cumulative unless the user explicitly supersedes an earlier requirement.

Avoid technical shorthand such as “same-user PIDs” or “interval averages” in persistent overview chrome when it does not help the user decide what to do.

### Review the user's experience, not the existence of code

Check the default view, expanded detail, narrow layout, light/dark appearance and missing-data cases. Ask what attracts attention first, what can be removed, whether the important answer is apparent without Help, and whether secondary information is explained and reachable. Verify actual hover/click behavior separately; a `.help` modifier or passing render test is not proof of responsive live help.

## Cross-interface issue review

A screenshot identifies where a defect was noticed, not its product scope. Before closing any report:

1. Check Mac, TUI, text CLI and JSON. Record each as affected, unaffected or not applicable, naming the shared model, renderer or input path that settles the classification.
2. Compare behavior and meaning: current membership versus process existence, exact identities and paths, counts and totals, missing versus zero, filters, history range and action availability. Matching strings alone is insufficient.
3. Preserve machine-readable fields and units when shortening human-facing wording. Give native hover, focus, resizing and SF Symbols terminal equivalents only where the same task exists; do not add terminal hover or JSON markup.
4. Run focused guards for affected outputs. If earlier fixes in the session missed this review, include them now. Put unresolved counterparts in PLAN; a Mac-only fix does not establish product-wide completion.

## Shared information and diagnostics

- Keep the main agent/session/CWD/executable comparison visually dominant. Move detailed collection diagnostics and explanations into a clearly named on-demand view; retain a concise, actionable indication of material missing measurements beside affected totals.
- Give every metric a clear population, unit and time range. A process-count column must say that it counts processes; “Now” alone is insufficient. Distinguish latest-sample presence from recent history and confirmed termination, and do not present overlapping counts as additive categories. Tooltips supplement labels rather than repair their meaning.
- Define separate behavior for selection, expanding children, inspecting details and actions. Put a control beside its target or give a clearly labeled selected-item inspector. Column-header help describes the column, never a hidden selected-row target. Keep executable and directory distinctions readable when narrow; do not rely on color or hover to establish ownership.

The [ledger decision](../architecture.md#constrained-overview-presentation) adds explicit acceptance checks: compare at least five current/recent sessions under arrivals and departures; verify a hardware-derived fixed ceiling and explicit manual override, inspect actual above-range interval values, preserve the chosen range and sort direction across new collections/scopes, equal pixel widths for unequal-duration intervals, missing versus zero and unchanged totals after paused pin/sort; keep workload context full-width and metric columns aligned at every depth.

Check complete selected row blocks and visible coverage at 40×8, three-row lanes at 90×30, and bottom-pane scrolling/focus after resizing.

On Mac, render Compact with details and warnings, verify full path wrapping and explicit metric accessibility labels, and dispatch both sort directions through the actual buttons. Render the last inner child followed by the next root, checking branch connectors, stronger inset and root separation rather than just row depths. Verify counted headings across disclosure, pinned duplicates and missing placeholders. Retention tests must continue to establish that opening/closing details does not replace the native outline.

## Mac interaction review

### Action coverage

Before accepting a change, inventory the visible actions and map each to a user task, interaction and evidence. Exercise each claimed pointer target through the production view, not just its state helper: row body, disclosure triangle, information button, each sortable header in both directions, and the matching menu action. Native selection tests do not establish row-click activation. If a synthetic event cannot reach a target, report that evidence limit and keep the physical check open; do not replace it with a screenshot claim.

### Sorting, selection and disclosure

A sortable table must expose standard header sort indicators and use the same ordering state as its menu. Check Contributor, CPU and Memory in both directions, children as well as roots, refresh, pins, selection and explicit disclosure.

Section headings must be separate nonselectable headers, never labels inside a contributor’s selectable cell. Check Pinned, Sessions and Other observed work with adjacent rows selected, and native up/down navigation across section boundaries.

Clicking a row body selects only; the process-count/chevron and native disclosure controls toggle children. Verify count tooltips explain currently observed processes. Keyboard selection stays independent, and pin, action-menu and information controls must not toggle children.

### Current and historical rows

Verify historical rows are visibly distinct in selected and unselected states in both appearances, with readable paths, current/past counts whose tooltips explain their populations and evidence limits, and no empty action menu.

Do not mark a current group as historical merely because it contains earlier workers; use separate current and past counts. Do not reuse the Help question mark or a Time Machine-like clock for lifecycle status. Paths must truncate independently of status; unavailable presence must not look like confirmed departure.

### Exact action targets

Audit every command menu/button against the actual native key router, including unselected rows, multi-process submenus and a different inspected process. Show a shortcut only when its command is available for that exact target now. Otherwise omit it from the label and tooltip; never append selection/inspection prerequisites. Commands with no native binding must not borrow a TUI key. Check k/f against the selected current contributor, menu shortcut hints and frozen multi-target termination review with fake services; no live signals are required.

### View and menu state

Exercise every View choice twice and reopen the menu: exactly one choice must be checked and selecting it again must be idempotent. Sort commands must preserve the current table, selection, disclosure and inspector; verify Stable across changing values and arrivals, Reverse in both views, and a stale PID menu action after returning to the overview. Check menu state before the first snapshot as well as after data arrives.

### Help, shortcuts and action routes

Inventory repeated routes before adding another action: coverage is a badge on the footer Diagnostics control with a plain-language tooltip and technical details inside Diagnostics, the footer also provides compact Help, and the options menu provides labelled Help, Keyboard Shortcuts and Diagnostics entries. Keyboard shortcuts must be directly reachable without expanding a glossary section.

Give every visible button and meaningful symbol a concise, task-specific tooltip and accessible name. Put help on the actual hover target, with a comfortable rectangular area for small status symbols; avoid ancestor-level help that overlaps child controls. Preserve shortcuts only for commands available on that exact target.

Prefer familiar SF Symbols for compact controls; retain menu text and labels for ambiguous/destructive decisions. Apple’s [button guidance](https://developer.apple.com/design/human-interface-guidelines/buttons) recommends text when it communicates more clearly; “avoid all text” is not the rule.

### Summary groups

Distinguish synthetic summary groups from real sessions with category symbols and an accessible summary-group label; do not depend on color alone. Check recent, remainder, uncertain, shared and released-detail groups alongside real sessions, including a selected synthetic group. Keep full group names and resource totals visible. Each special group and the Other observed work heading needs an adjacent information button that opens its definition in the existing glossary. Verify the exact destination, concise action tooltip and focus return; do not add a separate tooltip-like popover. Explain that Recent contributors is a grouping decision, not a process-exit state.

### Native hierarchy

Apply Apple's [outline-view guidance](https://developer.apple.com/design/human-interface-guidelines/outline-views), [disclosure guidance](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls) and [focus guidance](https://developer.apple.com/design/human-interface-guidelines/focus). Prefer standard SwiftUI content controls; AppKit lifecycle ownership remains unchanged. Use first-column hierarchy, aligned metric columns, recognizable disclosure affordances only on expandable rows, and subtle row separation that remains distinct from selection.

### Whole-table folding

In Mac, verify native section headers remain nonselectable and the table instance survives whole-table folding.

Test attached intrinsic sizing and detached top-edge preservation: collapse at a custom height, change a visible notice, reopen, and verify the original height, selection and child disclosure return.

Exercise both 8 and the top disclosure: collapse/expand should animate briefly without bounce, including a quick second toggle, while Reduce Motion and resize-grip dragging remain immediate.

Check physical pacing separately from offscreen native-animation requests; NSPopover treats animation as a platform-controlled hint. Confirm the aggregate lane includes filtered/hidden work once and changes neither retention nor measurement totals.

### Panel resizing

Verify height resizing through the visible bottom grip while attached and detached, at minimum/screen limits and with Details open. Programmatic NSWindow resizing does not prove native edge hit-testing. Verify cursor, tooltip, accessibility adjustment, retained table identity and close/reopen height.

### Keyboard focus and shortcuts

Verify **?** from a selected row opens shortcuts applicable to that view and target, omits unavailable actions, and returns focus to the same selection with Esc. Keep glossary access separate from the shortcut guide; terminal help must remain scrollable and readable at 40×8.

Exercise report shortcuts with focus on the table, whole-table disclosure button, options picker and row controls. Verify `8`, section folding, pause, sorting and `?` without first refocusing the table; keep arrows, Space and Return with their native control. Test the native window's key-equivalent path, not only model dispatch. Editable text, reference pages and action panels must not trigger background report commands; process actions still require the correct visible target. Check repeated pin/unpin focus after rows move and Escape closing Details after focus moves to the toolbar.

Review pointer and keyboard paths independently: select a row, expand/collapse, inspect that row, close inspection and return to the same identity.

Controls need discoverable labels, reasonable hit targets and accessibility names/values. Retain useful keyboard navigation; do not make static totals or diagnostic paragraphs selectable just to capture keystrokes, or hide all focus indicators to mask an incorrect focus target.

### Refresh and rendered hierarchy

Check refresh, pause, missing/reordered rows and returning from inspection for focus theft or retargeting. Inspect light/dark offscreen renders at supported sizes, including long paths and multiple hierarchy levels.

### Section surfaces and tree guides

Also render tables over a colored backdrop: verify opaque soft-gray/charcoal section surfaces suppress desktop colors in light and dark modes, thin rounded outlines enclose both headings and rows, collapsed sections retain bordered title strips, expansion/collapse and arriving rows move following panel borders together with their headings and contents without clipping, gaps and unused viewport expose the surround without filler stripes, no bright row separators or doubled native/custom fills, and one visual group for each session and its children.

Check row boundaries as well as interiors: subtree fills must not expose light padding strips or per-row rounded notches, and tree guides must connect across sibling/deeper rows in both appearances.

Root and child disclosure chevrons must share the headline/tree-elbow height, including after layout and disclosure; exercise the native button action in addition to checking its frame.

Sample real row interiors to check visible alternation, and the empty viewport below the final row to catch native filler stripes. Repeat the empty-area check after expansion, collapse and height changes; margin pixels alone cannot validate row or filler backgrounds.

### Readable inspection values

In inspection, use long paths, executable names and session IDs whose final components must remain visible; test inherited single-line row environments, wrapping and selectable full values.

Plain text actions need a visible non-color cue such as an underline or a button border. VoiceOver order, physical pointer/keyboard delivery and live popover behavior remain the user's [native smoke checks](native-app.md#manual-macos-smoke-test).

## TUI interaction review

### Section folding

For terminal section folding, verify P/S/O through the owned PTY fixture; 5/6/7/8 must not fold the TUI. Keep native 5/6/7/8 coverage in the shared state and native host checks. Check complete selected rows at 40×8, section controls and aggregate alignment at 90×30 or wider, and reopening after refresh.

### Terminal conventions

Follow the [TUI contract](../architecture.md#tui-contract) and [no-fork decision](../decisions/swifttui-fork.md). Use terminal-native selection, tree markers and keyboard commands; do not copy Mac hover interactions or graphical popovers. Keep the current selection, available detail/Back commands and shortcut meanings discoverable in the supported viewport.

### Table geometry and hierarchy

Check cell widths, long/Unicode labels, narrow/wide layouts, scrolling and pagination. Moving down must not hide earlier contributors while the whole table fits, with or without Details. Expansion must use remaining rows for the following contributor rather than requiring its whole context block to fit; keep the selected block complete and signal clipped content.

Check sibling junctions and final-child elbows, ancestor trunks through nested multiline rows, and termination before the next root.

### Color and population labels

Verify normal-contrast paths/counts, blue identities/history, cyan values that follow the active sort column, direction arrows, borderless plots and reverse-video selected headline/CPU/memory cells with unhighlighted charts; unselected context must remain readable in both terminal themes. Check the monochrome view, single population labels and singular counts too.

The Unresolved / uncertain heading and native question-mark folder must not reuse the warning color of above-range chart bars. Executable headings must not append ×N; current counts and historical populations remain separate.

### Historical-row filter

Exercise Shift+H twice through the PTY, check its Help entry and active-filter reminder, and verify hiding historical rows preserves totals and history.

### Context wrapping

At 99 columns context can extend below charts; at 100 and above it must stop before them. Check spacer lines between siblings without breaking tree guides, and omit extra spacing in compact-height terminals. Keep hierarchy in the label column and numbers aligned; distinguish selection from expansion and preserve meaningful state without color.

Detailed diagnostics belong behind an explicit command without hiding material coverage warnings.

### Focus and inspection

Exercise focus routing, disclosure, inspection/return, pause, refresh and row disappearance using the synthetic PTY fixture. In the contributor tree, Return and `i` must inspect in place; repeated Return preserves the open pane, selection and expanded branches. Only the explicit view switch changes tables.

Check field colors in overview, grouped/flat process tables and both Details panes through final clipping, wrapping and scroll offsets; previewing the overview alone is insufficient.

Ensure navigation keys reach the active pane and editors do not trigger table shortcuts. Source/model checks do not establish terminal key delivery on the user's keyboard; retain the [manual workflow check](native-app.md#manual-tui-workflow-check).

### Navigation and paging

Compare headers, sort direction and core shortcut wording across contributors, grouped processes and flat processes. Keep `v`, `g`, Help and quit discoverable.

Exercise u/d, Ctrl-U/Ctrl-D, Space and encoded Shift-Space in the PTY for half-page navigation, Page Up/Down for full pages, table selection visibility and Details focus; retain the physical modified-key check for terminals that send identical Space bytes.

### Scrollbar and pane sizing

Verify visible-range indicators, the table scrollbar and bottom-aligned footer at narrow/wide sizes with both short and overflowing Details.

Check rail/thumb position at top, middle and bottom, proportional size with mixed-height rows, disappearance when all content fits, selection visibility after paging/arrows/resize and stable anchors when rows arrive or disappear.

Tab must route paging between rows and Details in both table modes without changing disclosure or totals. Exercise -/+ and M/= in both contributor and process Details and check the pane geometry changes.

### Keyboard Help

Check styled key spans through Keyboard Help wrapping/clipping, including monochrome output; headings alone are insufficient.

At 100/120/160 columns, verify balanced two-column Keyboard Help preserves every key and whole sections, with a four-cell gutter; check single-column fallback, paging and offset clamping after resize.

### Monochrome output

Verify actual PTY bytes preserve reverse-video selection, bold and underlined Help keys under both NO_COLOR and --no-color while emitting no foreground/background color attributes.

Review monochrome overview/process tables, Details, reference pages, chart glyphs and explicit warning text; use solid cell fills and footer rules so color is never the sole boundary cue.

### Summary and footer layout

Keep shortcut hints neutral in report, Details, diagnosis and reference-page footers, and in glossary content.

Verify the three-line contributor summary and inline section shortcuts, including when every section is folded. Footer hints use at most three rows; report, reference and diagnosis footers separate them with a rule plus at most two hint lines, including narrow and monochrome layouts.

### Three-row charts

Verify the overall CPU chart spans summary rows zero through two without adding header height, shares the contributor chart column and retains the scroll indicator outside its lane.

With stacked mode selected, render contributor charts as exactly three text rows, with full-cell fill and no fourth plot row and check missing, zero and above-range glyphs against the Help/glossary legend; verify fractional caps in every row and full-cell backgrounds strictly below them.

Check displayed height against known values (150% on a three-row 0–400% chart is 1⅛ rows), not only unchanged CPU values or allowed glyphs.

Review color/monochrome output and the accepted Menlo, Source Code Pro, Monaco and Vera Mono font appearances; offscreen font geometry is not a substitute for live terminal rasterization.

### Compact chart mode

In compact mode, verify eight proportional glyph steps with no background fill even at the maximum, matching range/sample values in the overall and every contributor chart, a visible compact caption and truthful Help.

Exercise compact output in color/NO_COLOR through the PTY; check Apple font resolution with fake permission/query functions, including missing, denied, failed, malformed and multiplexed cases.

Automatic lookup must never use the frontmost tab or default profile.

User-owned Apple Terminal smoke checks cover actual font lookup, Meslo Powerline at 12 pt, custom spacing and explicit overrides.

### Aligned resource totals

Check CPU/Memory summary emphasis for both metric sorts and neutral Stable/contributor sorting.

Cadence text must match the subdued footer hints without dimming chart glyphs or aligned totals. Check that wide TUI headings, totals and row values share column boundaries, Recent CPU remains visible and narrow/short terminals retain the inline summary.

In Mac, inspect the total/row alignment and keep sorting and totals available when the table is collapsed.

### Range overflow and legend

Exercise over-range samples in compact/stacked and color/NO_COLOR modes: color uses warning-colored blocks, monochrome retains ↑, and numeric values remain unclamped.

A color PTY fixture must remove NO_COLOR, not set it to an empty string: SwiftTUI detects the key’s presence.

Verify the bottom-right chart legend appears only with visible contributor charts and room beside every footer line; hide it entirely when constrained, without losing shortcuts or adding footer rows.

## Evidence and maintenance

Use offscreen native renders at compact widths and narrow/wide terminal layouts. Verify text/value legibility, truncation priorities, structured disclosure, contextual action safety and meaning without color. Height limits alone are not a UX oracle. Tooltips briefly explain a metric or action; full paths/arguments belong in selectable Details, and they must not be the only way to learn which agent/session is responsible. Human-readable names require verified source evidence and a provider/ID fallback. Physical macOS interaction remains the user-owned smoke test. Track the review in [UX-01](../../PLAN.md#resource-accounting-priority).

Report demonstrated defects, recommended changes with rationale, checked evidence and pending physical checks separately. For code changes, use red/green behavior guards and inspect relevant rendered output; do not call a UX correction complete merely because code compiles or text fits. Maintain accepted semantics in [architecture](../architecture.md), controls in [usage](../usage.md), this review procedure for reusable checks, and [PLAN](../../PLAN.md) for unfinished acceptance. Improve the skill/procedure when feedback demonstrates a missing decision rule; do not append bug histories or duplicate the feature specification.

Do not generate saturation, burners or churn as part of a routine UX review. The user stopped the 2026-10-25 stress workload; repeating artificial load requires fresh explicit authorization. Data retention for probes follows the user's scope and [artifact policy](workflow.md#build-and-probe-artifact-retention), not the product recorder setting.

# Project plan

## Resume point

Finish the [product goal](docs/product.md): identify agent → session → CWD → executable → CPU/memory in Mac and TUI, with particular attention to short workers during inspection. Shipping acceptance remains open. Keep only unfinished work, next actions and pending decisions here; remove completed entries once their durable outcome is documented. [Architecture](docs/architecture.md) owns implemented contracts, [development](docs/development.md) owns validation procedures, and [research](docs/research/README.md) owns dated evidence.

## Open follow-ups

### Mac app icon release correction

- [ ] Revise the rejected application-icon candidate using the [Apple guidance findings](docs/research/native-menu-design.md#application-icon-release-review--2026-11-01). Show small-size and appearance previews and obtain the user's requested design approval before publication.
- [ ] Verify Icon Composer integration with the custom bundle build, package the approved icon and add missing/invalid-icon regression guards to bundle and archive validation. The current failing packaging regression establishes the missing declaration; it does not settle the final icon format.
- [ ] Release the correction as 0.4.1, update the Homebrew cask and verify the installed bundle under the [Mac release checks](docs/macos-release.md#required-app-icon-review). Preserve published 0.4.0 assets. Live Finder/appearance acceptance remains user-owned.

### Resource accounting priority

#### CPU-01 — Accounting acceptance

- [ ] **Close coverage, sustained-load performance and memory acceptance.** The first [accounting delivery](docs/proposals/resource-accounting.md) is authorized. Preserve measured CPU, exact lifetimes, frozen attribution and explicit unknown/missing work. Keep default acquisition at 100 ms and do not exclude processes or change totals through display filters; explicitly selected [adaptive acquisition](docs/architecture.md#adaptive-acquisition) may relax within its configured bounds. ADAPT-01 below owns its remaining acceptance gates.

##### Short-worker coverage

**Next action:** Choose a bounded improvement to the implemented sampler using authorized workload observations and the [recording and analysis playbook](Tools/WorkloadCapture/README.md).

**Evidence and limits:** The user accepted making the most of the existing implementation while alternatives remain unresolved; this does not establish complete accounting. Never-observed workers and final exit CPU remain missing. The [root/private tracing path is rejected](docs/decisions/privileged-resource-tracing.md), and [Activity Monitor inspection](docs/research/cpu-accounting.md#activity-monitor-data-path--2026-10-26) supplies no supported replacement. The 10/50 ms fixture does not establish real-build loss rates.

##### Sustained cost/cadence

**Next action:** Revalidate after acquisition changes; complete native-app acceptance separately.

**Evidence and limits:** The ordinary-launch optimized collector at `e6fd992` passed both targets under naturally busy load on 2026-10-26; see the [acceptance scope](docs/research/menu-bar-load-cost.md#ordinary-launch-acceptance-scope--2026-10-26). No profile data retained. This does not establish continuous saturation or closed-panel Mac behavior. Preserve the ≥10-minute, provider/helper-inclusive protocol and per-window gap/overrun disclosure.

##### Memory

**Next action:** Validate a transient-peak analysis method after the [synthetic allocation export check](docs/research/menu-bar-load-cost.md#synthetic-allocation-export-feasibility--2026-10-29), then extend the [simultaneous ownership fixture](docs/development.md#simultaneous-ownership-checks) to internal merge/compaction transients and native allocations before selecting broader admission bounds. The two authorized recordings are complete; do not repeat them unchanged. Resolve input buffering without a fork.

**Evidence and limits:** Logical per-stage caps and the scoped fixture are not a process-wide heap ceiling. The [source classification](docs/research/menu-bar-load-cost.md#population-and-scratch-ownership-follow-up--2026-10-26) identifies remaining unreserved holders.

The fixture covers accepted rollback, incoming and merged report values before admission; internal merge/compaction transient peaks, full acquisition/bridge scheduling, native buffers and framework UI allocations remain outside it; TUI-INPUT-01 still permits cumulative input backlog.

Command-array sharing requires explicit ownership before charge discounts.

##### Publication pressure

**Next action:** Verify realistic bridge delays and publisher stalls while preserving history/report pairing.

**Evidence and limits:** Deterministic conservation/collapse guards do not establish native cadence or heap cost.

##### Native acceptance

**Next action:** Complete MENUBAR-01/03 and UX-01.

**Evidence and limits:** CLI profiles do not establish closed-panel App Nap, native cost or physical interaction.

The completed short-worker fixture confirms substantial loss despite timely polling within that synthetic workload; it does not establish a real-build lifetime distribution or a 50% loss rate for the user’s Java/Node builds. [Coalition research](docs/research/cpu-accounting.md#ordinary-app-launch-and-coalition-isolation--2026-10-26) provides no unseen-session attribution; further coalition trials are not the recommended next step.

Inspection-focused discovery is implemented experimentally and default-off, with a local 50 ms-worker coverage benefit but substantial remaining loss and an unmet short-trial cost target. General transparent coverage remains required, and older summaries must disclose incomplete measurements.

#### UX-01 — Responsibility workflow

- [ ] **Validate the responsibility workflow in both interfaces.** Use the [review procedure](docs/development.md#resource-overview-ux-review) for overview and process inspection separately. Continue from the [user-confirmed selection/disclosure and Details/return checks](docs/research/native-menu-design.md#physical-workflow-and-surface-feedback--2026-10-30); broader pointer/keyboard, VoiceOver and live menu anchoring remain pending.

##### Responsibility and layout scenarios

- Compare multiple contributors and CWDs, departed workers, memory-heavy idle work and uncertain ownership. Check nested sorting and contextual actions.
- Validate the accepted [ledger and lanes](docs/architecture.md#constrained-overview-presentation) with at least five arriving/departing sessions and both bottom inspectors. Cover the 620-point Mac panel, Compact-height details and TUI resizing at 40×8 and 90×30.
- Check full paths, counted headings, hardware-derived and manually selected chart bounds, overall CPU-chart alignment and separation between a final inner child and the next root. Verify complete selected headlines, connected multiline branches and readable paths in light, dark and monochrome terminals.

##### Selection, disclosure and keyboard routing

- Test the retained SwiftUI table’s active-window selection/focus, hidden input and VoiceOver exclusion, diagnosis/action/process-view returns, and row-body activation separately from triangle/information activation.
- Check both header-sort directions and menu agreement, header/content separation while scrolling, nonselectable section titles and navigation across sections. Distinguish synthetic groups through symbols, labels and tooltips.
- Open **?** shortcut help from selected rows and return focus with Esc. Exercise report shortcuts from disclosure/toolbar focus, with text-entry and action-panel isolation, plus Help/Keyboard Shortcuts/Diagnostics return paths.
- Fold and reopen sections and the whole table while preserving selection and children. Check content-sized whole-table collapse and restored custom height in attached/detached windows, including brief animation from 8/top disclosure, quick repeats and Reduce Motion.

##### Surfaces, details and actions

- Review bordered neutral section panels, continuous subtree fills, connected ancestor guides and headline-aligned chevrons. Verify synchronized movement during expansion/collapse and arriving rows, including Reduce Motion; the user confirmed the 2026-10-31 motion correction.
- Check the system inspector background, fixed-width stacked current/past counts and their help, Diagnostics warning-badge hover/click, standard footer Help, and special-group information buttons with contextual glossary destinations.
- Exercise Copy all in contributor/process Details, including collapsed evidence and loaded arguments. Review concise tooltips, explained counts and deeper evidence that starts collapsed.
- Check hover/focus pin reveal, process-count tooltips, count-button disclosure, native contributor process inspection/actions and attached/detached bottom-grip resizing against the local studies in `.build/design-studies/`.

#### ADAPT-01 — Adaptive sampling acceptance

- [ ] **Calibrate adaptive defaults and close coverage/native acceptance.** The default-off [production mechanism and Mac/TUI controls](docs/architecture.md#adaptive-acquisition) are implemented. Calibrate actual low-activity agent CPU/churn before proposing slower defaults.

Required evidence and authorization:

- Obtain user acceptance of separate numeric identity/CPU loss budgets for each duration, scenario and visibility context, compared with fixed 100 ms and fixed context maxima, plus measured savings.
- Preserve the [offline findings](docs/research/cpu-accounting.md#adaptive-sampling-offline-prototype--2026-10-27): they establish modeled savings and phase-sensitive losses, not native cost or actual idle-agent distributions.
- Complete user-run native controls/lifecycle checks and separately authorized cost/cadence/App Nap measurements. Persistent-unreadability relaxation remains unadopted.
- Do not treat aggregate summaries as a replay of temporal evidence. Raw recordings are unavailable; any live diagnostic needs a separate explicit request.

#### XUI-01 — Cross-interface audit

- [ ] **Audit this session’s fixes across Mac, TUI, text and JSON.** Finish the remaining interaction checks without adding unrelated controls. The user’s 2026-10-31 request makes this a standing review rule, not Mac-only acceptance.

The audit covers lifecycle/filter/count semantics, identity/path truncation, details/history, action and shortcut availability, Help/Diagnostics and native-only styling/interaction. Preserve these findings from the current pass:

| Area | Established scope |
| --- | --- |
| Details history | Duplicate interval inspection was removed from Mac and TUI Details; text/JSON have no equivalent chart inspection. |
| Historical-row filter | Mac options and TUI Shift+H use a shared row-membership predicate that preserves totals and wire output. |
| Copy all | Native Details uses existing data; TUI has no clipboard command. |
| Shortcut focus | The 2026-10-31 native fix has no TUI equivalent: the host already dispatches report commands independently of pane focus. Text/JSON have no focused controls. |
| Charts and folding | The TUI history caption is concise; the overall CPU chart and section/table folding use shared data and visibility state. |

### Existing validation follow-ups

- [ ] **CLI-HELP-01 — Correct the process-disclosure description in `--group` help.** Generated help still says left/right opens process details; the current TUI contract uses arrows for session children and `i`/Enter for Details. The README rewrite uses the current controls. Correct the separate option-help text with a generated-help regression.

- [ ] **TUI-CHART-01 — Validate the accepted Meslo compact fallback physically.** The user accepted a single-row filled fallback for Apple Terminal with Meslo Powerline; the overall and every contributor chart now share the selected mode and CPU range. Auto uses existing-permission font lookup and falls back on Meslo or unavailable/unrecognized font; explicit `--tui-chart-style compact|stacked` overrides it.

Confirm the actual Meslo LG L DZ Regular for Powerline 12 pt output in color/monochrome, lookup behavior with/without existing Automation authorization, custom spacing and accepted stacked-font appearances. The [retained findings](docs/research/terminal-ui.md#font-detection-and-compact-fallback--2026-11-01) distinguish offscreen glyph geometry from live rasterization.

Do not claim three-row Meslo seams were fixed: compact mode avoids cross-row joins and reduces resolution to eight steps. No terminal settings or fonts may be changed automatically.

- [ ] **MAC-TABLE-01 — Diagnose the native table reentrancy warning.** Synthetic selection/render checks on 2026-10-30 pass but emit an NSTableView delegate reentrant-operation warning that macOS says will become an assertion. Isolate the triggering callback and distinguish test scheduling from production reconciliation before changing the bridge; see the [section-header validation](docs/research/native-menu-design.md#nonselectable-section-headings--2026-10-30).

- [ ] **TUI-INPUT-01 — Bound ordered input end to end.** The [proposal](docs/proposals/bounded-terminal-input.md) is on hold for an official upstream fix or verified supported-public-API solution. The [0.19.1 source review](docs/research/terminal-ui.md#upstream-0191-comparison--2026-10-29) found no supported end-to-end admission path. Reader/parser/runtime queues remain open; discarding paste after the reader does not bound its upstream storage. The [no-fork decision](docs/decisions/swifttui-fork.md) prohibits forks, vendored changes and checkout patches.
- [ ] **TUI-UPSTREAM-01 — Prepare GitHub issue drafts later.** Deferred at the user's request. Preserve the two candidate reports and reproduction requirements in the [dedicated follow-up](docs/swifttui-upstream-follow-up.md). Do not prepare/file issues or contact maintainers now.
- [ ] **MENUBAR-01 — Complete the user-run native smoke and energy checks.** Follow the [manual checklist](docs/development.md#manual-macos-smoke-test), including responsibility labels, five-second display, recent workers, coverage, live/static close/reopen, focus and menus. Measure closed-panel cost and inspect App Nap separately. Physical checks remain pending until the user reports them; Computer Use stays disabled.
- [ ] **MENUBAR-03 — Complete targeted accessibility and interaction checks.** Use the [targeted follow-ups](docs/development.md#manual-macos-smoke-test) for diagnosis, detachment, contextual controls and VoiceOver. These are not routine prerequisites for every code edit.
- [ ] **ACTIONS-03 — Complete terminal-focus variants.** Test background/minimized windows, Spaces/full screen, shared-terminal cases and first Automation consent using the [disposable-target checklist](docs/development.md#manual-terminal-focus-check).

### Structural simplification candidates — 2026-11-01

A whole-codebase quality review found these shared semantics re-derived in renderers. Each needs its own scope decision; none is authorized, and each must preserve Mac and TUI behavior.

- [ ] **REFACTOR-01 — One contributor presence model.** Presence/retention wording and counts are rebuilt in `ContributorInspection`, `ContributorLayout`, the `ContributorOverview` hide filter and `MenuBarContributorCounts`, with two count formulas (`processes − current − membershipChanged` versus `workers − present`). Candidate: a Presentation `ContributorPresence` with counts, labels and filter membership that both hosts switch on.
- [ ] **REFACTOR-02 — Mac overlay state in `LiveReportState`.** Mac keeps `MenuBarReferencePage` (a copy of `ReportReferencePage`) and never mirrors diagnosis into `report`, unlike TUI, so Presentation's diagnosis guards do not apply on Mac and the host repeats its own guard (`isReportUnobstructed`). Candidate: mirror diagnosis, bind the popover to `report.referencePage` and expose one input-acceptance property.
- [ ] **REFACTOR-03 — Overview action targeting in Presentation.** Mac decides k/f overview targets and shortcut availability in three places (`MenuBarKeyboard`, `MenuBarKeyboardShortcuts`, `MenuBarContributorActions`); `LiveReportState.beginAction` rejects all overview actions. Candidate: shared target resolution and available-command queries; wiring TUI overview actions would be a separate product decision.
- [ ] **REFACTOR-04 — One active sort/details model.** `showsOverview ? overview.order : sortKey` and the matching details branches recur in TUI chrome, reference layout and Mac options, keyed on two different predicates (`showsOverview`, `view.isOverview`). Candidate: `activeSort`/`activeDetails` accessors on `LiveReportState`.
- [ ] **REFACTOR-05 — Semantic chart lanes.** `ContributorActivity` returns glyph strings that `ContributorLayout` re-parses (`glyph == "█"`) to recover fill style, and the Mac lane recomputes sample selection separately. Candidate: per-span normalized bars that each renderer quantizes; compact becomes one row. This area changed in five of the last fifteen commits before the review.
- [ ] **REFACTOR-06 — One owner label.** `MenuBarProcessLabel` composes its own owner wording ("Shared runtime", "Uncertain session", "Unresolved session") beside `SessionGroup.sessionDescription`. Candidate: one Presentation owner-label function using `SessionCorroboration.isExactSession`.

### Deferred features

- [ ] **GPU-01 — Close admission, metric and coverage gaps for observed GPU accounting.** Use the [offline model](docs/research/gpu-accounting.md#bounded-anonymous-matching-has-a-conditional-lower-bound--2026-10-29) and [native lifecycle evidence](docs/research/gpu-accounting.md#record-lifecycle-and-aligned-timing-calibration--2026-10-29) to define a supported history/ownership contract beyond the exercised zero-born, retirement and replacement paths.

Resolve imported/reappearing history and reset treatment, independent unit/charging evidence, and transparent attribution to already-running processes.

Assess uncoordinated queue lifetimes, material loss budgets and sustained cost with a suitably narrow collector; the held-queue diagnostic is not that acceptance test and should not be repeated unchanged.

Mutable timestamps are not record IDs, and the measured self-task GPU field is unhelpful. Interface policy and graphics-memory scope remain separate decisions.

The [proposal](docs/proposals/gpu-resource-visibility.md) remains unapproved for production collection and Mac/TUI support; host activity cannot substitute for contributor accountability.

- [ ] **PROBE-01 — Review container totals after CPU-01 acceptance.** [Proposal only](docs/proposals/container-resource-probes.md); implementation needs separate approval. Keep host and guest totals separate, strip environment variables except allowlisted markers, and exclude exec/attach and guest-process inspection.
- [ ] **CAPTURE-01 — Review bounded diagnostic recording after CPU-01.** [Recording remains unapproved](docs/proposals/diagnostic-recording.md). Validate framing, writer ownership, cutoffs, attribution and memory/storage bounds before measuring serialization costs. Default-off means no recorder files, queues or cumulative history; normal monitoring retains bounded rolling memory only.

## Scope and pending decisions

### Temporary feedback intake — 2026-10-17

- [ ] **FEEDBACK-13 — Verify physical German-keyboard scrolling.** Check u/d, Ctrl-U/Ctrl-D, retained Space, Page Up/Down and bracket aliases on the user’s keyboard. Apple Terminal may send Shift-Space as ordinary Space; encoded support does not establish physical delivery.

Verify the proportional TUI table scrollbar and visible u/d movement with expanded rows.

Check the following in the user's font and theme:

- Styled Keyboard Help and neutral view controls.
- Stacked three-row filled charts, with fractional caps and solid interiors, and the accepted single-row compact fallback in color/monochrome.
- Accepted Menlo, Source Code Pro, Monaco and Vera Mono appearances.
- -/+ contributor Details sizing.

Use the [TUI workflow check](docs/development.md#manual-tui-workflow-check). The [dated triage](docs/research/terminal-ui.md#feedback-triage--2026-10-26) owns the other feedback dispositions; their source corrections do not replace UX-01’s physical workflow checks.

### Execution and authorization boundaries

- Keep default acquisition at 100 ms with adaptation off and closed-panel multiplier one; explicitly selected settings follow the [implemented adaptive contract](docs/architecture.md#adaptive-acquisition). Preserve one-second metadata freshness, identity checks and frozen labels. Slower target defaults require the acceptance in ADAPT-01; coverage priorities remain in force.
- Distinguish ordinary CLI/TUI, diagnostic launch-policy and native-app results; one diagnostic arm does not authorize host reclassification or a higher scheduling class.
- No new burners, artificial saturation or native churn trials. Earlier bounded short-worker and coalition authorizations were consumed; deterministic in-memory tests remain allowed. New observation mechanisms do not authorize privileged helpers, entitlement/security changes or native probes.
- Analyze new profiles and delete their data and temporary binaries. The earlier permitted aggregate tables may remain local but must not enter Git; no later profile-retention exception is authorized.
- Live messaging/signalling requires disposable authorized targets. Real Codex workload/recipient validation remains a [coverage gap](docs/development.md#validation-coverage), not permission to act on existing sessions.
- Preserve the [child-counter rejection](docs/decisions/exited-descendant-cpu.md), [Codex registry deferral](docs/decisions/codex-session-registry.md) and [menu-bar scope decisions](docs/decisions/menubar-product-scope.md). Interval-supported ownership, historical session-memory peaks and tracing are not approved implementations.

### Existing scope decisions

A sortable provider column/provider filter, author credit in `--help` and alternative diagnosis bindings remain separate ideas. The user authorized signed/notarized Mac app releases, the separate `agent-monitor-app` Homebrew cask and correction of the missing application icon on 2026-11-01 under the [Mac release workflow](docs/macos-release.md). Other distribution channels, new platforms/providers, background services, notifications, external plugins and broader terminal/container attribution require separate scope decisions; the [working-model proposal](docs/proposals/agent-working-model.md) is not adopted. Current capabilities belong in [architecture](docs/architecture.md), not a completed-feature log here.

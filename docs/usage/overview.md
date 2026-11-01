# Understand contributors and measurements

Use this guide to interpret the same contributor totals, history and coverage qualifications in the Mac app and terminal interface.

[Usage guide](../usage.md) · [All usage topics](README.md)

## Reading responsibility and retaining data

The [product question](../product.md) is which agent/session and executable consume CPU or memory, with the workload CWD as context. The current overview expands sessions into executable groups and exact processes. CPU/memory ordering applies within those groups too. Full paths, available arguments and attribution evidence are inspection details.

Provider-listed names are unavailable in local-only operation; session labels use locally verified provider/session IDs, and missing identity remains explicit. Session headings lead with provider/session identity; compact CWD paths or directory counts are secondary context. Overview sessions and native process-group headings use a second compact line for workload context when needed.

In the overview, matching path suffixes gain enough leading components to distinguish observed workloads; inspect for the full path.

Standalone Mac process rows—including individually pinned processes and flattened one-process sessions—show provider, abbreviated session ID above the executable/CWD/resources. Unresolved or shared ownership stays explicit; “Changed” flags a last-observed label that does not describe all CPU in the window. Children with the same session use its visible header and retain a single resource line. A child belonging to a different thread inside a root group shows its own session identity.

Overview executable groups reserve space for their directory independently of the executable name; the TUI uses two linked lines when the fields cannot fit together.

The remaining acceptance work is tracked in [UX-01](../../PLAN.md#resource-accounting-priority).

### What is retained

Normal monitoring keeps bounded rolling data in memory, including the detailed recent window and scalar chart. It does not automatically write process-data logs or accumulate an unbounded history. Pause freezes a bounded view while collection continues. Diagnostic recording is a [separate, unimplemented proposal](../proposals/diagnostic-recording.md), off by default and requiring explicit opt-in. Selecting JSONL or saving an export explicitly is distinct from automatic capture.

## Main contributors and recent activity

Mac **Diagnostics** and TUI **D** hold detailed coverage metrics and explanations. A compact Diagnostics warning badge remains visible when observations are missing; it directs users to those details. At small sizes the TUI preserves the selected identity/resource block and quit/resume/help controls. `i` remains inspection of a contributor, separate from collection diagnostics.

### Find the main load

Mac and TUI default to **Main contributors**. Individually shown sessions are the union of the top five by combined group CPU (strictly above 25% of one core) and the top five by current memory (at least 100 MB). Hysteresis keeps small rank changes from constantly reshuffling the list. These relevance floors collapse rows; they do not remove measured work. A zero-CPU process can still matter through memory, and zero CPU does not mean it has stopped.

**Recent contributors** keeps bursts discoverable after workers disappear: sessions qualify through at least 0.5 recent candidate CPU-seconds, a 100 MB sampled worker footprint, or having recently left the main list.

**More processes** quantifies the remaining exact-session population. **Unresolved / uncertain** always remains visible; recognised shared agent runtimes have their own summary. **Show all** (TUI `a`) opens the recent/remainder sections. Explicit resource filters still apply to process rows, with filtered counts and full totals retained.

### Read activity lanes

CPU activity lanes share a visible fixed zero-to-ceiling display range; activity never changes it. They show whole measured time spans over the retained recent range, with gaps for unavailable CPU and a maximum-span caption when timing is coarse. TUI lanes use three text rows, or one row in compact mode; `~ spans` marks incomplete observations. Current CPU and memory stay aligned beside identity; executable/CWD summaries use the full width below. Memory is a current measurement, not a historical graph. Hover in the Mac app for definitions, or expand coverage/details when needed.

Expand root/session → thread where relevant → executable → process. `executable node` combines observed paths ending in `node`; it does not merge `node_repl` or guess from display names. Exact lifetimes prevent PID reuse from becoming the same worker. Session CPU is **point-evidence candidate CPU**, not proven ownership throughout an interval.

Earlier unresolved work stays unresolved after later evidence becomes available. Workers changing sessions can count in both historical memberships; parent distinct counts deduplicate them.

### Understand the recent window

**Recent** targets 60 seconds, within fixed record/text limits. It reports actual retained coverage, missing observations and older-opening recovered CPU separately. A retention-limit/gap qualifier clears once the affected boundary ages out of the target range.

Publication backlog can combine units without dropping measured CPU; a warning shows how many units were coalesced and the maximum unit span. Whole-unit retention can shorten the range, or widen it when the newest unit alone exceeds the target; the displayed duration is the actual range.

Memory maxima come from acquisition readings, even if a spike was gone by the next display refresh. Last kernel task peaks remain inspectable but can predate monitoring or reset on exec; they are not recent-window maxima.

**No longer observed** means absent from the latest identified scan, not confirmed exit or a monotonic stopped counter. Read failures and exits before read disclose distinct same-user-listed PID values and per-scan failure counts, not identified workers or verified agent ownership; released PID detail produces count ranges.

Older collapsed workers carry count ranges; verified birth timing can tighten those ranges without treating disappearance as confirmed exit. Retention cannot recover never-observed processes or their final exit CPU.

### Recognise embedded tools

Embedded tools recognised by an attribution adapter show their observed invocation name (for example, `ugrep`) even with `--commands` off. This is a label; the actual executable path remains in inspection. Other workers keep the observed executable basename.

### Counts and chart range

Overview headings include **Main contributors (X/Y)** or **All contributors (Y)**: X main/pinned retained session groups out of Y total retained groups. Shared, unresolved and released-detail work remain separate.

Hardware chooses the initial range once: performance plus super cores × 100%, falling back to all logical CPUs if core types are unavailable. This gives 400% for four performance cores; a reported two-super/four-performance configuration gives 600%. It does not identify core placement or computing-power saturation: 100% means one CPU-second per elapsed second.

Mac **View options → CPU chart range** or `b` cycles/selects a manual range, including all logical cores. Range and sort direction survive collection resets.

An orange cap or warning-colored terminal bar marks overflow; monochrome terminals use ↑. Numeric columns retain the measured values. Details explains retained CPU and coverage without repeating row charts or raw interval values. Equal-width bars are successive whole-interval averages, with unequal durations identified in Mac chart tooltips and the TUI caption. They show observation order, not equal elapsed-time slices.

### Inspect without losing context

In TUI, **?** opens contextual **Keyboard shortcuts**, **G** opens the glossary, and **D** opens Diagnostics. These are scrollable terminal pages; **Esc** returns to the same selection and pause state.

In TUI, arrows select/fold and `.` pins the owning session. Folding only reveals children; `i` opens a labelled field/value inspection for the selection. A dot marks a process leaf; it does not imply another expandable group.

Tab switches focus between the list and bottom details; arrows scroll a visible focused details pane, Page Up/Down scroll by pages, and Esc closes it. At very small terminal heights, enlarge the terminal to reveal the pane; row navigation remains available.

Return opens Details in place, preserving the contributor tree and its selection; repeated Return keeps the pane open. Use `v` to explicitly switch views. When leaving the overview from a current worker, `v` selects that exact worker and opens its process Details without changing process-view grouping.

`c`/`m` reorder main contributors by CPU/memory while keeping the overview; `v` switches views; `o` chooses stable order in the current view, `r` reverses metric sorting, `n` sorts by PID only in process views, and `g` enters process inspection. Rows keep their positions across refreshes unless one exceeds a row above it by more than 20%, at every level; new entries arrive in contribution order, and `c`/`m` sort exactly.

The footer Diagnostics badge flags measurement limitations; Diagnostics explains read failures, exits before read, excluded observations and unavailable memory.

In Mac, click a row body to select it; use its disclosure triangle or count button to expand children, or choose **All contributors** from View options for recent/remainder groups. The row’s **ⓘ** information button, `i`, or the row context menu opens its bottom details pane: a persistent ownership heading, complete selectable paths and a **Process counts** table with Item, Value and Meaning columns.

**Attribution details** reveals deeper evidence and starts collapsed. **Copy all** in contributor and process Details copies all available detail text, including full paths, loaded arguments and collapsed evidence. It does not read arguments on your behalf.

Details in Mac and TUI do not repeat row-history charts or raw interval values. Esc or the close button returns focus to the table. **Inspect current process…** opens the current worker's process details and actions. Historical workers have no actions.

**Diagnostics** includes sampling metrics, retained-history coverage, failure breakdowns and limitations. Retained time does not establish workload completeness. **Help** defines the terms in both interfaces.

### Pause and reopen

Pause freezes both the overview and worker details. Live-icon mode collects while the Mac panel is closed and preserves history on reopen while clearing inspection. Static-icon mode stops collection and starts a new run labelled **Collected since panel opened**.

Run/scope changes reset history; old and new CPU are never combined. History is in memory and needs no recording. Detailed semantics are in the [architecture contract](../architecture.md#contributor-overview-and-recent-activity).

## Filters and measurements

The current report is not a complete accounting of agent CPU or memory. Short-lived workers can run entirely between scans, and their final CPU after the last observation is unavailable. Lower thresholds reveal more observed processes; shorter intervals can capture more workers, but neither guarantees complete coverage. These are gaps against the project's [resource visibility requirements](../architecture.md#resource-visibility-requirements), not acceptable evidence that a busy agent is idle.

### Choose visible processes

By default, **both display thresholds are zero and all observed processes in scope are included**, including idle processes and unavailable resource measurements. Interactive overviews collapse lower contributors into quantified summaries; the process/text views show their individual rows.

Zero disables each resource filter independently. With either threshold nonzero, findings must strictly exceed at least one enabled threshold. Filters change visible rows, never session totals or the Mac icon.

Only agent-associated processes appear; `--all-processes` also includes unrelated and unattributed processes owned by your user. Unknown or ambiguous agent sessions remain visible.

### Units and missing values

- CPU is the sum of measured CPU-seconds in the display window divided by its enclosing monotonic duration. Acquisition defaults to 100 ms; TUI and the Mac app publish at most every five seconds independently; text/JSONL retain one-second report windows. Slow consumers receive a combined window, not a replay burst or only the newest sample. **100% means one fully occupied core**, so a multithreaded process can exceed 100%.
- Memory is a snapshot of physical footprint in **decimal GB**. Footprint includes memory accounting that RSS omits. Process inspection also shows the kernel footprint peak when available, which can reveal earlier allocation bursts. That counter can reset on exec; it is separate from current memory and must not be summed as a simultaneous session peak. Report JSONL schema 1 exposes it as optional `kernelPeakFootprintBytes`.
- `*` marks an exceeded process threshold. Missing measurements are unavailable, not zero.

### Inspect no-longer-observed work

**Short-lived contributors:** a process observed during acquisition remains in its accounting window after it disappears. The TUI marks historical process rows `[past]`; the Mac overview uses an archive-box count and subdued historical rows. Expand it to inspect its measured CPU and last observed footprint, or pause the display to keep that window for inspection. Historical rows cannot terminate, message or focus a process. Memory-only filters use their last observed footprint for row eligibility; that value is still excluded from current memory totals. “No longer observed” is not proof of exit.

### Interpret attribution

Session CPU uses frozen point-evidence candidates, not proven ownership throughout each measured interval. Conflicting session candidates remain uncertain and are counted once. Details distinguish candidate and uncertain/unresolved CPU, recovered CPU and evidence age.

JSONL schema 1 retains compact CPU records with frozen attribution, accepted interval counts, explicit missing-read and exec-change counts, evidence-time ranges, enclosing scan endpoints and newborn birth evidence. Endpoints are an envelope, not a claim of continuous reads or ownership. A current memory label conflicting with historical CPU ownership leaves the combined row uncertain rather than assigning the memory to the old session.

```sh
agent-monitor --tui --cpu 40 --memory-gb 0.5
agent-monitor --all-processes --cpu 10
```

In the TUI, both thresholds clamp at zero. New settings apply at the next displayed window and show as pending until applied. Lowering a threshold can reveal previously omitted processes without restarting the monitor. An empty list means no matching processes were observed in that window; it does not establish that no agent work occurred.

### Compare host and observed CPU

Text, TUI and native panel headers show `CPU: host 211% of 800% · your measured processes 169% (3 without data)`. The status menu and accessibility text reuse the same context and label the displayed agent total `Observed agents: CPU …` to keep the two figures apart.

Host occupancy uses unweighted logical CPUs (100% = one core), not performance/efficiency-core computing capacity. “No data” means no valid host-counter interval between the window endpoints; a measured idle interval shows 0%.

Your measured total covers sampled current-user lifetimes with eligible CPU data, including historical contributors, excludes the monitor itself and includes processes below the table thresholds or outside agent scope. The count without data covers observed lifetimes with excluded measurements; it cannot count never-observed workers. No difference between the figures is presented as an explanation of load.

### Recovered CPU and newborn workers

CPU contributions retain exact process lifetimes and opening/closing scan identities. A qualifying newborn can contribute from a verified zero baseline at the retained pre-birth listing even if it is observed only once.

Work recovered across read gaps enters a window's rate only when its opening and closing endpoints lie inside the window; older openings are shown as separate recovered CPU-seconds, including when filters would otherwise hide the row. Combining windows deduplicates contributions and recomputes their eligibility and rate. Work never observed and CPU after the final observation stay uncounted.

### Collection cost evidence

The default prioritizes visibility over collection cost. On the measured desktop, the previous sequential collector with 100 ms waits used about 29% of one core before UI/provider work; this is a single-run measurement of the earlier implementation, not an overhead measurement of independent acquisition. Short-lived workers can still be missed. See the [controlled accounting probes](../research/cpu-accounting.md#controlled-exit-and-scheduler-probes--2026-10-23).

## History strip

Both live views show one compact history strip. It defaults to **agent CPU over the last 10 minutes**. In the TUI, **h** switches CPU → Memory → Heavy, and **t** switches 10 minutes ↔ 1 hour; the strip shows these hints. In the native panel, click **CPU · 10m** to choose a metric and time range from checked menu items. Changing the strip does not change sampling or table filters.

### History metrics

CPU totals all observed agent-associated processes (100% = one core); Memory totals their physical footprint in decimal GB. Heavy counts distinct agent processes exceeding CPU > 25% or footprint > 1 GB, independently of the table’s filters, including when the TUI shows unrelated processes.

The number beside the trace is the latest value; bars preserve peaks within each time bucket and scale from zero to the visible peak (with a minimum upper bound of 1). A flat zero draws a small baseline bar. Empty buckets and unavailable measurements remain gaps.

The native graph always has a subtle baseline and shows **No data** when the current measurement is unavailable; the TUI uses **—**. Neither means measured zero. Missing CPU or footprint makes that metric unavailable; the heavy count is unavailable if either resource is incomplete. The scope is observed agents, not a guarantee that unreadable processes are included.

### History timing and lifetime

History records **every collected report**, using that report's observations. Acquisition runs independently of the five-second display cadence; coalesced deliveries contribute their enclosing measured window. CPU represents the resource interval measured at each recorded observation; work missed between scans remains missing from history.

History accumulates while this instance runs, up to one hour; it is not saved across launches. The range ends at the latest history observation, and unsampled earlier periods stay blank.

Pause holds the strip along with the table; Resume includes measurements collected during the pause. The native live icon’s closed-panel delivered windows also feed history. Static-icon mode adds no samples while closed, leaving gaps between observations.

Closing/reopening preserves the history and metric/range choice. There is no additional polling or animation timer.

## Glossary and Diagnostics

The shared [glossary definitions](../../Sources/AgentMonitorPresentation/ReportGlossary.swift) explain process counts, current versus recent CPU, memory units, worker/runtime populations, missing data and pause.

**Processes / Procs** counts distinct process lifetimes represented by that row in the latest displayed sample, including runtimes where applicable; while paused, it describes the held sample.

Recent CPU uses the actual retained recent range, not the chart's 10-minute or one-hour range.

The main comparison keeps concise coverage warnings; detailed causes, timing, collection settings and unavailable provider capabilities belong in Diagnostics.

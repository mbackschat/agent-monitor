# Usage guide

Follow the [installation guide](installation.md), then start with the [README quick start](../README.md#quick-start). The commands below use the installed `agent-monitor` executable and work from any directory.

## Reading responsibility and retaining data

The [product question](product.md) is which agent/session and executable consume CPU or memory, with the workload CWD as context. The current overview expands sessions into executable groups and exact processes. CPU/memory ordering applies within those groups too. Full paths, available arguments and attribution evidence are inspection details. Session IDs currently identify sessions; human-readable session names are not available. “Multiple directories” is a directory summary, not a session name; improving that confusing primary label is tracked in [UX-01](../PLAN.md#resource-accounting-priority).

Normal monitoring keeps bounded rolling data in memory, including the detailed recent window and scalar chart. It does not automatically write process-data logs or accumulate an unbounded history. Pause freezes a bounded view while collection continues. Diagnostic recording is a [separate, unimplemented proposal](proposals/diagnostic-recording.md), off by default and requiring explicit opt-in. Selecting JSONL or saving an export explicitly is distinct from automatic capture.

## Finite CPU diagnosis and local guides

```sh
agent-monitor guide
agent-monitor diagnose cpu
agent-monitor diagnose cpu --json
agent-monitor diagnose cpu --json-schema
agent-monitor guide semantics
agent-monitor guide diagnostics
agent-monitor guide actions
agent-monitor guide tui
```

`diagnose cpu` takes a baseline followed by three one-second waits and scans, then returns the top ten measured current-user lifetimes, including nonagents and the invoking agent but excluding the monitor. There are no tuning options; explicitly supplied report controls are rejected, including default-valued controls. Report thresholds, streaming and grouping do not alter diagnosis. Collection and bounded provider lookups add runtime beyond the waits; help, guides and schemas run locally without any sampling or provider queries.

Contributors rank by observed CPU-seconds, with exact PID/start identity breaking ties. Mean and peak CPU describe each lifetime's own measured coverage; a brief high-rate burst does not outrank more measured CPU. Newborn intervals include zero before birth, earlier contributors retain their measured CPU and latest footprint, and omitted contributors remain in population totals. `elapsedSeconds` includes scans on the Mach clock, excluding sleep; display timestamps do not define it. Missing observations and CPU after the last observation remain uncounted. Coverage counts observations, not complete visibility or unique inaccessible processes.

Host occupancy appears beside measured process contribution. Its valid intervals are duration-weighted, with separate coverage and no single capacity when the logical CPU count changes. It is unweighted occupancy (100% = one logical CPU), not equivalent performance/efficiency-core capacity. Never subtract process totals from it or infer an idle machine from low measured CPU. Missing values are omitted in JSON and explained in text, not invented as zero.

Diagnosis JSON is one compact document with independent `schemaVersion: 1`; report JSONL also uses its own schema version 1. The [diagnosis schema](../Sources/AgentMonitorPresentation/Resources/diagnosis.schema.json) rejects unknown properties. Results include numeric coverage, exact identities, bounded executable labels, attribution evidence and timestamps, performed provider lookup outcomes and stable diagnostic codes. Names and paths are untrusted data. Available attribution is the latest association, not ownership of all window CPU or exclusive ownership of a shared daemon. `notObservedAtEnrichment` does not prove exit; metadata and provider failures remain distinct. Read `guide semantics` and `guide diagnostics` for the published values and next observations.

Exit **0** includes valid empty or partial results; **1** emits `collectionFailed` and an explanation on stderr with no success document; invalid usage exits **64**. Provider failure alone does not discard usable CPU. JSON stdout has no banners, colour or guidance. Diagnosis does not message, signal, change focus or read transcripts/tokens. Native reads and provider listings can consume resources, start helpers, connect and update caches; performed lookups are reported. Actions require a separate request and fresh identity verification; `--pid` resolves at invocation rather than binding to a prior diagnosis.

For finite memory or repeated observations, use existing reports:

```sh
agent-monitor --json --all-processes --memory-gb 1 --samples 1
agent-monitor --json --all-processes --samples 3 --interval 2
```

With at least one nonzero threshold, report display filters match strictly above any enabled threshold: CPU **or** physical footprint in decimal GB, not RSS. Zero disables that resource filter. Locate a known PID by its PID/start record in the returned findings; there is no PID-report filter. See [report output](#text-and-jsonl-output) for the separate report controls.

## Live terminal view

```sh
agent-monitor --tui
agent-monitor --tui --group session
```

`--tui` (also accepted as `-tui`) watches continuously unless you supply a `--samples` limit. It requires interactive stdin and stdout and cannot be combined with JSON output. Use `--no-color` or set `NO_COLOR=1` to disable colors.

| Key | Action |
| --- | --- |
| `v` / `a` | Switch overview/process view / open recent and remainder sections |
| Return | Inspect the selected current overview process in the action-capable process view |
| `i` | Show/hide selected overview details without folding its children |
| Page Up / Page Down | Scroll expanded overview details |
| **d** | Start a finite CPU diagnosis immediately; three one-second waits plus scans and up to three seconds per queried provider |
| ↑ / ↓ | Select a row |
| ← / → | Collapse/expand a session or close/open process details |
| Shift+← / Shift+→ | Collapse/expand displayed session groups at the current level |
| `g` | Toggle session grouping |
| `k` | Review SIGTERM for the selected process |
| `s` | Compose a message to a verified Codex or Claude Code recipient |
| `f` | Bring the terminal hosting the selected process's or group's agent session to the front |
| `c` / `m` / `n` | Sort by CPU, memory footprint, or PID |
| `o` | Stable order: keep existing positions and append arrivals (default) |
| `r` | Reverse CPU, footprint or PID sort direction |
| `h` | Cycle history: CPU (default), memory, heavy-process count |
| `t` | Switch history between the last 10 minutes (default) and one hour |
| `1` / `2` | Lower/raise the CPU threshold by 10 percentage points |
| `3` / `4` | Lower/raise the memory threshold by 1 decimal GB |
| `<` / `>` | Update less/more often: 0.1, 0.25, 0.5, 1, 2, 5, 10, 30 or 60 seconds, applied at once |
| `.` | Pin/unpin the selected process or session; values keep updating |
| `p` | Pause/resume the view; sampling continues and resuming shows the latest data |
| `[` / `]` | Scroll process details |
| `-` / `+` | Shrink/grow the details pane by 5 percentage points |
| `0` / `9` | Minimize/maximize the details pane |
| `=` | Restore the chosen details split |
| `q` / Ctrl-C | Quit |

Pins stay first in pin order, independently of sorting. `+` marks a pinned row and `@` marks the selected pinned row; `>` still marks an ordinary selection. A pinned group's expanded children use arrival order in Stable order and PID order in other sorts. If a target leaves the current heavy results, its placeholder remains with **Not in current results**; this does not prove it exited, and no old measurements or actions are offered. The same process lifetime or session can return automatically; PID reuse cannot replace a pin. `.` removes the selected pin. Pins last until unpinned or the monitor quits, and native pins also survive closing/reopening the panel. A process pinned separately is omitted from its group's child rows; group totals still cover its full heavy membership. Pinned groups retain their identity when switching to flat mode.

These are the current source-build keys. An installed release can differ; use its on-screen help and `agent-monitor guide tui`.

Text, JSONL and TUI reports request a 100 ms acquisition period. Native acquisition runs independently of background metadata, provider queries and display. Scan overruns delay the next scan without overlapping or catch-up scans; delivery can lag acquisition. An explicit `--interval` overrides it. The header shows the update interval and, while frozen, `PAUSED at` the time of the displayed sample. The shortest currently selectable acquisition period is 100 ms. While frozen, selection, sorting, details and actions keep working on the frozen rows; actions still recheck the live process, and threshold changes stay pending until you unfreeze. Selection follows the process across sorting and refreshes. Details start minimized; opening them uses an initial 50% split. The adjustable split ranges from 10–90%, subject to available terminal space. Minimizing or maximizing does not overwrite your chosen split.

The layout adapts to terminal size. Narrow views abbreviate names and session IDs and omit the terminal/project column; open details for the full information. The process column contains names only, with executable paths and optional command arguments in details. Very small windows show a resize hint.

To copy text, drag-select it and use your terminal's Copy command (usually Command-C on macOS). Navigation is keyboard-driven; mouse selection belongs to the terminal. Whether selection survives a refresh depends on your terminal.

In CPU diagnosis, **↑/↓** and **Page Up/Down** scroll the fixed result, **x** cancels, **Esc** returns to the live report, and **d** runs again. Rerun discards the old result immediately and remains disabled until the preceding run finishes cleanup. After Back, the live footer shows “CPU diagnosis cleanup in progress” until `d` is available again. Compact footers retain “Resize for all keys”; timing is explained in the collecting view and `guide tui`. Each run may query providers again. The view ranks the top ten by measured CPU-seconds, including earlier contributors; the live table, history and paused state stay independent. Diagnosis rows have no actions. Below 40×8, starting and rerunning are disabled while Cancel, Back and quit remain available. **Monitor helper** flags observed descendants of this monitor only; reparented/unobserved helpers and other monitor instances may be unflagged, and their CPU remains in totals.

## Process actions

These controls are available from release 0.2.0. Expand a session group and select an individual process before terminating or messaging; focus also works on a group. Opening a confirmation freezes its process identity: subsequent sorting, refreshes, and filter changes cannot retarget it.

**Terminate:** press `k`, inspect the PID, executable and session, then press Ctrl-Y to send SIGTERM. Esc cancels. Only the selected process is signaled, including when you explicitly select an agent runtime; children and process groups are not signaled automatically. SIGKILL is not offered. The process must still have the same PID, start time and executable and belong to your user. macOS identity checks and PID-based signaling are not atomic, so a small race remains. “SIGTERM accepted” does not mean the process exited.

**Message:** press `s` to verify recipients and open the composer. For Codex, Root agent is the default and Tab cycles to Selected agent when distinct; a Claude Code session has one recipient. An unavailable root remains disabled rather than silently switching to a child. Type or paste up to 4,000 characters; Backspace edits the end. Bracketed paste preserves newlines and cannot activate commands; terminal control characters are removed. Enter opens the full message review, Ctrl-Y sends it, and Esc returns to editing or cancels. ↑/↓ and Page Up/Down scroll the panel. Ctrl-C quits from any panel; `q` is ordinary message text while composing.

**Focus:** press `f` to bring the terminal hosting the selected process's agent runtime to the front. On a collapsed session group, `f` focuses the group's runtime when its processes share exactly one; otherwise expand the group and select a process. The runtime, not the workload, is the target because agent tool subprocesses often have no terminal. In Terminal.app the tab on the runtime's terminal device is selected, its window is unminimized and ordered front, and Terminal is activated; the result panel names the device. Other terminal and editor apps found above the runtime are only asked to come to the front, so another of their windows may show. Sessions under tmux, screen, or ssh, and background runtimes without a terminal, report that nothing was focused. On first use macOS asks whether the terminal running Agent Monitor may control Terminal; that Automation grant applies to everything run in that terminal, and it can be revoked in System Settings › Privacy & Security › Automation. Since macOS 14 activation is a request, so macOS may keep another app in front. Focus never types into, runs commands in, or reads the target terminal.

The generated context identifies the selected workload and the measurements you inspected, for example:

```text
[Agent Monitor: selected process PID 42001 (swift-frontend)]
Sample time: 2026-10-15T18:42:00Z
CPU: 184.6% (100% = one core)
Memory footprint: 1.42 GB

Please investigate why this process is using so much CPU.
```

The context uses the workload PID, not the recipient's runtime PID. CPU and memory come from the selected observation, including when paused; the ISO 8601 sample time remains unchanged during composition or saved-draft restoration. Missing resources or time are explicitly unavailable. Direct-PID CLI messaging has no recorded sample time or CPU interval, so those fields are unavailable rather than inferred. Both target and message remain visible in the scrollable review. Immediately before sending, the monitor rechecks live provider routing, process lifetime, executable and attribution. An exited/reused process, changed attribution or changed recipient availability requires reopening the composer. Historical detached ancestry, ambiguous sessions and unverified runtimes cannot be messaged.

Messaging requires a Codex CLI supporting `app-server proxy`, `thread/read` with `sessionId`, and `queue` (protocol checked against 0.162.1). Both inspection and queueing use the default local app-server socket under the current Codex environment. The monitor never starts a server, resumes a transcript or injects terminal input. Standalone/no-daemon sessions and remote/custom sockets are unsupported. Provider calls have a 10-second deadline and bounded output. A queue timeout or failure may occur after acceptance: check Codex before retrying. There are no automatic retries.

Acceptance means only that Codex accepted the queue request; delivery, execution and the workload's continued existence are unverified. Messages are unsuitable as an emergency stop. Message text is passed as a literal CLI argument and may be visible to local process inspection while `codex queue` runs; Agent Monitor does not persist drafts or provider output.

Claude Code messaging requires Claude Code 2.1.224 or later on PATH (checked against 2.1.300) and a session with cross-session messaging, which binds a per-session inbox socket; bare-mode sessions have none. The monitor first asks `claude agents --json` whether the attributed runtime PID still hosts exactly that session, then reads the inbox path that Claude exported to the workload (`CLAUDE_CODE_MESSAGING_SOCKET`) and writes one message line to it. It never reads or sends the session's messaging token, so the session treats the message like one from another session: under the default settings, a session that prompts for permissions delivers it, while a session that bypasses permission prompts holds it for your approval, and `crossSessionInbound` can hold or silently refuse it. A delivered message starts a new turn in an idle session or is read between tool calls in a busy one; it cannot approve prompts or run slash commands. If the inbox is missing or refuses the connection, nothing was sent. A timeout after the line was written may follow acceptance: check the session before retrying. Claude Code does not document the inbox message format; it may change between releases. See [Claude session messaging research](research/claude-session-messaging.md).

### Actions from the command line

The same actions are available without the TUI, for a PID taken from a text report:

```sh
agent-monitor kill --pid 42001
agent-monitor message --pid 42001 --text "Why is this so busy?" [--to root|selected]
agent-monitor focus --pid 42001
```

Each command reads the process's current lifetime and attribution, independently of the display thresholds, and applies the same identity, recipient and runtime checks as the TUI. `kill` and `message` print the target, and for messages the recipient and the exact text with its observation context, then ask `[y/N]`. Without an interactive stdin they refuse unless `--yes` is given, so a script must opt in explicitly. `--to selected` addresses the Codex agent that launched the process instead of the root; a Claude Code session has one recipient. `focus` needs no confirmation.

| Exit status | Meaning |
| --- | --- |
| `0` | Accepted: SIGTERM sent, message handed over, or terminal focused. Exit, delivery and action are not confirmed. |
| `1` | Nothing was done: refused, cancelled, not found, or failed before sending. |
| `2` | `message` only: the message may have been accepted although that could not be confirmed. Check the session before retrying. |

JSONL output has no action commands.

## Main contributors and recent activity

On Mac, **Recent coverage** holds sampling explanations and current-scan counts; the process table has a **Sampling coverage** disclosure. These notes stay collapsed while one coverage-status row, always present, keeps actual read failures, overruns and pressure visible; processes that exited before their read are a neutral notice. TUI keeps explanations behind `i` details.

Mac and TUI default to **Main contributors**. Individually shown sessions are the union of the top five by combined group CPU (strictly above 25% of one core) and the top five by current memory (at least 100 MB). Hysteresis keeps small rank changes from constantly reshuffling the list. These relevance floors collapse rows; they do not remove measured work. A zero-CPU process can still matter through memory, and zero CPU does not mean it has stopped.

**Recent contributors** keeps bursts discoverable after workers disappear: sessions qualify through at least 0.5 recent candidate CPU-seconds, a 100 MB sampled worker footprint, or having recently left the main list. **More processes** quantifies the remaining exact-session population. **Unresolved / uncertain** always remains visible; recognised shared agent runtimes have their own summary. **Show all** (TUI `a`) opens the recent/remainder sections. Explicit resource filters still apply to process rows, with filtered counts and full totals retained.

CPU bars use a fixed one-core scale (full at 100%, clamped above it); memory bars scale to physical RAM. Numeric CPU can still exceed 100%. Native tooltips also show each row’s share of observed totals. Hover in the Mac app for definitions, or expand coverage/details when needed. Expand root/session → thread where relevant → executable → process. `executable node` combines observed paths ending in `node`; it does not merge `node_repl` or guess from display names. Exact lifetimes prevent PID reuse from becoming the same worker. Session CPU is **point-evidence candidate CPU**, not proven ownership throughout an interval. Earlier unresolved work stays unresolved after later evidence becomes available. Workers changing sessions can count in both historical memberships; parent distinct counts deduplicate them.

**Recent** targets 60 seconds, within fixed record/text limits. It reports actual retained coverage, missing observations and older-opening recovered CPU separately. A retention-limit/gap qualifier clears once the affected boundary ages out of the target range. Publication backlog can combine units without dropping measured CPU; a warning shows how many units were coalesced and the maximum unit span. Whole-unit retention can shorten the range, or widen it when the newest unit alone exceeds the target; the displayed duration is the actual range. Memory maxima come from acquisition readings, even if a spike was gone by the next display refresh. Last kernel task peaks remain inspectable but can predate monitoring or reset on exec; they are not recent-window maxima. **No longer observed** means absent from the latest identified scan, not confirmed exit or a monotonic stopped counter. Read failures and exits before read disclose distinct same-user-listed PID values and per-scan failure counts, not identified workers or verified agent ownership; released PID detail produces count ranges. Retention cannot recover never-observed processes or their final exit CPU.

In TUI, arrows select/fold and `.` pins the owning session. Folding a group reveals children; `i` toggles details for the selection, while expanding a selected worker reveals its evidence. Page Up/Down scroll details. Return inspects an eligible current worker without changing the process-view grouping; Return in the process view does nothing. `c`/`m` reorder main contributors by CPU/memory while keeping the overview; `v` switches views, and `n`/`o`/`g` enter process inspection. Rows keep their positions across refreshes unless one exceeds a row above it by more than 20%, at every level; new entries arrive in contribution order, and `c`/`m` sort exactly. The coverage-status row below totals exposes read failures, exits before read, excluded observations and unavailable memory. In Mac, click rows, use **Show all**, and choose **Inspect current process…** from a current worker's details. Historical workers have no actions. **Sampling coverage** opens a compact metric grid, retained-history bar and failure breakdown. Hover values for definitions and the info icon for sampling limitations. The bar measures retained time, not workload completeness. TUI coverage details use aligned metric columns.

Pause freezes both the overview and worker details. Live-icon mode collects while the Mac panel is closed and preserves history on reopen while clearing inspection. Static-icon mode stops collection and starts a new run labelled **Collected since panel opened**. Run/scope changes reset history; old and new CPU are never combined. History is in memory and needs no recording. Detailed semantics are in the [architecture contract](architecture.md#contributor-overview-and-recent-activity).

## Filters and measurements

The current report is not a complete accounting of agent CPU or memory. Short-lived workers can run entirely between scans, and their final CPU after the last observation is unavailable. Lower thresholds reveal more observed processes; shorter intervals can capture more workers, but neither guarantees complete coverage. These are gaps against the project's [resource visibility requirements](architecture.md#resource-visibility-requirements), not acceptable evidence that a busy agent is idle.

By default, **both display thresholds are zero and all observed processes in scope are included**, including idle processes and unavailable resource measurements. Interactive overviews collapse lower contributors into quantified summaries; the process/text views show their individual rows. Zero disables each resource filter independently. With either threshold nonzero, findings must strictly exceed at least one enabled threshold. Filters change visible rows, never session totals or the Mac icon. Only agent-associated processes appear; `--all-processes` also includes unrelated and unattributed processes owned by your user. Unknown or ambiguous agent sessions remain visible.

- CPU is the sum of measured CPU-seconds in the display window divided by its enclosing monotonic duration. Acquisition defaults to 100 ms; TUI and the Mac app publish at most every five seconds independently; text/JSONL retain one-second report windows. Slow consumers receive a combined window, not a replay burst or only the newest sample. **100% means one fully occupied core**, so a multithreaded process can exceed 100%.
- Memory is a snapshot of physical footprint in **decimal GB**. Footprint includes memory accounting that RSS omits. Process inspection also shows the kernel footprint peak when available, which can reveal earlier allocation bursts. That counter can reset on exec; it is separate from current memory and must not be summed as a simultaneous session peak. Report JSONL schema 1 exposes it as optional `kernelPeakFootprintBytes`.
- `*` marks an exceeded process threshold. Missing measurements are unavailable, not zero.

**Short-lived contributors:** a process observed during acquisition remains in its accounting window after it disappears. The TUI marks it `[past]`; the Mac app marks it **Past**. Expand it to inspect its measured CPU and last observed footprint, or pause the display to keep that window for inspection. Historical rows cannot terminate, message or focus a process. Memory-only filters use their last observed footprint for row eligibility; that value is still excluded from current memory totals. “No longer observed” is not proof of exit.

Session CPU uses frozen point-evidence candidates, not proven ownership throughout each measured interval. Conflicting session candidates remain uncertain and are counted once. Details distinguish candidate and uncertain/unresolved CPU, recovered CPU and evidence age. JSONL schema 1 retains compact CPU records with frozen attribution, accepted interval counts, explicit missing-read and exec-change counts, evidence-time ranges, enclosing scan endpoints and newborn birth evidence. Endpoints are an envelope, not a claim of continuous reads or ownership. A current memory label conflicting with historical CPU ownership leaves the combined row uncertain rather than assigning the memory to the old session.

```sh
agent-monitor --tui --cpu 40 --memory-gb 0.5
agent-monitor --all-processes --cpu 10
```

In the TUI, both thresholds clamp at zero. New settings apply at the next displayed window and show as pending until applied. Lowering a threshold can reveal previously omitted processes without restarting the monitor. An empty list means no matching processes were observed in that window; it does not establish that no agent work occurred.

Text, TUI and native panel headers show `CPU: host 211% of 800% · your measured processes 169% (3 without data)`. The status menu and accessibility text reuse the same context and label the displayed agent total `Observed agents: CPU …` to keep the two figures apart. Host occupancy uses unweighted logical CPUs (100% = one core), not performance/efficiency-core computing capacity. “No data” means no valid host-counter interval between the window endpoints; a measured idle interval shows 0%. Your measured total covers sampled current-user lifetimes with eligible CPU data, including historical contributors, excludes the monitor itself and includes processes below the table thresholds or outside agent scope. The count without data covers observed lifetimes with excluded measurements; it cannot count never-observed workers. No difference between the figures is presented as an explanation of load.

CPU contributions retain exact process lifetimes and opening/closing scan identities. A qualifying newborn can contribute from a verified zero baseline at the retained pre-birth listing even if it is observed only once. Work recovered across read gaps enters a window's rate only when its opening and closing endpoints lie inside the window; older openings are shown as separate recovered CPU-seconds, including when filters would otherwise hide the row. Combining windows deduplicates contributions and recomputes their eligibility and rate. Work never observed and CPU after the final observation stay uncounted.

The default prioritizes visibility over collection cost. On the measured desktop, the previous sequential collector with 100 ms waits used about 29% of one core before UI/provider work; this is a single-run measurement of the earlier implementation, not an overhead measurement of independent acquisition. Short-lived workers can still be missed. See the [controlled accounting probes](research/cpu-accounting.md#controlled-exit-and-scheduler-probes--2026-10-23).

## Session grouping

`--group session` groups text output and the interactive process view by launch session. The TUI opens in Main contributors; press `v` for process inspection or `g` to enter it and switch grouping. → expands a group or opens process details, and ← collapses it. New groups start collapsed; previously expanded session/root groups reopen when the same identity returns after filtering. Explicit collapse stays collapsed. The monitor remembers up to 256 absent expanded groups, evicting the oldest expansion choices first; visible or pinned groups are not evicted.

Both interactive views also restore the inspected process's details when that exact PID/start lifetime returns. While it is missing, no stale details are shown. Selecting another row, changing disclosure/grouping or pane mode, or opening an action panel cancels that pending restoration, so a returning process cannot override a new inspection choice. One process is inspected at a time: inline in the Mac app and in the TUI's details pane. Expansion memory lasts for the current collection/view; closing the native panel or restarting the TUI clears it.

**Shift+←/→** changes session disclosure at the current level in both live views. On a top-level row (or with no row selected), it collapses/expands all displayed session groups, including pinned groups. On a child process inside an expanded group, it changes only the containing session, hiding/revealing siblings; collapsing moves selection/focus to the parent. Individually pinned processes count as top-level rows. The Mac app's flattened single-process rows also count as top-level and have no group disclosure to change. Missing groups are unaffected, repeat presses are idempotent, and choices use the same sticky expansion rules. Process details remain single-target; in Processes view without pinned session groups, the bulk command has no effect. It is disabled in action panels and editors.

Unpinned groups appear only when at least one member passes the display filters and is not separately pinned. Explicitly pinned groups remain visible even when all their children are filtered. Groups show the project, session, process count, and CPU/memory totals of **all observed session members**, including processes hidden by display filters. These totals do not recover work missed between scans. `~` marks a partial total when measurements are missing. CPU/memory sorting orders groups by their totals; PID sorting uses each group's lowest observed PID.

Unresolved or ambiguous processes stay separate even when they share a project or runtime. Session evidence identifies launch origin: a shared Gradle, Kotlin, or MCP daemon may later serve other sessions. See [attribution evidence](architecture.md#attribution-evidence-and-inspection-scope) for the exact interpretation and inspection scope.

A Claude Code runtime carries no session marker of its own, and Bash-tool shells and other macOS system binaries expose no environment. When `claude` is on `PATH`, the monitor asks `claude agents --json` which session each observed runtime hosts and shows the runtime and such children in that session with `sessionRegistry` evidence. This names the **current** session rather than the launch session, and cannot receive messages. The listing runs automatically for observed runtimes that need it, at most once a minute unless a new runtime appears, including while the live-icon panel is closed. It runs separately from native acquisition and rechecks the exact runtime after the lookup.

**Shared runtime** identifies a Codex runtime process with multiple distinct thread writer descriptors and no exact attributed thread. This describes shared runtime usage, rather than a failed workload lookup. It appears consistently in process rows, session groups, details, text output and action targets. Its singleton group remains separate from exact sessions and unresolved workloads. JSONL retains the original ambiguous evidence and candidate thread IDs. A runtime without a terminal still cannot be focused; the label does not establish a terminal-client mapping.

Project names describe the displayed workloads’ working directories, not session ownership. A session with more than one distinct readable working directory shows **Multiple directories**, including when one directory is nested inside another. This does not establish separate projects or repository roots. Otherwise, missing directory evidence shows **Unknown project**. A **shared runtime** has no project subtitle because its launch directory may belong to another session. Expanded details retain both the work directory and runtime directory. This labeling does not change attribution or grouping identities.

## Text and JSONL output

With no options, the monitor takes a baseline and requests its next acquisition after a 100 ms start-to-start period, then prints one resolved report. `--samples 0` watches until Ctrl-C; `--interval` controls the requested acquisition period (0.1–60 seconds). Each text report includes a UTC timestamp.

Text reports and the `kill`, `message` and `focus` commands use colors only when their output goes to a terminal: the report header in blue, process lines and unresolved sessions in yellow, secondary details in gray, accepted results in green and errors in red. Pipes and files get plain text, and `--no-color` or `NO_COLOR=1` turns colors off everywhere. JSONL is never colored; `--no-color` is accepted with `--json` and has no effect there.

```sh
# Continuous text reports every two seconds
agent-monitor --samples 0 --interval 2

# Three machine-readable reports
agent-monitor --json --samples 3

# Print the report schema without sampling
agent-monitor --json-schema
```

JSONL contains one complete, compact JSON object per line/report. It retains the flat process list and full attribution evidence, including ambiguous candidate IDs. Schema version 1 retains required `observedFindings`, a flat list independent of display thresholds alongside the filtered `findings`. Both use the same process shape and requested scope. The required report-level `cpuAccounting` object contains: optional `hostBusyPercent`, `logicalCPUCount`, `measuredUserPercent`, `unmeasuredLifetimeCount` and optional `previousScanSeconds`. Unavailable optional fields are omitted. Report and nested objects reject unknown fields. Findings remain flat; `sessionRegistry` evidence is retained. `--group session` is incompatible with `--json` and `--json-schema`. The optional `cpuAccounting.acquisition` object reports run/scan identity, requested QoS, requested/achieved periods, scan work, resolution delay and prompt-capture outcomes. The shared header shows the achieved acquisition period in milliseconds and warns when resolution is behind; neither a requested interval nor a successful prompt read guarantees complete coverage. Each window also reports `acquisitionCoverage`: scan count, maximum gap and overrun count across all scans. `publicationCoverage` distinguishes source units from admitted history units and records backlog-coalesced counts, maximum unit span and the enclosing coalesced time range. Under delivery pressure, `collapsedContributions` preserves exact older CPU, interval counts and sampled memory maxima with a time range and provable worker-count bounds; identity/category detail loss is explicit. Include collapsed CPU when summing detailed records. A current population exceeding the remaining capacity fails explicitly.

`--commands` includes command arguments in reports and process details. Arguments can contain credentials or other sensitive values and are omitted by default. Session IDs and project paths can still appear without this option.

For the complete option reference and defaults, run `agent-monitor --help`.

## History strip

Both live views show one compact history strip. It defaults to **agent CPU over the last 10 minutes**. In the TUI, **h** switches CPU → Memory → Heavy, and **t** switches 10 minutes ↔ 1 hour; the strip shows these hints. In the native panel, click **CPU · 10m** to choose a metric and time range from checked menu items. Changing the strip does not change sampling or table filters.

CPU totals all observed agent-associated processes (100% = one core); Memory totals their physical footprint in decimal GB. Heavy counts distinct agent processes exceeding CPU > 25% or footprint > 1 GB, independently of the table’s filters, including when the TUI shows unrelated processes. The number beside the trace is the latest value; bars preserve peaks within each time bucket and scale from zero to the visible peak (with a minimum upper bound of 1). A flat zero draws a small baseline bar. Empty buckets and unavailable measurements remain gaps. The native graph always has a subtle baseline and shows **No data** when the current measurement is unavailable; the TUI uses **—**. Neither means measured zero. Missing CPU or footprint makes that metric unavailable; the heavy count is unavailable if either resource is incomplete. The scope is observed agents, not a guarantee that unreadable processes are included.

History records **every collected report**, using that report's observations. Acquisition runs independently of the five-second display cadence; coalesced deliveries contribute their enclosing measured window. CPU represents the resource interval measured at each recorded observation; work missed between scans remains missing from history. History accumulates while this instance runs, up to one hour; it is not saved across launches. The range ends at the latest history observation, and unsampled earlier periods stay blank. Pause holds the strip along with the table; Resume includes measurements collected during the pause. The native live icon’s closed-panel delivered windows also feed history. Static-icon mode adds no samples while closed, leaving gaps between observations. Closing/reopening preserves the history and metric/range choice. There is no additional polling or animation timer.

## Menu bar app

**View options** separates **Display filters** (CPU and footprint thresholds) from **Sampling** (acquisition interval and live icon). Filter tooltips explain their scope: visible process rows change, while observed totals and recent activity stay unchanged.

From a source checkout, run `bash scripts/menubar.sh run` and click the load icon in the menu bar. This opens a compact native panel. Drag the popover’s top edge away from the menu bar to detach it using AppKit’s built-in behavior; close it and click the icon again to reopen at the menu bar. The detached panel keeps the same content and selected sampling interval. The app follows the system’s light/dark appearance, using native background, text and accent colors without a separate theme setting. The panel keeps its height as rows update or details expand; content scrolls inside it. Choose **Compact**, **Standard** or **Tall** in the footer to change the height and see less or more content. The choice lasts until quit and is capped to fit the screen when opening. Click anywhere on a row to expand or collapse it. Every row has a chevron: right means collapsed, down means expanded. The focus outline marks keyboard focus, not expansion. Session groups have a larger chevron and a gray count badge for all observed members; individual processes have a smaller chevron and a trailing info-circle control. The badge and info control share the trailing column and are part of the whole-row click target. Expanded children are indented. Pin remains a separate, enlarged button. Unpinned sessions with one observed process whose row passes the filters show that process directly, including its project and session context; sessions with multiple observed processes and pinned sessions get a group row. Compact single-line rows align identity, CPU and memory; disclosure and tooltips reveal context. Expand a process to inspect attribution and find **Terminal**, **Message…** and **Terminate…**. Open **View options** for **Group by agent session / Processes**, Stable order or CPU/footprint/PID sorting, ascending order, CPU and footprint thresholds, and the sampling interval. Show and Sort by offer their checked choices directly in the menu. CPU, footprint and interval submenus list actual values with a checkmark beside the current selection; the selected interval defaults to 100 ms and ranges from 0.1 to 60 seconds, including 15 seconds. The TUI retains its incremental controls. The dropdown stays stable while samples arrive. Changes apply to the running collector without restarting its CPU baseline; a pending label remains until the displayed sample uses the requested thresholds. Display/sampling choices survive panel dismissal until quit. The app starts with the default agent-only scope and thresholds.

Point at a row or focus it with the keyboard to reveal **Pin**. A pinned row keeps its pin button visible; click it again to unpin. The row context menu offers **Pin/Unpin**, **Copy PID**, **Focus terminal**, **Message…** and **Terminate…**. Unavailable actions remain visible but dimmed, including actions on missing pins, messaging without an exact verified session, and terminal focus without a known terminal runtime. Group rows support focus when their processes agree on one runtime; expand and choose a process for messaging or termination. Terminate still opens confirmation, and Message still opens composition and review. Pins appear in a highlighted section above the other results. Click the row itself to expand/collapse, as before. A pinned session stays a session header even when only one observed process remains. If a pinned target is absent from the displayed results, its row says **Not in current results** and keeps the same filled pin icon for unpinning. The target may have fallen below the filters, exited or become unreadable; the placeholder does not distinguish these causes. Its live row returns when the same identity appears again.

Each time the Mac panel opens, keyboard focus starts at the first displayed row. Returning from action review or diagnosis restores the retained selected row, falling back to the first visible row or empty table. While findings load or the table is empty, the table itself receives focus; the first arriving row takes it only if you have left focus there. Refreshes never pull focus back from View options or another control. Tab/Shift-Tab still reaches menus and buttons normally.

In Main contributors, `v` opens the process view and `a` opens recent/remainder disclosure. The following row/action controls describe the process view. Open **View options → Keyboard shortcuts** for compact help inside the panel; **Hide** dismisses it without changing the panel height. Use Tab/Shift-Tab to reach native controls. With a row header focused, ↑/↓ moves between visible rows and scrolls the focused row into view; ← collapses and → expands the focused row. Repeating either arrow leaves the row in that state. `.` pins or unpins the focused row, including its Pin button or an unavailable pin’s Unpin button. Return and Space retain native control activation. Use the same browsing keys as the TUI: `p` pause, `c/m/n/o` CPU/memory/PID/stable sorting, `r` reverse, `g` grouping, `h` cycles history through CPU/memory/heavy count, `t` switches its range between 10 minutes and one hour, `1/2` CPU threshold, `3/4` memory threshold, `</>` slower/faster, `k/s/f` terminate/message/focus, and `q` quit. These keys do not operate inside action panels or the message editor. `y` copies the focused process’s numeric PID; **Copy PID** is also in its right-click menu and expanded details, where the PID is selectable text. Groups and missing pinned placeholders have no copyable PID. Shortcuts target the focused row, never a hovered or stale selection. A session's **Terminal** action is available in its details and context menu. Native details use the scroll area and panel size choices instead of the TUI's split-pane keys.

Click **Pause** (`p`) before targeting a moving row. It holds the displayed values and row order, with **Paused at** showing the sample time; **Resume** immediately shows the latest collected sample. Collection continues while paused, but the icon’s bars hold the same displayed sample. You can expand details and use actions against the held rows; actions still verify the live target. Pause is unavailable before the first sample or during action review. Reopening the panel starts live. For live values without resource-driven movement, use Stable order.

**Terminate…** reviews one frozen process before sending SIGTERM. **Message…** verifies live recipients, defaults to the root agent where applicable, then shows the exact outgoing text including PID, CPU, memory footprint and sample time before **Send message**. **Copy message** is available while composing and reviewing, and copies exactly that outgoing text without sending it; it reports Copied or Copy failed. **Terminal** uses the existing terminal-focus adapters; macOS may ask to let Agent Monitor control the target terminal. Acceptance does not confirm termination or message delivery. No action automatically retries.

An unsent message is kept in memory when you dismiss the panel. On reopening, use **Resume…** to recheck the original target and recipient, **Copy text** to recover it, or **Discard** to remove it. Resume returns to editing and requires review again. If verification fails, the text stays saved. Cancel in the composer discards the message; quitting the app clears saved drafts.

**Stable order** is the default in the process view in both GUI and TUI: existing rows keep their relative order as values change, new identities append, and departed rows disappear. Pins stay at the top. In the native app choose **View options → Stable order**; in the TUI press **o**. CPU, footprint and PID remain available (`c`, `m`, `n` in TUI). Switching back to Stable order retains the current order; reverse/Ascending does not apply. The first batch and simultaneous arrivals start in descending CPU order. Native reopening preserves surviving rows’ order.

New process rows and their parent session headers receive a system-adaptive gray background for three seconds, followed by a brief fade (no animation with Reduce Motion). Parent headers highlight even when collapsed, so arrivals are visible without expanding. Initial loading and reopening do not highlight the whole list. Reordering, pinning and expanding rows do not restart the highlight. A returning identity counts as a new arrival; while paused, arrivals are highlighted only when Resume applies the latest sample.

The menu bar icon uses three thick bars for the observed agents’ CPU as a share of your Mac's logical processor capacity: empty at zero, one below 25%, two from 25% to below 50%, and three at 50% or more. Right-click or Control-click the menu bar icon for raw CPU, footprint, the observed-process count, threshold explanation and sample time. The same menu provides **Open Agent Monitor**, **View options** and **Quit Agent Monitor**; left-click opens or closes the process panel. Status text stays fixed while the menu is open and refreshes on the next opening. Opening this menu does not request a fresh sample or switch to the faster panel interval. The icon bars use all observed agents in the displayed snapshot while open, including Pause; Resume updates both immediately. The Observed processes heading shows the same total, including singletons and collapsed children. Pins never double-count a process, and absent pinned placeholders do not count. While closed, the icon uses the latest collected unfiltered observations. The same three-bar icon appears from startup onward. Startup uses a single 250 ms sampling interval (or the shorter selected interval) before returning to the selected interval, open or closed; actual feedback also includes the collection time. Before that first sample or after collection failure, the bars are unfilled; the right-click menu explains the state. Unavailable CPU also leaves the bars unfilled. Totals with missing measurements are qualified in the right-click menu. In static-icon mode, the menu explains that sampling runs only while the panel is open.

<p><img src="assets/menubar-load-icons.webp" width="300" height="92" alt="The same three-bar icon at startup, idle, below 25%, 25–50%, and 50% or more of logical CPU capacity, on light and dark backgrounds."></p>

There is no numeric status-icon badge. The status menu and accessibility text report **N observed agent-associated processes in this window, including M no longer observed**. This includes filtered and historical contributors, not just busy workers. The bars remain a fixed width and use macOS template contrast without flashing or event animation.

Use **Diagnose CPU** while a slowdown is happening to find which processes consume the most CPU during a new short window. It cannot recover work that ended before you started. Start with the largest CPU-seconds contributors, then use their PID and session evidence to locate the workload in the live table. Check coverage and helper flags before attributing the load to an agent.

**Diagnose CPU** starts a separate finite investigation immediately, with three one-second waits plus scanning and provider-lookup time. Results rank the top ten by measured CPU-seconds and retain earlier contributors; they do not change the live table, history or icon. You can start while paused without resuming the live view. **Cancel** leaves the collecting state while owned work finishes; **Run again** waits for cleanup, discards the previous result and starts a fresh window. Each run may query providers again, independently of live monitoring’s listing cadence. **Back**, popover dismissal and detached-window closure discard the result; dragging the panel into a detached window keeps the run. Diagnosis rows have no actions. **Monitor helper** marks observed descendants of this instance; unobserved/reparented helpers and other monitor instances may remain unflagged. Their CPU stays in the totals.

The result starts with the window summary, followed by numbered contributors ranked by measured CPU-seconds. Each process has a separate card with its name and CPU-seconds emphasized; full identity, measurement coverage and attribution evidence remain underneath. Coverage explanations and guidance follow the contributors. Plain-text output, the TUI and clipboard copy use the same section boundaries with headings and blank lines.

For a completed diagnosis, **Copy report** copies the full readable report, including identities, timestamps, coverage and attribution qualifications, to the clipboard. It shows **Copied** or **Copy failed** and does not collect again or perform actions. Copying is unavailable while collecting, after cancellation/failure, or after dismissal.

Click outside the panel to dismiss it. The live icon keeps your selected sampling interval while closed, **100 ms by default**; the CPU value averages the actual time between samples. Reopening shows the latest snapshot immediately and resumes live table updates. Turn off **View options → Live menu bar icon** for a static three-bar icon and no closed-panel sampling; reopening in this mode takes a fresh baseline and waits one interval for measurements. The choice lasts until quit. Closing always cancels pending actions; a send already handed off may still have been accepted, so check any retained outcome before retrying. **Quit** exits and drains owned tasks.

Launch through the script so provider commands receive your shell's PATH. Finder-launched provider discovery, first-use Automation behavior, live message delivery and sustained energy use are not validated for the menu bar app. Quit an existing instance before rebuilding or changing PATH. See [development checks](development.md#menu-bar-app).

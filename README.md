<p align="center">
  <img src="docs/assets/agent-monitor.webp" alt="Agent Monitor: terminal prompt and resource activity bars" width="128" height="128">
</p>

<h1 align="center">Agent Monitor</h1>

<p align="center"><strong>Find the session behind the load.</strong></p>

Trace heavy CPU and memory usage to **Codex CLI and Claude Code sessions** on macOS.

When several coding agents are running, a busy `node`, `java`, or `python` process tells you little on its own. Agent Monitor connects heavy processes to their agent session, terminal, and project, so you can see where the work started. Then act on it: message the agent, jump to its terminal, or stop the process.

This README describes the current source build, which can be ahead of the [latest release](https://github.com/mbackschat/agent-monitor/releases/latest); newer controls, history and the menu bar app require a [source build](docs/installation.md#build-from-source).

**Current accounting limitation:** a busy agent build can be substantially underreported when workers start and finish between scans. Reliable identification and complete understanding of agent CPU and memory use is the project's highest priority; the current sampler does not yet meet it. See the [measurement limits](docs/usage.md#filters-and-measurements) and [active accounting work](PLAN.md#resource-accounting-priority). A low agent total does not establish that agents are causing little load.

## Features

- **Main contributors** — Mac and TUI start with the sessions contributing most CPU or memory. Recent bursts, unresolved work and quieter processes remain in quantified expandable summaries; filters never change totals.
- **Recent worker activity** — inspect a rolling 60-second target range of measured CPU, distinct workers, disappeared workers, sampled memory maxima and kernel-peak evidence. Expand session → executable → exact process; `java` and `node` workers group by observed executable basename, independent of PID.
- **Live terminal view** — request a 100 ms acquisition period by default (scan overruns remain visible); watch CPU and memory usage, sort processes, and open details without leaving your terminal. Stable order keeps existing rows in place and appends newcomers. Acquisition defaults to 100 ms; the display refreshes independently every two seconds, retaining CPU from workers that disappear between refreshes. Freeze the view to inspect a window.
- **Native menu bar app** — open a compact macOS panel for resource usage and session actions, with Pause/Resume and a separate **Diagnose CPU** investigation; three bold load bars keep collecting at the selected interval even while the panel is closed. Available from a source build.
- **Finite CPU diagnosis** — start with **d** in the TUI or **Diagnose CPU** in the Mac app. Rank a new observation window by measured CPU-seconds, recover compatible counters across temporary read gaps, and retain contributors that leave before it ends, without changing live-table values. The Mac app can copy the completed report for further investigation.
- **Compact history** — one strip for agent CPU, memory or heavy-process count, covering the last 10 minutes or one hour in both live views, updated with every collected report.
- **Pinned inspection** — keep a process or session at the top while its values update, in both native and terminal views. Missing targets stay marked until unpinned.
- **Memory burst context** — inspect the kernel footprint peak beside current memory; it survives freeing allocations but can reset on exec.
- **Session grouping** — bring related observed processes together and see their combined resource usage.
- **Adjustable filters** — change CPU and memory thresholds while the monitor runs.
- **Message the agent** — send a reviewed message to the process's verified Codex agent or Claude Code session; the inspected PID, CPU, memory and sample time are included automatically. Copy the prepared message from the native app.
- **Jump to the session's terminal** — bring the terminal running the agent to the front, selecting its tab in Terminal.app.
- **Stop a runaway process** — review and send SIGTERM to one process only.
- **Actions from scripts** — the same actions as `kill`, `message`, and `focus` commands, with confirmation or `--yes`.
- **Responsive layout** — use narrow or wide terminals, resize the details pane, and copy text with normal terminal selection.
- **Scriptable output** — print a colored report or stream JSONL schema version 6 to other tools.
- **Explicit uncertainty** — unknown or ambiguous sessions stay visible instead of being guessed.

## Install

Requires **Apple Silicon and macOS 27 or later**. With [Homebrew](https://brew.sh) installed:

```sh
brew install mbackschat/tap/agent-monitor
```

No Xcode, root access, or agent hooks are required. Update with `brew update` followed by `brew upgrade agent-monitor`.

Prefer a direct download or a source build? See the [installation guide](docs/installation.md).

## Quick start

For a finite CPU answer, use `agent-monitor diagnose cpu --json` (or omit `--json` for text). It takes a baseline and three one-second waits, then ranks the top ten current-user lifetimes by measured CPU-seconds, with independent host context and explicit coverage limits. Scans and session lookup add time. Start with `agent-monitor guide` for interpretation; [finite diagnosis](docs/usage.md#finite-cpu-diagnosis-and-local-guides) describes the output and exit codes.

The **TUI (terminal user interface)** is a live, full-window dashboard that runs inside your terminal. It refreshes in place and is controlled with the keyboard. Launch it from any directory:

```sh
agent-monitor --tui
```

The default **Main contributors** overview combines aligned CPU, memory and recent CPU columns with fixed-scale resource meters on wide terminals. Expand sessions into executable groups and individual workers. **Recent contributors** retains observed short-lived work; **More processes** accounts for the quieter population. Press **v** for the process view shown below, or **g** for session grouping there. The layout adapts to terminal width and the footer shows the available keys.

![Agent Monitor terminal UI showing five synthetic processes, CPU and memory usage, Codex and Claude sessions, and details for the selected process](docs/assets/tui-preview.svg)

*Illustrative process view with the selected process pinned (`@`) and details open. The text comes from the real layout renderer using entirely synthetic data; terminal colors and window decoration are illustrative. Press `g` to switch between this view and session groups.*

In the overview, use **↑ / ↓** to select, **← / →** to disclose details, **a** to show all session groups, **.** to pin a session, **c / m** to order by CPU or memory, **i** for details, **Enter** to inspect a current process without changing grouping, and **Page Up / Down** to scroll detail. **v** switches between overview and process inspection.

In the process view, use **↑ / ↓** to select, **← / →** to collapse/expand a session or process details, **Shift+← / Shift+→** to collapse/expand session groups at the current level, **g** to toggle grouping, **o** for Stable order, **h** to change the history metric, **t** for 10-minute/hour history, **< / >** to update less or more often, **.** to pin/unpin the selected row, **p** to pause/resume the view, **d** for a finite CPU diagnosis, and **q** to quit. The controls and current filters are shown in the terminal.

By default, totals include **all observed agent-associated processes**, including idle processes and missing resource measurements. The overview collapses quieter entries into quantified summaries; process and text views show individual rows. Display thresholds start at zero and never change totals. CPU at 100% means one fully occupied core.

## Choose what to show

Both interactive interfaces start in **Main contributors**. In the Mac app, **View options → Processes / Group by agent session** opens process inspection. In the TUI, **v** opens process inspection and **g** switches its grouping. `--group none|session` selects the text/process-view grouping; it does not disable the interactive overview. A session is one coding-agent conversation/run and the processes attributed to it.

| Setting | What it changes |
|---|---|
| **Main contributors** | Compact session overview with recent activity, executable groups and a quantified remainder. |
| **Processes** | A flat list of individual observed processes, each with its own CPU and memory values and session attribution. Use it to find the specific command consuming resources. Pinned session groups remain grouped at the top. |
| **Group by agent session** | Groups observed processes by attributed agent session or corroborated root session. Expand a group to inspect its processes. Counts and CPU/memory totals include all observed session members, independent of display filters; sampling can still miss work. The Mac app shows an unpinned one-process session directly as a process row. |
| **Sort** | Stable order keeps surviving rows in place and appends newcomers. CPU/Footprint/PID order ranks individual processes, or session groups by their totals/minimum PID. It does not change which processes qualify. |
| **CPU / Footprint thresholds** | Zero disables each filter independently. With both off, every observed process appears; otherwise a process must exceed at least one enabled threshold. Lower them to reveal lighter workloads; switching between Processes and Sessions does not change these filters. |
| **Interval** | Requested acquisition period, 100 ms by default. Scans run independently of resolution and display; overruns delay collection. This controls sampling cadence; the display refreshes independently every two seconds. |

Sessions are not projects: two sessions in the same directory remain separate, and one session can contain workloads in multiple directories. Unknown or ambiguous ownership stays separate rather than being guessed.

Shift+←/→ affects all displayed session groups when on a top-level row, or only the containing session when on a child process. It reveals/hides sibling rows without opening multiple process details. Expansion survives temporary filtering in both live views. Missing processes show no old measurements; a process's details reopen on return unless you explicitly change inspection. **Pin** keeps an identity at the top, including an unavailable placeholder when missing; **Pause** freezes the displayed measurements. See [grouping and expansion](docs/usage.md#session-grouping) for retention limits and [all controls](docs/usage.md#live-terminal-view) for details.

## Process actions

In the process view (`v` in TUI), select a process and press **k** to review a termination request or **s** to compose a message to its Codex or Claude Code session, or **f** to bring the session's terminal to the front. **Ctrl-Y** confirms the reviewed action; **Esc** cancels or returns to editing. Termination sends SIGTERM to that process only.

The monitor automatically includes the selected workload's PID, name, CPU, memory footprint and sample time, marking unavailable measurements explicitly, then shows the exact message before sending. Codex messages default to the verified **root agent**; **Tab** can select the attributed agent when it is distinct and reachable. Codex CLI must be on PATH with the session loaded on its default local app server; standalone Codex sessions and remote/custom app servers are not supported. Claude Code messages go to the attributed session's local inbox; Claude Code 2.1.224 or later must be on PATH, and the session may hold or refuse messages from other processes under its own settings. Acceptance does not confirm delivery or action. Focus selects the session's tab in Terminal.app; other terminal apps are only brought to the front, and macOS asks once for Automation permission. See [action controls and limits](docs/usage.md#process-actions).

## More ways to run

```sh
# Print one report
agent-monitor

# Choose your own thresholds
agent-monitor --tui --cpu 10 --memory-gb 0.5

# Stream reports as JSONL
agent-monitor --json --samples 0

# Explore all options
agent-monitor --help
```

See the [usage guide](docs/usage.md) for all keyboard controls, filters, session grouping, and output options.

## Menu bar app

Text, TUI and native headers show host occupancy beside measured CPU from your listed processes, including a count without CPU data. Newborn processes contribute their first observed interval; work never observed or after the last observation remains uncounted. “No data” means host occupancy is unavailable. See [measurement semantics](docs/usage.md#filters-and-measurements).

The source-built Mac app runs with `bash scripts/menubar.sh run`. Its default **Main contributors** view highlights meaningful CPU and memory use, with **Recent contributors**, **More processes** and **Unresolved / uncertain** summaries. CPU bars scale to one core and memory bars to physical RAM; tooltips and expandable coverage carry the explanations. Expand a session to inspect executable groups and individual workers, including workers no longer observed. **Show all** opens the remaining session population. **View options → Group by agent session / Processes** opens the existing process inspection view and verified actions.

The default grouped overview gives CPU prominence to groups above 25% of one core, while preserving the existing memory and recent-activity criteria; quieter work stays in quantified summaries. Acquisition defaults to 100 ms and display updates independently every two seconds. Recent activity targets 60 seconds within bounded memory; coverage explains shorter ranges and missing observations. Pause holds summary and worker detail. With the live icon enabled, history continues while closed; static mode starts a new history when reopened. The three status bars show unfiltered observed agent CPU; right-click for the qualified process census. The unqualified numeric badge has been removed. See [overview usage](docs/usage.md#main-contributors-and-recent-activity), [menu bar controls](docs/usage.md#menu-bar-app), and [validation limits](docs/development.md#menu-bar-app).

<p><img src="docs/assets/menubar-preview.webp" width="420" height="560" alt="Agent Monitor Main contributors view with current session CPU and memory, retained recent workers, and quantified collapsed population summaries."></p>

*Production native view with synthetic data. Coverage is expandable; process details and actions remain available through inspection. This offscreen capture does not establish live menu anchoring or physical keyboard/mouse behavior.*

## Options and defaults

With no options, `agent-monitor` prints one text report after a one-second accounting window, requesting a 100 ms acquisition period. Resolution and delivery can arrive later. With both thresholds zero, every observed process in scope is included, including unavailable measurements; interactive views can collapse lower contributors into quantified summaries. With filters enabled, **CPU OR memory must exceed an enabled threshold**; zero disables that resource filter. Only your user's agent-associated processes are included by default.

The following options control reports; diagnosis has fixed defaults and its own output flags.

| Option | Description | Default |
| --- | --- | --- |
| `--cpu <percent>` | CPU threshold; 100% means one occupied core. Zero disables this filter. Accepts nonnegative values. | `0` (%) |
| `--memory-gb <gb>` | Physical memory footprint threshold in decimal GB. Zero disables this filter. Accepts nonnegative values. | `0` (GB) |
| `--interval <seconds>` | Requested acquisition period, from 0.1 to 60 seconds; overruns delay collection. | `0.1` (seconds) |
| `--samples <count>` | Number of accounting windows; slow readers may receive combined reports. `0` runs until you quit. | `1`; `0` with `--tui` |
| `--tui`, `-tui` | Open the grouped contributor overview with a two-second display; requires interactive input and output. | Off; text reports |
| `--group <mode>` | Text/process-view grouping: `none` shows individual processes; `session` groups by launch session and totals all observed members. | `none` |
| `--json` | Emit JSONL schema version 6: one complete JSON object per report, including CPU context, contribution windows and historical contributors. | Off |
| `--json-schema` | Print the report's JSON Schema and exit without sampling. | Off |
| `--all-processes` | Include unrelated and unattributed processes; same-user scope and display thresholds still apply. | Off |
| `--commands` | Include command arguments in reports and details; arguments can contain secrets. | Off |
| `--no-color` | Disable colors in text, TUI and action output, like `NO_COLOR=1`; JSONL is never colored. Colors otherwise appear only on a terminal. | Off |
| `--version` | Print the installed version and exit. | — |
| `-h`, `--help` | Show command help and exit. | — |

| Command | Description |
| --- | --- |
| `guide [semantics\|diagnostics\|actions\|tui]` | Show local guidance without sampling or provider queries. |
| `diagnose cpu [--json]` | Baseline plus three one-second waits; top ten by CPU-seconds. Text by default; JSON is one diagnosis v1 document. |
| `diagnose cpu --json-schema` | Print the separate diagnosis schema without collection. |
| `kill --pid <pid> [--yes] [--no-color]` | Review and send SIGTERM to one process. |
| `message --pid <pid> --text <text> [--to root\|selected] [--yes] [--no-color]` | Review and message the process's Codex or Claude Code session. |
| `focus --pid <pid> [--no-color]` | Bring the terminal hosting the process's agent session to the front. |

The `kill` and `message` commands ask for confirmation in a terminal and need `--yes` in scripts; see [actions from the command line](docs/usage.md#actions-from-the-command-line) for exit statuses.

Choose only one of `--tui`, `--json`, or `--json-schema`. Session grouping is available for text and TUI output; `--group session` cannot be combined with `--json` or `--json-schema`.

## Current support

Agent Monitor supports Codex CLI and Claude Code terminal sessions. Claude Code's native installation has been checked with a real workload; npm-based Claude installations and real terminal Codex workloads have not yet been validated. Desktop conversation attribution and third-party agent plugins are not currently supported.

Background jobs whose launching shell has exited can reconnect to their live runtime through an inherited session marker and a matching Codex thread writer or Claude inbox. Missing or conflicting runtime evidence stays unresolved.

A Codex runtime holding multiple thread writers is labeled **shared runtime** when its own usage cannot be assigned to one thread. Its workloads can still have exact session labels; the shared runtime stays separate from their session totals.

Session associations identify **where a process was launched**. A shared daemon may later serve other sessions, so its current activity cannot always be assigned to the session that started it. Group totals cover the heavy processes shown, not every process in a session.

The monitor inspects only your user's processes and does not read conversation transcripts. Command arguments are hidden unless you request them with `--commands`.

## Adding more agents

Codex CLI and Claude Code use built-in attribution adapters. Each adapter recognizes its runtime and interprets its session markers and runtime evidence; shared monitoring handles resource measurement, process lifetimes and conflicting claims.

Messaging is a separate capability. Additional session inspection and external plugins remain future work; **there is no third-party plugin API**. See the [adapter architecture](docs/architecture.md#agent-attribution-adapters) for the implemented boundaries and extension limits.

## Documentation and contributing

- [Usage guide](docs/usage.md) — controls, actions, measurements, grouping, and JSONL.
- [Development guide](docs/development.md) — build, test, and verification commands.
- [Architecture](docs/architecture.md) — how collection, attribution, and presentation fit together.
- [Validation coverage](docs/development.md#validation-coverage) — live checks and known coverage limits.
- [Project plan](PLAN.md) — open follow-ups and scope decisions.
- [Research findings](docs/research/README.md) — dated evidence, sources, and unresolved empirical questions.

Bug reports and focused contributions are welcome. Include your macOS version, agent installation type, command used, and expected versus observed behavior. Remove session IDs, project paths, and command arguments you do not want to share from any attached output. For code changes, start with the [development guide](docs/development.md).

Run `bash scripts/doctor.sh` to check your development environment. Contributors using Codex CLI or Claude Code can optionally run `bash scripts/skills.sh install`, then `bash scripts/skills.sh check`. This installer downloads pinned Swift concurrency/testing and SwiftUI review/performance skills into the ignored `.skill-sources/` directory and exposes them to both agents; it does not install Agent Monitor or change global agent settings. See [skill setup](docs/development.md#skills-shared-by-codex-cli-and-claude-code).

The TUI preview is generated from synthetic data using the production layout renderer. After changing its appearance, run `bash scripts/preview.sh update` and review the image. CI checks for stale previews on every pull request; see the [preview workflow](docs/development.md#readme-preview).

## License

[MIT](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md) for dependencies, bundled components, and their licenses.

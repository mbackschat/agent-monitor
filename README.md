<p align="center">
  <img src="docs/assets/agent-monitor.webp" alt="Agent Monitor: terminal prompt and resource activity bars" width="128" height="128">
</p>

<h1 align="center">Agent Monitor</h1>

<p align="center">
  <a href="https://github.com/mbackschat/agent-monitor/actions/workflows/verify.yml"><img src="https://github.com/mbackschat/agent-monitor/actions/workflows/verify.yml/badge.svg?branch=main" alt="Verify build status"></a>
  <a href="https://github.com/mbackschat/agent-monitor/releases/latest"><img src="https://img.shields.io/github/v/release/mbackschat/agent-monitor" alt="Latest GitHub release"></a>
  <a href="https://github.com/mbackschat/agent-monitor/blob/main/LICENSE"><img src="https://img.shields.io/github/license/mbackschat/agent-monitor" alt="License"></a>
</p>

<p align="center"><strong>Find the session behind the load.</strong></p>

Agent Monitor shows which **coding agent, session and process** is using CPU or memory—and the working directory behind it. Inspect Codex CLI and Claude Code workloads in a terminal dashboard or native macOS menu bar app, without restarting agents or adding launch wrappers.

**Terminal dashboard**

![Terminal dashboard showing agent sessions, CPU history, memory and working directories](docs/assets/tui-preview.svg)

**macOS menu bar app**

<p><img src="docs/assets/menubar-preview.webp" width="620" height="560" alt="Native menu bar app showing contributor sessions, resource charts and expandable process groups."></p>

*Both previews use synthetic data. This README describes the current source build; the menu bar app requires a source build, and newer controls may be ahead of the [latest release](https://github.com/mbackschat/agent-monitor/releases/latest).*

## What you can do

- **Find the workload behind a spike.** Compare CPU and memory by agent session, then expand executable groups to individual processes and directories.
- **Inspect recent work.** See measured CPU from workers that disappeared between display updates, alongside current memory and known measurement gaps.
- **Follow a session.** Pin it, pause the display, sort by CPU or memory, and inspect full paths or arguments on demand.
- **Act on a verified target.** Jump to its terminal or review a termination request. Actions recheck process identity before delivery.
- **Use the output in scripts.** Print a report, stream JSONL, or run a finite CPU investigation with a structured result.

> **Measurement limit:** workers that start and finish between scans can be missed, substantially undercounting a busy build. A low reported total does not prove the agents are idle. See [measurement limits](docs/usage.md#filters-and-measurements).

## Install

Requires **Apple Silicon and macOS 27 or later**. With [Homebrew](https://brew.sh):

```sh
brew install mbackschat/tap/agent-monitor
```

Update with `brew update && brew upgrade agent-monitor`. Release binaries need neither Xcode nor root access. For direct downloads or the current development version, follow the [installation guide](docs/installation.md).

## Quick start

Open the terminal dashboard from any directory:

```sh
agent-monitor --tui
```

Start with **Main contributors**. Expand a session to find the command using resources, then open Details for its full identity and working directory.

| Task | Key |
| --- | --- |
| Select / expand / collapse | ↑ ↓ / → / ← |
| Sort by CPU / memory | `c` / `m` |
| Open Details | `i` or Enter |
| Pin / pause | `.` / `p` |
| Switch to process view / toggle grouping | `v` / `g` |
| Keyboard help / diagnostics | `?` / `D` |
| Investigate CPU / quit | `I` / `q` |

Keys depend on the active view; **?** shows the available controls. See the [usage guide](docs/usage.md) for scrolling, filters, chart ranges and process actions.

### Menu bar app

From a [source checkout](docs/installation.md#build-from-source), run:

```sh
bash scripts/menubar.sh run
```

Click a contributor to select it, the chevron to expand it, or **ⓘ** to inspect it. The **…** menu offers actions for its current processes. Sort with the CPU and Memory headings, drag the bottom edge to resize, and use the footer for Help and Diagnostics. [Menu bar controls](docs/usage.md#menu-bar-app) covers the remaining interactions.

### Reports and automation

```sh
# Print one report
agent-monitor

# Investigate CPU over a short, finite observation window
agent-monitor diagnose cpu --json

# Stream reports as JSONL until stopped
agent-monitor --json --samples 0

# Show local guidance or command help
agent-monitor guide
agent-monitor --help
```

Diagnosis takes a baseline plus three one-second waits, then ranks the top ten process lifetimes by measured CPU-seconds. Collection adds some time. Omit `--json` for a readable report; see [diagnosis output and exit codes](docs/usage.md#finite-cpu-diagnosis-and-local-guides).

## Reading the numbers

- **CPU:** 100% is one CPU-second per elapsed second. Multi-core workloads can exceed 100%.
- **Memory:** current physical footprint; sampled maxima and kernel-peak evidence are available in Details.
- **Totals:** include all observed processes in scope, including those hidden by display filters. Unknown ownership and missing measurements stay explicit.
- **Recent counts:** `java ×17` represents 17 distinct process lifetimes in that group’s displayed and retained recent data. `1 process` below it means one is currently observed in the group—not 17 running JVMs.
- **Charts:** show interval averages on a fixed range. Warning-colored bars (↑ in monochrome) indicate values above the range; use `b` to change it. Dots mean no measurement, not zero.

By default, acquisition is requested every 100 ms and the interactive display refreshes every five seconds. Slow scans can exceed the requested interval. [Measurement semantics](docs/usage.md#filters-and-measurements) explains coverage, history and attribution.

## Support, privacy and limits

Agent Monitor supports Codex CLI and Claude Code terminal sessions. Claude’s native installation has been checked with a real workload; npm-based Claude and live terminal Codex validation remain open. Desktop conversations and third-party attribution plugins are not supported. Shared runtimes and ambiguous ownership are shown separately. Attribution identifies launch ownership; shared daemons may later serve other sessions.

Monitoring stays local: no provider CLI launches, Internet connections or transcript reads. Session names from provider listings and provider messaging are unavailable. Arguments are hidden unless requested with `--commands` or inspected on demand. Normal monitoring keeps bounded history in memory and writes no automatic process-data log.

Native performance, short-worker coverage, a process-wide memory ceiling and broader keyboard/accessibility acceptance remain open. See [validation coverage](docs/development.md#validation-coverage) and the [project plan](PLAN.md) for evidence and remaining work.

## Options and defaults

With no options, `agent-monitor` prints one report after a one-second accounting window. It includes your user’s agent-associated processes by default. `--tui` runs until quit; `--all-processes` expands scope to all processes owned by your user.

<details>
<summary>Report options</summary>

| Option | Purpose | Default |
| --- | --- | --- |
| `--cpu <percent>` | Display CPU threshold; `0` disables it. | `0` |
| `--memory-gb <gb>` | Display footprint threshold in decimal GB; `0` disables it. | `0` |
| `--interval <seconds>` | Requested acquisition period, 0.1–60 seconds; adaptive visible maximum when enabled. | `0.1` |
| `--samples <count>` | Accounting windows; `0` runs until stopped. Delivery may combine windows. | `1`; `0` with TUI |
| `--tui`, `-tui` | Interactive contributor overview; requires a terminal. | Off |
| `--tui-chart-style <style>` | `auto`, `stacked` or `compact`; requires TUI. Apple Terminal auto falls back for Meslo or unknown fonts. | `auto` |
| `--adaptive-sampling` / `--no-adaptive-sampling` | Activity-based acquisition; mutually exclusive, TUI only. | Off |
| `--sampling-minimum <seconds>` | Adaptive minimum, at least 0.1 and no greater than `--interval`; TUI only. | `0.1` |
| `--sampling-window <seconds>` | Adaptive activity window, 1–300 seconds; TUI only. | `60` |
| `--inspection-observations` | Experimental extra discovery while the TUI is live and unpaused; cost/benefit unvalidated. | Off |
| `--group none\|session` | Grouping for text and process views; does not disable the interactive overview. | `none` |
| `--json` | Stream report JSONL, schema version 1. | Off |
| `--json-schema` | Print the report schema without sampling. | Off |
| `--all-processes` | Include unrelated and unattributed same-user processes. | Off |
| `--commands` | Include arguments, which may contain secrets. | Off |
| `--no-color` | Disable colors; also honors `NO_COLOR`. TUI retains emphasis and selection. | Off |
| `--version` | Print the installed version. | — |
| `-h`, `--help` | Show command help. | — |

Filters match CPU **or** memory above an enabled threshold and never redefine totals. Sampling minimum/window options do not themselves enable adaptation. Choose one of `--tui`, `--json` or `--json-schema`; JSON modes cannot be combined with `--group session`.

</details>

<details>
<summary>Commands and actions</summary>

| Command | Purpose |
| --- | --- |
| `guide [semantics\|diagnostics\|actions\|tui]` | Read local guidance without collecting data. |
| `diagnose cpu [--json]` | Run a finite CPU investigation; JSON is a separate diagnosis document. |
| `diagnose cpu --json-schema` | Print the diagnosis schema without collection. |
| `kill --pid <pid> [--yes] [--no-color]` | Review and send SIGTERM to one verified process. |
| `focus --pid <pid> [--no-color]` | Bring the process’s agent terminal to the front. |
| `message [--no-color]` | Report that provider messaging is unavailable, without sending anything. |

Termination requires confirmation, or explicit `--yes` in scripts. Terminal.app focus can select the session’s tab; other supported terminals are brought to the front. macOS may request Automation permission. See [action behavior and exit statuses](docs/usage.md#actions-from-the-command-line).

</details>

## Documentation and contributing

- [Usage](docs/usage.md) — controls, measurements, actions and JSONL.
- [Development](docs/development.md) — prerequisites, tests, synthetic previews and optional coding-agent skills.
- [Architecture](docs/architecture.md) — sampling, attribution adapters and presentation boundaries.
- [Product contract](docs/product.md) and [project plan](PLAN.md) — priorities and unfinished work.
- [Research](docs/research/README.md) — retained measurements and technical investigations.

Bug reports and focused contributions are welcome. Include your macOS version, agent installation, command and expected versus observed behavior. Remove sensitive paths, session IDs and arguments from attached output. For code changes, start with `bash scripts/doctor.sh` and the [development guide](docs/development.md).

## License

[MIT](LICENSE), with [third-party notices](THIRD_PARTY_NOTICES.md) for bundled dependencies.

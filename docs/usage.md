# Usage guide

Follow the [installation guide](installation.md), then start with the [README quick start](../README.md#quick-start). The commands below use the installed `agent-monitor` executable and work from any directory.

## Live terminal view

```sh
agent-monitor --tui
agent-monitor --tui --group session
```

`--tui` (also accepted as `-tui`) watches continuously unless you supply a `--samples` limit. It requires interactive stdin and stdout and cannot be combined with JSON output. Set `NO_COLOR=1` to disable colors.

| Key | Action |
| --- | --- |
| ↑ / ↓ | Select a row |
| Enter | Expand/collapse a session or open/close process details |
| `g` | Toggle session grouping |
| `c` / `m` / `p` | Sort by CPU, memory footprint, or PID |
| `r` | Reverse the sort direction |
| `1` / `2` | Lower/raise the CPU threshold by 10 percentage points |
| `3` / `4` | Lower/raise the memory threshold by 1 decimal GB |
| `[` / `]` | Scroll process details |
| `-` / `+` | Shrink/grow the details pane by 5 percentage points |
| `0` / `9` | Minimize/maximize the details pane |
| `=` | Restore the chosen details split |
| `q` / Ctrl-C | Quit |

Selection follows the process across sorting and refreshes. Details start minimized; opening them uses an initial 50% split. The adjustable split ranges from 10–90%, subject to available terminal space. Minimizing or maximizing does not overwrite your chosen split.

The layout adapts to terminal size. Narrow views abbreviate names and session IDs and omit the terminal/project column; open details for the full information. The process column contains names only, with executable paths and optional command arguments in details. Very small windows show a resize hint.

To copy text, drag-select it and use your terminal's Copy command (usually Command-C on macOS). Navigation is keyboard-driven; mouse selection belongs to the terminal. Whether selection survives a refresh depends on your terminal.

## Filters and measurements

By default, findings must exceed **25% CPU OR 1 GB physical footprint**. Only agent-associated processes appear; `--all-processes` also includes unrelated and unattributed processes owned by your user. Unknown or ambiguous agent sessions remain visible.

- CPU is averaged over the elapsed interval between snapshots. **100% means one fully occupied core**, so a multithreaded process can exceed 100%.
- Memory is a snapshot of physical footprint in **decimal GB**. Footprint includes memory accounting that RSS omits.
- `*` marks an exceeded process threshold. Missing measurements are unavailable, not zero.

```sh
agent-monitor --tui --cpu 40 --memory-gb 0.5
agent-monitor --all-processes --cpu 10
```

In the TUI, both thresholds clamp at zero. New settings apply at the next sample and show as pending until applied. Lowering a threshold can reveal previously omitted processes without restarting the monitor. An empty list means no matching heavy processes were found in that sample; try lowering the thresholds.

## Session grouping

`--group session` groups text or TUI output by launch session. In the TUI, press `g` to switch modes. Groups start collapsed; Enter expands a group, and Enter on a process opens its details.

Groups show the project, session, process count, and CPU/memory totals of **displayed heavy processes only**. They do not represent the entire session's resource use. `~` marks a partial total when measurements are missing. CPU/memory sorting orders groups by their totals; PID sorting uses each group's lowest displayed PID.

Unresolved or ambiguous processes stay separate even when they share a project or runtime. Session evidence identifies launch origin: a shared Gradle, Kotlin, or MCP daemon may later serve other sessions. See [attribution evidence](architecture.md#attribution-evidence-and-inspection-scope) for the exact interpretation and inspection scope.

## Text and JSONL output

With no options, the monitor takes a baseline, waits one second, and prints one report. `--samples 0` watches until Ctrl-C; `--interval` controls the wait between scans (0.1–60 seconds). Each text report includes a UTC timestamp.

```sh
# Continuous text reports every two seconds
agent-monitor --samples 0 --interval 2

# Three machine-readable reports
agent-monitor --json --samples 3

# Print the report schema without sampling
agent-monitor --json-schema
```

JSONL contains one complete, compact JSON object per line/report. It retains the flat process list and full attribution evidence, including ambiguous candidate IDs. `--group session` is incompatible with `--json` and `--json-schema`.

`--commands` includes command arguments in reports and process details. Arguments can contain credentials or other sensitive values and are omitted by default. Session IDs and project paths can still appear without this option.

For the complete option reference and defaults, run `agent-monitor --help`.

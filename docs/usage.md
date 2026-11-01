# Usage guide

Find which **coding agent, session and process** is using CPU or memory, with the workload's working directory beside it. [Install Agent Monitor](installation.md), then choose an interface:

```sh
agent-monitor --tui             # Interactive terminal overview
agent-monitor diagnose cpu     # Short, finite CPU investigation
agent-monitor --json --samples 3
```

For the source-built Mac app, run `bash scripts/menubar.sh run` from the checkout. For a complete topic index, see [usage topics](usage/README.md).

## Reading responsibility and retaining data

Read identity, executable, working directory and contribution together. Session labels use locally verified provider/session IDs; unknown ownership stays explicit. Normal monitoring retains bounded data in memory and does not automatically record process data to disk.

[Understand identity and retention](usage/overview.md#reading-responsibility-and-retaining-data).

## Finite CPU diagnosis and local guides

Run `agent-monitor diagnose cpu` during a slowdown. It takes a baseline plus three one-second waits and native scans, then ranks the ten largest measured current-user contributors by CPU-seconds. It includes nonagents, retains earlier observed work and reports coverage limits. `agent-monitor guide` opens the local reference without sampling.

[Diagnosis commands, ranking, JSON and exit statuses](usage/cli.md#finite-cpu-diagnosis-and-local-guides).

## Live terminal view

Start `agent-monitor --tui`. Select with ↑/↓, expand with →, inspect with `i`, page with `u`/`d`, pause with `p`, and open keyboard help with `?`. Use `H` to hide/show no-longer-observed rows; totals and history stay unchanged.

[Terminal controls and workflows](usage/terminal.md) · [Chart and layout reference](usage/terminal-display.md).

## On-demand help and diagnostics

In the TUI, `?` opens shortcuts, `G` opens the glossary, `D` explains existing measurements, and `I` starts a new CPU investigation. The Mac footer provides separate Help, Keyboard Shortcuts and Diagnostics controls.

[Terminal help](usage/terminal.md#help-glossary-and-passive-diagnostics) · [Mac help](usage/mac.md#help-and-diagnostics) · [Shared definitions](usage/overview.md#glossary-and-diagnostics).

## Process inspection

Open Details for full paths, exact identity and attribution evidence. Read arguments explicitly: choose **Read arguments** on Mac or press `x` in TUI process Details. This performs a fresh read, including while paused; it does not add arguments to history.

[Argument inspection and its limits](usage/actions.md#process-inspection).

## Process actions

In the TUI, switch to process view with `v` before requesting termination or terminal focus. Termination reviews a frozen target and rechecks it before sending SIGTERM. Terminal focus requests the hosting terminal; it never types or runs commands there. Messaging is unavailable under the offline runtime requirement. An accepted action does not prove exit or physical focus.

[Review a process action](usage/actions.md#process-actions) · [Mac contributor and batch actions](usage/mac.md#inspect-and-act-on-a-contributor).

### Actions from the command line

Use `agent-monitor kill --pid <PID>` or `agent-monitor focus --pid <PID>`. Each resolves the current lifetime afresh; a PID copied from a previous report is not a frozen action target.

[CLI confirmations and exit statuses](usage/actions.md#actions-from-the-command-line).

## Main contributors and recent activity

The default overview highlights significant CPU and memory contributors and keeps other measured work in quantified summary groups. Expand a session to see its executables and individual workers. **Recent** work can include processes that are still running; **no longer observed** does not mean confirmed exit.

[Ranking, counts, recent history and chart range](usage/overview.md#main-contributors-and-recent-activity).

## Filters and measurements

CPU uses 100% for one fully occupied core. Memory is physical footprint in decimal GB. Display thresholds default to zero; changing them filters rows, not measured session totals. Missing measurements are unavailable, not zero. Polling can miss short-lived workers and their final CPU.

[Units, filters, attribution and coverage](usage/overview.md#filters-and-measurements).

## Session grouping

Use `--group session` for text output and the interactive process view. In the TUI, `v` switches to processes and `g` changes grouping. Group totals include observed members hidden by display filters; CWD explains a workload but does not establish ownership.

[Grouping, disclosure, counts and local attribution](usage/cli.md#session-grouping).

## Text and JSONL output

With no options, Agent Monitor prints one resolved one-second accounting window. `--samples 0` streams until interrupted. JSONL has one complete flat report per line, with separate observed and filtered findings; it cannot be combined with session grouping.

[Report examples and JSONL contract](usage/cli.md#text-and-jsonl-output).

## History strip

The compact strip defaults to observed-agent CPU over ten minutes. In the TUI, `h` changes the metric and `t` changes the range; on Mac, use **CPU · 10m**. It is separate from the detailed recent-contributor window and does not change sampling or filters.

[History metrics, gaps and retention](usage/overview.md#history-strip).

## Menu bar app

Click the load icon to open the native panel. Select a row to inspect it, use its process-count/chevron button to expand children, and open **ⓘ** for Details. **View options** controls views, filters and sampling. Drag the top edge to detach the panel or the bottom grip to resize it.

[Mac workflows, status icon, diagnosis and lifecycle](usage/mac.md).

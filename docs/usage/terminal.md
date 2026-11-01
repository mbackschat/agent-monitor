# Use the terminal interface

Start with `agent-monitor --tui`. Use the contributor overview to find the load, then open Details or switch to the process view for a closer inspection.

[Usage guide](../usage.md) · [All usage topics](README.md)

```sh
agent-monitor --tui
agent-monitor --tui --group session
agent-monitor --tui --adaptive-sampling --interval 1 --sampling-minimum 0.1 --sampling-window 60
```

`--tui` (also accepted as `-tui`) watches continuously unless you supply a `--samples` limit. It requires interactive stdin and stdout and cannot be combined with JSON output. Use `--no-color` or set `NO_COLOR=1` to disable colors while retaining reverse-video selection, bold headings, underlined Help keys and solid monochrome chart cells. Footer rules and textual warning markers remain visible.

## Keyboard controls

These are the current source-build keys. An installed release can differ; use its on-screen help or `agent-monitor guide tui`.

### Navigate and inspect

| Key | Action |
| --- | --- |
| `v` / `a` | Switch overview/process view / select All or Main contributors |
| Return | Open Details for the selected row in the current view; repeated Return keeps it open |
| `i` | Show/hide selected details in either view without folding children |
| `u` / `d` or Ctrl-U / Ctrl-D | Move half a page up/down in the active table, Details or reference page |
| Space | Move half a page down; `p` remains pause/resume |
| Page Up / Page Down | Move a full page up/down in the focused pane |
| ↑ / ↓ | Select a row, or scroll focused Details |
| Tab | Switch focus between table and open Details |
| ← / → | Collapse/expand children; process leaves do not expand |
| Shift+← / Shift+→ | Collapse/expand displayed session groups at the current level |
| `g` | Toggle session grouping |

### Find help and diagnose load

| Key | Action |
| --- | --- |
| **?** | Open available keyboard shortcuts |
| **G** | Open the metric glossary |
| **D** | Open passive diagnostics |
| **I** | Start a finite CPU diagnosis immediately; three one-second waits plus native scans and metadata reads |

### Sort, filter and change history

| Key | Action |
| --- | --- |
| `c` / `m` / `n` | Sort the current view by CPU or memory; PID applies only in process views |
| `o` | Stable order in the current view: keep surviving sibling positions and append arrivals (process-view default) |
| `r` | Reverse the current view’s sort direction; no effect in Stable order |
| `P` / `S` / `O` | Fold Pinned / Sessions / Other observed work in the contributor overview |
| `b` | Cycle the fixed contributor CPU chart range; no effect in process views |
| `H` (Shift+H) | Hide/show no longer observed rows in the contributor overview; measured totals and history stay unchanged |
| `h` | Cycle history: CPU (default), memory, heavy-process count |
| `t` | Switch history between the last 10 minutes (default) and one hour |
| `1` / `2` | Lower/raise the CPU threshold by 10 percentage points |
| `3` / `4` | Lower/raise the memory threshold by 1 decimal GB |

### Sampling, pins, pause and Details

| Key | Action |
| --- | --- |
| `<` / `>` | Increase/decrease the requested period, or visible maximum in adaptive mode: 0.1, 0.25, 0.5, 1, 2, 5, 10, 30 or 60 seconds; skip invalid steps |
| `.` | Pin/unpin the selected process or session, including absent targets; values keep updating |
| `U` | Unpin all processes and sessions in both views |
| `p` | Pause/resume the view; sampling continues and resuming shows the latest data |
| `[` / `]` | Scroll visible details in either view by one line |
| `-` / `+` | Shrink/grow the details pane by 5 percentage points |
| `M` | Maximize Details; `i` closes it |
| `=` | Restore the chosen details split |

### Request an action or quit

For termination or terminal focus, first press `v` to switch from the overview to process view. Select a current process, or a session group for focus. These actions are unavailable in the contributor overview.

| Key | Action |
| --- | --- |
| `k` | Review SIGTERM for the selected process |
| `s` | Explain why messaging is unavailable in local-only operation |
| `f` | Bring the terminal hosting the selected process's or group's agent session to the front |
| `q` / Ctrl-C | Quit |

## Keep contributors pinned

Pins stay first in pin order, independently of sorting. `★` marks a pinned row and `>` independently marks the selection, including without color. A selected pin shows `>★`; a missing pinned target keeps both indicators. A pinned group's expanded children use arrival order in Stable order and PID order in other sorts. If a target leaves the current heavy results, its placeholder remains with **Not in current results**; this does not prove it exited, and no old measurements or actions are offered.

The same process lifetime or session can return automatically; PID reuse cannot replace a pin. `.` removes the selected pin even when its target is absent. `U` clears pins in both the overview and process view; the Mac app also offers **View options → Unpin all**. Each view admits at most 256 pins and 64 KiB of retained identity/label text. Reaching either limit refuses a new pin visibly; existing pins are never evicted, and removal remains available.

Pins last until unpinned or the monitor quits, and native pins also survive closing/reopening the panel. A process pinned separately is omitted from its group's child rows; group totals still cover its full heavy membership. Pinned groups retain their identity when switching to flat mode.

## Choose a chart style

`--tui-chart-style auto|stacked|compact` selects one mode for all contributor CPU charts; `auto` is the default. In Apple Terminal, auto attempts a read-only lookup of the tab matching the output TTY only when Automation permission already exists. Menlo, Source Code Pro, Monaco and Bitstream Vera Sans Mono family-name matches retain stacked charts; Meslo (including Powerline/Nerd Font variants), unrecognized fonts and unavailable lookup use compact charts.

No permission is requested or terminal settings changed. Lookup is skipped inside tmux/screen or SSH; Apple Terminal then uses compact.

Other terminal apps retain stacked charts because their glyph rendering can differ; force `compact` if seams appear, or `stacked` if your font/spacing renders continuous bars. The choice is made once at startup. Process-view history already uses a single-row sparkline. Native Mac charts are unchanged.

```sh
agent-monitor --tui --tui-chart-style compact
agent-monitor --tui --tui-chart-style stacked
```

## Scroll the table and Details

Overflowing tables have a right-edge scrollbar: the thumb shows the visible share, and ↑/↓ mark hidden content above/below. It includes expanded children and wrapped lines, disappears when everything fits, and works without color. `u`/`d` scroll the table by half its visible height while keeping selection in view; Tab directs paging to the table or open Details. Tables, Details and reference pages also show their visible range.

Footer controls stay at the terminal bottom even when Details has little content. **D diagnostics !** indicates measurement warnings; the read-failure counts and technical explanation stay inside Diagnostics. Apple Terminal may send Shift-Space identically to Space; use `u` or Ctrl-U for half-page up. Encoded Shift-Space remains supported on terminals that transmit the modifier.

## Read process counts and hide past rows

Executable headings show the name without a population multiplier in both TUI and Mac. Current process counts remain below the heading; Details keeps recent worker counts. In the TUI, `H` hides or restores no-longer-observed rows, with an active-filter reminder showing how many rows are hidden. Mac exposes the same filter in **View options → Display filters → Hide no longer observed**. Neither filter changes measured totals or CPU history.

## Sampling and pause

Text, JSONL and TUI reports default to fixed 100 ms acquisition. Acquisition is independent of metadata work and display; overruns delay the next scan without overlapping or catch-up scans, and delivery can lag acquisition. An explicit `--interval` changes the fixed period, or the visible maximum in adaptive mode.

Adaptive sampling is off by default. When enabled, it starts at the minimum, returns there on qualifying activity or missing required evidence, and relaxes toward the visible maximum during low activity.

| Option | Meaning and limits |
| --- | --- |
| `--adaptive-sampling` | Enable adaptation; requires `--tui`. |
| `--no-adaptive-sampling` | Use fixed `--interval`; mutually exclusive with adaptation. Even an explicit disabling flag requires `--tui`. |
| `--sampling-minimum` | Default 0.1 seconds; at least 0.1 and no greater than the visible maximum. Setting it does not enable adaptation. |
| `--sampling-window` | Activity window: default 60 seconds, range 1–300. Setting it does not enable adaptation. |

All adaptive settings require `--tui`. Faster/slower keys adjust the visible maximum, skipping steps below the configured minimum; there are no additional keys for adaptive settings. The shortest selectable period is 100 ms. Slower acquisition can miss short-lived workers; see the [adaptive contract](../architecture.md#adaptive-acquisition).

The header shows the view, active sort direction, requested period/adaptive maximum, display interval and update count. `PAUSED` marks a frozen report. Collection and activity detection continue while paused; selection, sorting, Details and actions still work, but actions recheck the live process. Threshold changes remain pending until resume. Selection follows process identity across refreshes and sorting.

## Resize Details

Details start minimized; opening them uses an initial 50% split. The adjustable split ranges from 10–90%, subject to available terminal space. Minimizing or maximizing does not overwrite your chosen split. The divider’s `pane N%` is the requested share of the content area for details, not CPU usage.

## Read narrow layouts

The layout adapts to terminal size. Process leaves have a leading `i` inspection marker, distinct from expandable session controls `▸`/`▾`; select the row and press `i` to show or hide its details. The footer uses the same view, grouping, Help, pause and quit wording across report modes; **?** lists the complete controls. Below 85 columns, process inspection uses two linked lines: agent/session and process name above PID/count, CPU, memory and CWD. Session IDs use eight characters; names and paths abbreviate as needed, with full information in details.

Matching directory suffixes gain enough leading components to distinguish workloads in group headings; if the terminal still cannot fit them, an ellipsis marks truncation and details provide the full paths. The viewport keeps each identity/resource pair together; very small panes show a resize hint.

Wide flat rows reserve aligned executable, agent/session and CWD columns even when resource values grow; matching directory basenames remain disambiguated. Historical `[past]` labels stay inside the executable cell, and truncated text has an ellipsis. Terminal context, executable paths and optional command arguments remain in details.

## Copy terminal text

To copy text, drag-select it and use your terminal's Copy command (usually Command-C on macOS). Navigation is keyboard-driven; mouse selection belongs to the terminal. Whether selection survives a refresh depends on your terminal.

## Run a short CPU investigation

In CPU diagnosis, **↑/↓** and **Page Up/Down** scroll the fixed result, **x** cancels, **Esc** returns to the live report, and **I** runs again. Rerun discards the old result immediately and remains disabled until the preceding run finishes cleanup. After Back, the live footer shows **CPU cleanup** in place of **I investigate** until `I` is available again; like that hint, it is omitted when the footer is too narrow. Compact live footers retain **? help**; timing is explained in the collecting view and `guide tui`.

Runs use native observations without provider queries. The view ranks the top ten by measured CPU-seconds, including earlier contributors; the live table, history and paused state stay independent. Diagnosis rows have no actions. Below 40×8, starting and rerunning are disabled while Cancel, Back and quit remain available. **Monitor helper** flags observed descendants of this monitor only; reparented/unobserved helpers and other monitor instances may be unflagged, and their CPU remains in totals.

## Help, glossary and passive Diagnostics

In the TUI, press **?** for available keyboard shortcuts, **G** for Help & glossary and **D** for passive Diagnostics; use **u/d** or **Ctrl-U/Ctrl-D** for half-page up/down, **Space** for down, **Page Up/Down** for a full page or **↑/↓** and **[ / ]** for one line and **Esc** to return. These pages preserve the current selection, inspection and paused report. The compact footer exposes Help, and measurement warnings link to Diagnostics. Uppercase **I** starts a new finite CPU diagnosis; uppercase **D** only displays existing measurements and their limitations.

For chart symbols and measurement meaning, see [the overview](../usage/overview.md). For exact layout, color and compact-width behavior, see the [terminal display reference](../usage/terminal-display.md).

## Experimental between-scan observations

`--tui --inspection-observations` opts into experimental between-scan discovery while the TUI is live and unpaused. Complete acquisition and the five-second display stay unchanged. Coverage details show a structured **Between-scan reads** row; a warning appears if more than half of opportunities were skipped.

The feature is off by default, is unavailable in ordinary text/JSONL collection and has no Mac control yet.

A [bounded local comparison](../research/cpu-accounting.md#bounded-inspection-comparison-retry--2026-10-26) found better 50 ms-worker capture but persistent shorter-worker loss and cost above the trial target. Sustained coverage and cost acceptance remain open. It does not recover final-exit CPU or guarantee discovery of short workers; see the [inspection contract](../architecture.md#supplemental-inspection-observations).

# Usage guide

Follow the [installation guide](installation.md), then start with the [README quick start](../README.md#quick-start). The commands below use the installed `agent-monitor` executable and work from any directory.

## Live terminal view

```sh
agent-monitor --tui
agent-monitor --tui --group session
```

`--tui` (also accepted as `-tui`) watches continuously unless you supply a `--samples` limit. It requires interactive stdin and stdout and cannot be combined with JSON output. Use `--no-color` or set `NO_COLOR=1` to disable colors.

| Key | Action |
| --- | --- |
| ↑ / ↓ | Select a row |
| Enter | Expand/collapse a session or open/close process details |
| `g` | Toggle session grouping |
| `k` | Review SIGTERM for the selected process (unreleased) |
| `s` | Compose a message to a verified Codex or Claude Code recipient (unreleased) |
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

## Process actions (unreleased)

These controls are available in the current source checkout, not the v0.1.0 release/Homebrew package. Expand a session group and select an individual process before using either action. Opening a confirmation freezes its process identity: subsequent sorting, refreshes, and filter changes cannot retarget it.

**Terminate:** press `k`, inspect the PID, executable and session, then press Ctrl-Y to send SIGTERM. Esc cancels. Only the selected process is signaled, including when you explicitly select an agent runtime; children and process groups are not signaled automatically. SIGKILL is not offered. The process must still have the same PID, start time and executable and belong to your user. macOS identity checks and PID-based signaling are not atomic, so a small race remains. “SIGTERM accepted” does not mean the process exited.

**Message:** press `s` to verify recipients and open the composer. For Codex, Root agent is the default and Tab cycles to Selected agent when distinct; a Claude Code session has one recipient. An unavailable root remains disabled rather than silently switching to a child. Type or paste up to 4,000 characters; Backspace edits the end. Bracketed paste preserves newlines and cannot activate commands; terminal control characters are removed. Enter opens the full message review, Ctrl-Y sends it, and Esc returns to editing or cancels. ↑/↓ and Page Up/Down scroll the panel. Ctrl-C quits from any panel; `q` is ordinary message text while composing.

**Focus:** press `f` to bring the terminal hosting the selected process's agent runtime to the front. The runtime, not the workload, is the target because agent tool subprocesses often have no terminal. In Terminal.app the tab on the runtime's terminal device is selected, its window is unminimized and ordered front, and Terminal is activated; the result panel names the device. Other terminal and editor apps found above the runtime are only asked to come to the front, so another of their windows may show. Sessions under tmux, screen, or ssh, and background runtimes without a terminal, report that nothing was focused. On first use macOS asks whether the terminal running Agent Monitor may control Terminal; that Automation grant applies to everything run in that terminal, and it can be revoked in System Settings › Privacy & Security › Automation. Since macOS 14 activation is a request, so macOS may keep another app in front. Focus never types into, runs commands in, or reads the target terminal.

The generated prefix identifies the selected workload, for example:

```text
[Agent Monitor: selected process PID 42001 (swift-frontend)]
Please investigate why this process is using so much CPU.
```

The prefix uses the workload PID, not the recipient's runtime PID. Both target and message remain visible in the scrollable review. Immediately before sending, the monitor rechecks live provider routing, process lifetime, executable and attribution. An exited/reused process, changed attribution or changed recipient availability requires reopening the composer. Historical detached ancestry, ambiguous sessions and unverified runtimes cannot be messaged.

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

Each command reads the process's current lifetime and attribution, independently of the display thresholds, and applies the same identity, recipient and runtime checks as the TUI. `kill` and `message` print the target, and for messages the recipient and the exact text with its PID prefix, then ask `[y/N]`. Without an interactive stdin they refuse unless `--yes` is given, so a script must opt in explicitly. `--to selected` addresses the Codex agent that launched the process instead of the root; a Claude Code session has one recipient. `focus` needs no confirmation.

| Exit status | Meaning |
| --- | --- |
| `0` | Accepted: SIGTERM sent, message handed over, or terminal focused. Exit, delivery and action are not confirmed. |
| `1` | Nothing was done: refused, cancelled, not found, or failed before sending. |
| `2` | `message` only: the message may have been accepted although that could not be confirmed. Check the session before retrying. |

JSONL output has no action commands.

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

Text reports and the `kill`, `message` and `focus` commands use colors only when their output goes to a terminal: the report header in blue, process lines and unresolved sessions in yellow, secondary details in gray, accepted results in green and errors in red. Pipes and files get plain text, and `--no-color` or `NO_COLOR=1` turns colors off everywhere. JSONL is never colored; `--no-color` is accepted with `--json` and has no effect there.

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

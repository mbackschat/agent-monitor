# Inspect and act on a process

Open Details to inspect an exact process lifetime. Termination and terminal focus recheck the live target; a successful request does not prove exit or physical focus.

[Usage guide](../usage.md) · [All usage topics](README.md)

## Process inspection

**On-demand arguments:** open a current process inspector and choose **Read arguments** on Mac, or press `x` in TUI process details (`x` again hides them). The numbered argument list preserves argument boundaries. This reads the process now, even while the view is paused; the inspection shows its read time.

PID/start identity, same-user ownership and executable path are checked around the read. A changed, exited, unreadable or oversized process returns unavailable.

Only one read may be in flight, the argument-area allowance is 256 KiB, and switching or closing inspection discards the result. Nothing is added to rolling history, reports or recordings by this action.

## Process actions

In the TUI, press `v` to switch from the contributor overview to process view. Select a current individual process before terminating; focus also works on a process-view session group. The overview itself has no termination or focus command. The Mac contributor menu additionally offers a frozen multi-target review, described in [Mac actions](../usage/mac.md#inspect-and-act-on-a-contributor). Opening a confirmation freezes its process identity: subsequent sorting, refreshes, and filter changes cannot retarget it.

### Terminate one process

Press `k`, inspect the PID, executable and session, then press Ctrl-Y to send SIGTERM. Esc cancels. Only the selected process is signaled, including when you explicitly select an agent runtime; children and process groups are not signaled automatically. SIGKILL is not offered.

The process must still have the same PID, start time and executable and belong to your user. macOS identity checks and PID-based signaling are not atomic, so a small race remains. “SIGTERM accepted” does not mean the process exited.

### Messaging is unavailable

Messaging is unavailable in local-only operation. Native controls disable messaging; TUI `s` and the CLI `message` command refuse with an explanation. Agent Monitor does not invoke Codex/Claude helpers to discover recipients or send messages, and there is no switch to permit Internet-capable helpers.

### Focus the hosting terminal

Press `f` to bring the terminal hosting the selected process's agent runtime to the front. On a collapsed session group, `f` focuses the group's runtime when its processes share exactly one; otherwise expand the group and select a process. The runtime, not the workload, is the target because agent tool subprocesses often have no terminal.

In Terminal.app the tab on the runtime's terminal device is selected, its window is unminimized and ordered front, and Terminal is activated; the result panel names the device. Other terminal and editor apps found above the runtime are only asked to come to the front, so another of their windows may show.

Sessions under tmux, screen, or ssh, and background runtimes without a terminal, report that nothing was focused.

On first use macOS asks whether the terminal running Agent Monitor may control Terminal; that Automation grant applies to everything run in that terminal, and it can be revoked in System Settings › Privacy & Security › Automation. Since macOS 14 activation is a request, so macOS may keep another app in front. Focus never types into, runs commands in, or reads the target terminal.

### Actions from the command line

The same actions are available without the TUI, for a PID taken from a text report:

```sh
agent-monitor kill --pid 42001
agent-monitor focus --pid 42001
```

`kill` and `focus` read the process's current lifetime and attribution, independently of the display thresholds. `kill` prints the target and asks `[y/N]`; without interactive stdin it refuses unless `--yes` is supplied. `focus` needs no confirmation.

`agent-monitor message [--no-color]` reports the offline limitation and exits with status 1 before process lookup or confirmation. It accepts no PID, message text or recipient options.

| Exit status | Meaning |
| --- | --- |
| `0` | Accepted: SIGTERM sent or terminal focus requested. Exit and physical focus are not confirmed. |
| `1` | Nothing was done: refused, cancelled, not found, or failed before sending. |

JSONL output has no action commands.

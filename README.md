<p align="center">
  <img src="docs/assets/agent-monitor.png" alt="Agent Monitor: terminal prompt and resource activity bars" width="128" height="128">
</p>

<h1 align="center">Agent Monitor</h1>

<p align="center"><strong>Find the session behind the load.</strong></p>

Trace heavy CPU and memory usage to **Codex CLI and Claude Code sessions** on macOS.

When several coding agents are running, a busy `node`, `java`, or `python` process tells you little on its own. Agent Monitor connects heavy processes to their agent session, terminal, and project, so you can see where the work started.

## Features

- **Live terminal view** — watch CPU and memory usage, sort processes, and open details without leaving your terminal.
- **Session grouping** — bring related heavy processes together and see their combined resource usage.
- **Adjustable filters** — change CPU and memory thresholds while the monitor runs.
- **Responsive layout** — use narrow or wide terminals, resize the details pane, and copy text with normal terminal selection.
- **Scriptable output** — print a report or stream JSONL to other tools.
- **Explicit uncertainty** — unknown or ambiguous sessions stay visible instead of being guessed.

## Install

Requires **macOS 27**; tested on Apple Silicon. No root access or agent hooks are required.

[Download v0.1.0 for Apple Silicon](https://github.com/mbackschat/agent-monitor/releases/tag/v0.1.0), then follow the [installation guide](docs/installation.md). The download includes the CLI and its resource bundle; Xcode is only needed if you choose to build from source.

## Quick start

Launch the live view grouped by session from any directory:

```sh
agent-monitor --tui --group session
```

Use **↑ / ↓** to select, **Enter** to expand a session or inspect a process, **g** to toggle grouping, and **q** to quit. The controls and current filters are shown in the terminal.

By default, the monitor shows agent-associated processes exceeding **25% CPU or 1 GB memory footprint**. If the list is empty, press **1** to lower the CPU threshold or **3** to lower the memory threshold. CPU at 100% means one fully occupied core.

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

## Current support

Agent Monitor supports Codex CLI and Claude Code terminal sessions. Claude Code's native installation has been checked with a real workload; npm-based Claude installations and real terminal Codex workloads have not yet been validated. Desktop conversation attribution and third-party agent plugins are not currently supported.

Session associations identify **where a process was launched**. A shared daemon may later serve other sessions, so its current activity cannot always be assigned to the session that started it. Group totals cover the heavy processes shown, not every process in a session.

The monitor inspects only your user's processes and does not read conversation transcripts. Command arguments are hidden unless you request them with `--commands`.

## Documentation and contributing

- [Usage guide](docs/usage.md) — controls, measurements, grouping, and JSONL.
- [Development guide](docs/development.md) — build, test, and verification commands.
- [Architecture](docs/architecture.md) — how collection, attribution, and presentation fit together.
- [Validation record](docs/poc-validation.md) — what has been tested and known coverage limits.
- [Project plan](PLAN.md) — completed work and current scope.

Bug reports and focused contributions are welcome. Include your macOS version, agent installation type, command used, and expected versus observed behavior. Remove session IDs, project paths, and command arguments you do not want to share from any attached output. For code changes, start with the [development guide](docs/development.md).

## License

[MIT](LICENSE).

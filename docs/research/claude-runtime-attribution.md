# Claude runtime and workload attribution signals

Checked 2026-10-16 on macOS 27 with native Claude Code runtimes 2.1.296–2.1.301 that were already running. Question: which locally observable signals tie a Claude runtime process, and the workloads it starts, to one session, and where does the built-in adapter lose that link? Session IDs, project names and paths are anonymized; counts, process relationships and timings are retained. Related evidence: [Claude session metadata and messaging](claude-session-messaging.md) and [local process observations](terminal-process-observations.md).

## Method and limits

Read-only: one `agent-monitor --json --cpu 0 --memory-gb 0 --commands` sample, `ps` with arguments only, `lsof` path names, `codesign -dv`, two `claude agents --json` calls and the environment variable names visible to this session's own Bash tool and to one of its subagents. No transcript was read, no messaging token value was read or printed, no session was contacted and nothing was signaled. Listing `~/.claude/sessions` was refused by the host's permission classifier because the directory holds inbox auth keys; it was not inspected.

## Runtime-to-session binding

- All seven processes recognized as Claude runtimes were reported as `runtimeOnly` without a session ID. A native runtime's own environment carries no `CLAUDE_CODE_SESSION_ID`; the marker exists only in the environments it gives to children. Codex runtimes can be bound through writer descriptors; no Claude counterpart was found.
- `lsof` on two runtimes found no open path containing the runtime's session ID. The inbox socket is named `/tmp/cc-socks/<pid>.sock`, which encodes the runtime PID, not the session.
- `claude agents --json` returned six entries, each with `pid` and `sessionId`, plus `cwd`, `kind` (all `interactive`), `name`, `startedAt` and `status` (`idle` 4, `busy` 2). The entry for this session's runtime carried the same session ID as its Bash environment and the session's launch directory as `cwd`. The six entries matched the six genuine runtimes; the seventh recognized "runtime" was the embedded tool below.
- One call took 0.68 s wall time, 0.23 s user and 0.13 s system CPU (single measurement, `/usr/bin/time -p`).
- `startedAt` was 2–38 s later than the owning process's start time for all six entries. None of these sessions is known to have been cleared or resumed, so whether `startedAt` changes on `/clear` or `/resume` remains open; for these entries it tracks process registration rather than a later session start.

## Embedded tools invoked under another name

- A process recognized as a Claude runtime was the versioned Claude executable started with `argv[0]` `ugrep`, as a child of a Bash-tool `/bin/zsh`, in a `tail -f <file> | grep …` pipeline. Its arguments began `-G --ignore-files --hidden -I --exclude-dir=.git --exclude-dir=.svn …`. The kernel process name (`pbi_comm`) was the version file name, as for genuine runtimes, so only `argv[0]` distinguished it.
- Genuine runtimes showed `argv[0]` `claude`, matching the `~/.local/bin/claude` launcher name.
- In this session's Bash tool, `grep` was a shell function defined by Claude's shell snapshot. A disposable `tail -f /dev/null | grep <pattern>` started a process with `argv[0]` `ugrep` whose parent was the tool shell.
- Inference: the native executable dispatches on `argv[0]` like a multi-call binary, so the same file acts as a different program when invoked under another name. Only `ugrep` was observed; other embedded names were not looked for.
- Because the ancestry walk stops at the first recognized runtime before reading markers, such a process received no session even though its environment was readable and inherited from the Bash tool.

## Workload environments

- Environment variable names in a Bash-tool child of 2.1.301: `AI_AGENT`, `CLAUDECODE`, `CLAUDE_CODE_CHILD_SESSION`, `CLAUDE_CODE_ENABLE_AUTO_MODE`, `CLAUDE_CODE_ENABLE_TODO_TOOLS`, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_EXECPATH`, `CLAUDE_CODE_MESSAGING_SOCKET`, `CLAUDE_CODE_MESSAGING_TOKEN`, `CLAUDE_CODE_SESSION_ATTENDED`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_EFFORT`, `CLAUDE_PID`. `CLAUDE_PID` equaled the runtime PID, `CLAUDE_CODE_ENTRYPOINT` was `cli`, `CLAUDE_CODE_EXECPATH` named the versioned executable and `AI_AGENT` encoded the version.
- A subagent's Bash tool saw the same `CLAUDE_CODE_SESSION_ID` and `CLAUDE_PID` as its parent and no subagent-specific variable, so subagent workloads are indistinguishable from the main agent's by environment.
- The [earlier platform-binary observation](claude-session-messaging.md#live-transport-check-2026-10-14) reproduced: `/bin/zsh`, `/bin/sleep`, `/bin/bash -c /bin/sleep` and `/usr/bin/env -i CLAUDE_CODE_SESSION_ID=<id> /bin/sleep` returned arguments without environment (`notObserved`), while an ad-hoc-signed Miniconda Python child returned the marker and its `/bin/sleep` child resolved through it as `inheritedMarker`.
- `codesign -dv` reported a platform identifier for `/bin/zsh` and `/usr/bin/python3`, but not for the Xcode toolchain's `swift-frontend`, `clang` and `swift-build`; Homebrew `node` was unsigned. Inference: hidden environments coincide with platform binaries, so Xcode toolchain and Homebrew workloads keep readable markers. This was not established for every binary class.
- Under one long-lived runtime, 26 sampled children without readable markers resolved as `runtimeOnly`: Bash-tool `/bin/zsh` wrappers and their `sleep`, `tail` and `bash` children, and a `caffeinate -i -t 300` started directly by the runtime. Other runtimes had their own `caffeinate` children.

## Working directories within one session

These observations come from investigating a native group labeled with multiple directories; the label is now defined in the [architecture](../architecture.md).

- All eight sampled workloads of one session had exact marker evidence (seven direct, one inherited) and the same runtime; seven used the repository root as working directory, two transient Node processes had unreadable metadata and directory by the time of a follow-up read.
- The repository is a pnpm workspace with package directories below the root, driven through Gradle's Node integration; pnpm runs package scripts with the package directory as working directory. A session's workloads therefore legitimately report several directories in one repository.
- A detached Gradle daemon (parent PID 1) was linked back through its inbox socket and reported the repository root as working directory while idle. Whether its directory follows builds requested from other directories was not checked.

## Unresolved empirical questions

- Whether `claude agents --json` `sessionId` and `startedAt` change immediately on `/clear` or `/resume`, and how long the listing takes with many sessions.
- Which other `argv[0]` names the native executable dispatches on, and which `argv[0]` IDE, SDK or background launches give the runtime.
- Whether every process without a platform identifier exposes its environment, and whether any platform binary does.

# Process signaling and session messaging findings

Checked 2026-10-14 against Codex CLI 0.162.1, Claude Code 2.1.299 and the cited documentation. Initial local checks were read-only `--version`/`--help` calls. The later Claude inbox test used disposable sessions as described in [Claude session findings](claude-session-messaging.md). Current behavior and execution rules belong in [usage](../usage.md#process-actions) and [architecture](../architecture.md#process-and-session-actions).

## Process signaling

A same-user PID can be signaled, but checking PID/start identity and subsequently calling a PID-based signal API are separate operations. Signal acceptance does not prove process exit. A shared daemon's launch origin also does not establish which session currently causes its load. These are limits of the operation, independent of its confirmation UI; native integration coverage is described in the [development guide](../development.md#build-and-verify).

## Provider interfaces

| Provider/context | Evidence | Feasibility for Agent Monitor |
|---|---|---|
| Codex, an addressable existing session | Installed `codex queue --help` exposes `--thread` and `--message`; the official CLI reference documents the command as stable. | Accepts an exact session UUID. Live queue delivery was not tested in this investigation. |
| Codex, app-server integration | Public protocol provides `turn/start` and `turn/steer`; steering requires the matching active turn ID. Local Unix-socket and stdio transports exist. | Requires a known owning server/thread; steering also requires the active turn ID. |
| Claude, running background session | Since 2.1.285, `claude --resume <session> "message"` sends the next prompt and attaches to that session. Redirected I/O or output-format flags cause refusal without sending. | Supports an interactive handoff, not a simple captured subprocess call inside our TUI. |
| Claude, existing interactive terminal session | `/remote-control` exposes the current session through Claude's browser/mobile clients. | A provider-supported way for the user to message it; the inspected docs do not establish a generic local send-message API for arbitrary foreground terminals. |
| Claude, SDK-owned session | Streaming input supports persistent conversations and queued messages. | Feasible for a future managed-session integration; not proof that the SDK can attach to an arbitrary existing terminal process. |

Sources: [Codex queue CLI reference](https://learn.chatgpt.com/docs/cli/reference#codex-queue), [Codex app-server protocol](https://learn.chatgpt.com/docs/app-server), [Claude running-session resume semantics](https://code.claude.com/docs/en/sessions#resume-a-running-background-session), [Claude Remote Control](https://code.claude.com/docs/en/remote-control), and [Claude SDK streaming input](https://code.claude.com/docs/en/agent-sdk/streaming-vs-single-mode). Local checks ran only `--version` and `--help`, including `codex queue --help` and `codex app-server proxy --help`.

## Recipient identity and delivery limits

Codex documents `thread.sessionId` as the root of the logical session tree, with a root thread's own ID as its session ID. An inherited `CODEX_SESSION_ID` is launch metadata; it does not establish that a recipient is still loaded or reachable. [Thread identity semantics](https://learn.chatgpt.com/docs/app-server#start-or-resume-a-thread).

A read-only production-adapter probe against 0.162.1 established that `app-server proxy` forwards WebSocket bytes rather than the JSONL of a standalone stdio app server. Recipient lookup succeeded without requesting turns. Live child-recipient routing and actual queue delivery remain untested; see [coverage](../development.md#validation-coverage).

The initial Claude handoff finding was extended by the later [inbox investigation](claude-session-messaging.md), which observed delivery through the running session's socket. Ordinary transcript resume, SDK session management and Remote Control are different interfaces and do not by themselves establish a noninteractive send path into an arbitrary foreground process.

Queued or socket-accepted messages may be delayed, held or refused. Acceptance is not evidence of delivery, agent action or the continued existence of the workload named in a message.

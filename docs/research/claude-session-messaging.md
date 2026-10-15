# Messaging an existing Claude Code session

Checked 2026-10-14 against installed Claude Code 2.1.300. Question: can Agent Monitor, as a separate process, deliver a text message into an already-running local Claude Code session identified by session UUID and runtime PID, comparable to `codex queue --thread <uuid> --message <text>`? Related CLI interfaces are recorded in [session actions](session-actions.md). Findings, inferences, and gaps are kept separate.

## Session markers and hooks

The inspected [environment reference](https://code.claude.com/docs/en/env-vars) describes `CLAUDE_CODE_SESSION_ID` in Bash/PowerShell, hook-command and stdio MCP subprocesses. Bash/hooks track `/clear`; an already-running MCP server retains its spawn ID. Explicit `--resume <id>` supplies that ID to MCP, while `--continue` or unspecified resume can retain an initial ID. A marker describes session origin, not a particular tool invocation.

`CLAUDE_CODE_MESSAGING_SOCKET` is conditional on an inbox being bound and is exported per session from v2.1.224. Its absence does not establish that a process is unrelated to Claude. The [hook reference](https://code.claude.com/docs/en/hooks) includes session/cwd and tool-use context but no universal child OS PID; a hook's own PID/PPID identifies the hook. Hook commands run in their own OS session without a controlling terminal, and transcript writes can lag.

These are documentation findings, not a complete live compatibility matrix for clear/resume, MCP lifetimes or installation types. Current [attribution coverage](../development.md#validation-coverage) is recorded separately.

## Local evidence (installed CLI)

Only `--version`, `--help`, subcommand `--help`, and one `claude agents --json` call were run. No session was started, resumed, attached, or messaged. For the JSON call only field names, types, and `kind`/`status` values were inspected; no paths, names, or IDs were retained.

| Interface | Observed behavior | Relevance |
|---|---|---|
| `claude agents --json` | "Print active sessions (interactive and background) as a JSON array and exit (for scripting; does not require a TTY)". Each element has `pid` (int), `sessionId` (string), `kind` (observed: `interactive`), `status` (observed: `idle`, `busy`), `cwd`, `name`, `startedAt` (int). | Non-interactive way to verify that a runtime PID currently hosts a session ID, including interactive foreground sessions. Verification only; it does not send anything. |
| `claude --bg` / `--background` | Starts a background session and prints the id taken by `claude attach`, `logs`, `stop`, `rm`. "With --resume <session-id>, continues that session in the background under the same ID, or starts a copy and says so when the session is already running." | On a running session this forks a copy instead of delivering into it, so it is not a delivery transport for existing sessions. |
| `claude attach <id\|name>` | "Open the background session in this terminal." | Interactive handoff; needs the user's terminal. |
| `claude --resume <id> [prompt]` | Help only says "Resume a conversation by session ID". Running-session semantics come from the docs (see [session actions](session-actions.md)): attaches and refuses redirected I/O. | Interactive handoff, not a captured subprocess call. |
| `--remote-control [name]` | "Start an interactive session with Remote Control enabled." | Opt-in at session start or via `/remote-control`; addressed through Claude's own clients. |
| `--brief` | "Enable SendUserMessage tool for agent-to-user communication." | Agent → user direction only. |

The `claude --help` command list (2.1.300) has no `send`, `queue`, or `message` subcommand.

## Documented interfaces

| Interface | Documented behavior | Fit for Agent Monitor |
|---|---|---|
| `claude agents --json` | "The supported way to read session state from outside Claude Code"; research preview, format not declared stable. `pid`/`status` present while the process is alive; `status` is `busy`, `waiting` or `idle`; `kind` is `interactive` or `background`; `sessionId` is the full UUID when set. [Agent view](https://code.claude.com/docs/en/agent-view), [CLI reference](https://code.claude.com/docs/en/cli-reference). | Verifies that a live runtime PID currently hosts the attributed session. Foreground interactive sessions appeared in the local listing above, although agent view says they do not appear until backgrounded. |
| Session inbox socket | Each messaging-enabled session (v2.1.224+) binds a per-session Unix socket "where other sessions on the machine deliver messages"; read the section "when you want a script or hook to post into a session". The path is exported to hooks and Bash commands as `CLAUDE_CODE_MESSAGING_SOCKET`; each session exports its own path, never one inherited from a parent. Line-oriented: a connection must send a complete line within 30 seconds. The optional first line `{"type":"auth","token":"<token>"}` uses `CLAUDE_CODE_MESSAGING_TOKEN`; on macOS the line is optional. Socket restricted to the OS user. [Cross-session messaging](https://code.claude.com/docs/en/cross-session-messaging#the-sessions-inbox-socket), [environment variables](https://code.claude.com/docs/en/env-vars). | Only documented local path into an already-running foreground or background session. The message line schema after the auth line is not documented on the inspected pages. |
| Inbound controls | Messages on the socket pass `crossSessionInbound` (`accept`/`hold`/`refuse`). Without a value: a session that prompts for permissions delivers; a bypassing session holds for approval. A token-verified own-child message is delivered when no value applies. A refusing session shows no visible change. Idle receivers start a new turn; busy receivers read between tool calls. Messages cannot approve prompts, change configuration, or run slash commands. At most 50 accepted messages are queued; same-machine size cap about one million characters. | Socket acceptance is not delivery: a message may be held or silently refused. Presenting the session's token would claim own-child status and bypass the hold for bypassing sessions, so using it changes the trust classification of an external sender. |
| `claude --resume <id> "prompt"` | For a running **background** session (v2.1.285+), sends the prompt as the next turn and then attaches; prints `Sent your prompt to the background session (<id>); opening it…`. Without a TTY, or with redirected I/O or several flags, nothing is sent and it exits 1. Foreground sessions undocumented. [Sessions](https://code.claude.com/docs/en/sessions#resume-a-running-background-session). | Interactive handoff for background sessions only. |
| Channels | MCP servers named in `--channels` at launch push `notifications/claude/channel`; "being in `.mcp.json` isn't enough"; no acknowledgment; research preview. [Channels](https://code.claude.com/docs/en/channels). | Only for sessions launched with the channel; cannot reach an existing session. |
| Remote Control | Drives a session from claude.ai or the Claude app through Anthropic servers. [Remote Control](https://code.claude.com/docs/en/remote-control). | Not a local API. |

## Message line schema (inference)

The installed 2.1.300 binary embeds this debug-log hint next to its `[uds-messaging] Listening:` message: `{ echo '{"type":"auth","token":"'"$CLAUDE_CODE_MESSAGING_TOKEN"'"}'; echo '{"type":"user","message":{"role":"user","content":"hello"}}'; } | socat - UNIX-CONNECT:<path>`. The second line matches the documented SDK stream-json user message (`--input-format stream-json`). This is product-emitted guidance found by searching the binary's strings, not a documented public contract; it can change between releases. Only `strings` was used; no code was decompiled and no socket was contacted. The binary also refers to an "inbox auth key" published to a "session registry directory"; the `~/.claude/sessions/*.key` files were not read.

## Live transport check (2026-10-14)

With the user's approval, one disposable session at a time was started from a scratch directory: `claude -p --input-format stream-json --output-format stream-json --model haiku --safe-mode --no-session-persistence --settings '{"crossSessionInbound":"accept"}'`, with a single allowed Bash command that started an idle background child. No existing session was messaged, and both disposable sessions and their children were stopped afterwards.

- `claude agents --json` listed the `-p` runtime as `kind: interactive`, `status: idle`, with its PID and session ID; the debug log showed the bound socket under `/tmp/cc-socks/`, a user-only directory.
- An unauthenticated connection carrying one stream-json user line received no bytes back and saw end-of-stream about 20 ms after the client finished writing. The debug log recorded `Routed user message to queue (priority=next)` and the next request carried `cc_turn_origin=peer`; the idle session started a turn with the message.
- macOS 27 does not expose the environment of Apple platform binaries through `KERN_PROCARGS2`: Claude's `/bin/zsh` tool shell and its `/bin/sleep` child returned arguments only, as did `/usr/bin/env PROBE_X=1 /bin/sleep` started outside Claude. A Homebrew Python child of the same session exposed `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_MESSAGING_SOCKET` and other variables. Workloads that are platform binaries therefore carry no readable marker; this affects attribution generally, not only messaging.
- The production `SessionActions.local()` path, driven against the Homebrew Python workload of the second disposable session, resolved a Claude `marker` attribution under the runtime, offered one "Claude session" recipient, verified it with `claude agents --json`, and wrote the PID-prefixed message. The session answered it in a new turn.

## Conclusions

- No documented non-interactive command delivers into a running Claude session. The inbox socket is the only local, documented delivery path; its path is discoverable from a workload's own environment because Claude exports `CLAUDE_CODE_MESSAGING_SOCKET` to Bash commands.
- `claude agents --json` provides independent, non-interactive verification of the live `pid` ↔ `sessionId` binding.
- A socket transport would rely on an undocumented message line schema and offers no documented acknowledgment, so socket acceptance alone does not establish delivery.
- Gaps: the remainder of the hooks and environment-variable reference pages (beyond 100,000 characters) and changelog entries before 2.1.292 were not read.

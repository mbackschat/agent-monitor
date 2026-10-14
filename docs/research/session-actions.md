# TUI process and session actions

Checked 2026-10-14 against installed Codex CLI 0.162.1, Claude Code 2.1.299, and the official documentation below. The feasibility study originally proposed the behavior below; confirmed SIGTERM and Codex queued messaging are now implemented in the source checkout. See [current usage and limits](../usage.md#process-actions-unreleased) and [architecture](../architecture.md#process-and-session-actions). Live delivery remains untested; validation uses fake provider transports and disposable processes, never user workloads.

## Terminate the selected process

Feasible with macOS process signaling. Recommend `k` opening a confirmation showing the selected PID, executable, and attributed session; confirmation sends `SIGTERM` to that individual process. Recheck its PID/start identity and same-user ownership immediately before signaling, and refuse stale selections. This reduces PID-reuse risk, but a separate identity check and PID-based signal are not atomic. Report permission failures and disappearance explicitly; signal acceptance does not prove exit.

Do not implicitly terminate the agent runtime, a process group, or all session children. A heavy shared daemon can carry one session's launch marker while serving other sessions. Force termination should be a separate explicit action if later requested. Keep native action execution outside the TUI, with neutral requests/results and confirmation state in presentation; the read-only sampler remains independent.

## Send a message to the owning session

| Provider/context | Evidence | Feasibility for Agent Monitor |
|---|---|---|
| Codex, an addressable existing session | Installed `codex queue --help` exposes `--thread` and `--message`; the official CLI reference documents the command as stable. | Best initial adapter: submit a text message using an exact session UUID. Live delivery remains untested. |
| Codex, app-server integration | Public protocol provides `turn/start` and `turn/steer`; steering requires the matching active turn ID. Local Unix-socket and stdio transports exist. | Richer adapter possible when the owning server and thread are known; unnecessary for a first queued-message feature. |
| Claude, running background session | Since 2.1.285, `claude --resume <session> "message"` sends the next prompt and attaches to that session. Redirected I/O or output-format flags cause refusal without sending. | Supports an interactive handoff, not a simple captured subprocess call inside our TUI. |
| Claude, existing interactive terminal session | `/remote-control` exposes the current session through Claude's browser/mobile clients. | A provider-supported way for the user to message it; the inspected docs do not establish a generic local send-message API for arbitrary foreground terminals. |
| Claude, SDK-owned session | Streaming input supports persistent conversations and queued messages. | Feasible for a future managed-session integration; not proof that the SDK can attach to an arbitrary existing terminal process. |

Sources: [Codex queue CLI reference](https://learn.chatgpt.com/docs/cli/reference#codex-queue), [Codex app-server protocol](https://learn.chatgpt.com/docs/app-server), [Claude running-session resume semantics](https://code.claude.com/docs/en/sessions#resume-a-running-background-session), [Claude Remote Control](https://code.claude.com/docs/en/remote-control), and [Claude SDK streaming input](https://code.claude.com/docs/en/agent-sdk/streaming-vs-single-mode). Local checks ran only `--version` and `--help`, including `codex queue --help` and `codex app-server proxy --help`.

## Recommendation and limits

Implement a Codex-first message action, labeled **Queue message**, because the installed CLI already supplies a direct interface. Use argument arrays rather than shell interpolation. Show the exact target and message before submission; distinguish accepted, failed, and delivery-unverified results. A queued message is unsuitable as an emergency stop. For immediate steering, a separate app-server interaction would need active-turn validation.

### Recipient and process context

Default the recipient to the **root agent**, including when the selected workload belongs to a subagent, because it coordinates the session's work. Offer an explicit **Selected agent** choice when the process's attributed agent session is distinct and independently verified as reachable. This choice refers to an agent session, not the selected OS process. Show the selected process, attributed session, and chosen recipient separately. If both choices resolve to the same session, show one recipient. Do not guess the recipient from message wording or silently switch to a child when root verification fails; the user must explicitly choose another verified recipient.

Resolve the live root using provider metadata: Codex documents `thread.sessionId` as the session-tree root, with a root thread's own ID as its session ID. The monitor already retains an optional `rootSessionID` from `CODEX_SESSION_ID`; treat this inherited value as a candidate to verify, not sufficient delivery authority. If the chosen recipient cannot be verified or the evidence conflicts, leave submission unavailable with a reason. See [Codex thread identity semantics](https://learn.chatgpt.com/docs/app-server#start-or-resume-a-thread).

Automatically prepend the **selected workload's PID and process name** to the user's message, regardless of the recipient. Do not substitute the root agent runtime's PID. Show the complete generated message before submission and preserve the user's wording. For example:

```text
[Agent Monitor: selected process PID 42001 (swift-frontend)]
Please investigate why this process is using so much CPU.
```

Capture the selected process identity when opening the composer so refreshes and sorting cannot retarget the draft. Recheck its PID/start identity and attribution before submission; if the process exited, the PID was reused, or attribution changed, require a fresh selection. The PID describes the observed workload, not an instruction or authorization to terminate it. Queuing can delay delivery, so it does not guarantee that the same process will still be running when the agent reads the message. Initially, messaging starts from a process row; expand a session group and select a process rather than inventing one PID for the group.

Disable messaging when attribution is ambiguous, the runtime is unverified, or only detached launch-origin evidence remains. Resolving a historical session ID does not prove it is the currently responsible session or reachable by the local server. Verify the target with the provider before offering delivery, especially when one Codex runtime hosts many threads. Standalone/no-daemon sessions and server selection need a bounded integration test before claiming support.

For Claude, this study recommended a session handoff first and deferred inline messaging until a supported transport was validated. That recommendation is superseded by [Claude session messaging](claude-session-messaging.md), which identifies and validates the per-session inbox socket. Do not infer that ordinary transcript resume injects into an already-running foreground session, or write into another terminal's input. These conclusions concern the documented interfaces inspected, not a claim that all possible integrations are impossible.

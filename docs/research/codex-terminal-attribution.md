# Mapping macOS Processes to Codex Terminal Sessions

Research checked on 2026-10-14. Scope: an existing, locally running Codex terminal CLI and the local processes its shell tools launch. Claude Code is the next provider; Codex Desktop, ChatGPT Desktop/Work, IDE hosts, remote execution, and cloud environments require separate adapters and validation. This document proposes an attribution contract; it does not install hooks or claim that a collector has been implemented.

The product's entry point is a **heavy consumer**, initially above the chosen CPU or memory threshold, and its destination is the **specific responsible agent session**. Process enumeration and inspection of small ancestors are supporting mechanisms. They do not imply an all-process dashboard. An actionable result should identify the consumer, exact logical root/thread when available, runtime PID/start identity, and a concrete session locator such as its terminal device and project label; project alone cannot distinguish simultaneous sessions in the same directory.

## What the installed version actually provides

A read-only local check resolved `/opt/homebrew/bin/codex` to `/opt/homebrew/Caskroom/codex/0.162.1/bin/codex`; `codex --version` returned `codex-cli 0.162.1`. The version command also reported that creating PATH aliases was denied. No upgrade, configuration change, agent conversation, or environment dump was performed. The executable is locally installed; its full source tree was not available at that installation path.

The official GitHub release tag `rust-v0.162.1` resolves through annotated tag `7a078f6bb4ce0dc2a81408b334ce52979d92c603` to commit **`092d3acd6bec3e3a14bdc7e7a2810ab628ab759d`**, dated October 9, 2026. All source links below pin that commit. This matches the reported version, not a separately verified bit-for-bit build identity. [Tag reference](https://api.github.com/repos/openai/codex/git/ref/tags/rust-v0.162.1), [annotated tag](https://api.github.com/repos/openai/codex/git/tags/7a078f6bb4ce0dc2a81408b334ce52979d92c603).

| Signal | Meaning established by pinned implementation | Contract status |
|---|---|---|
| `CODEX_THREAD_ID` | Logical thread executing the shell command. It is inserted after shell-environment filtering, including `include_only`. | Verified implementation behavior; not established here as a stable documented external API. [Environment construction](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/protocol/src/shell_environment.rs#L81). |
| `CODEX_SESSION_ID` | Shared root-session identity, equal to the **root thread ID**. It groups the logical agent tree; it is not a PID or a fresh identifier for each resumed CLI process. | Verified implementation behavior. [Injection](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/exec_env.rs#L34), [root identity](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/agent/control.rs#L85). |
| `CODEX_VERSION` | Harness package version injected alongside root-session identity. | Useful compatibility hint, not authenticated provenance. [Injection](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/exec_env.rs#L34). |
| Unified-exec `process_id` | A Codex handle allocated randomly in production, independent of kernel PID. | Never use as a macOS PID. [Allocation](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/unified_exec/process_manager.rs#L420). |
| Tool-call ID | Separate command invocation identity passed with thread ID to exec-server metadata. | Not itself a process mapping; it is not injected as a corresponding generic child-environment marker by the inspected path. [Request metadata](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/unified_exec/process_manager.rs#L212). |

Unified exec injects the current thread and root-session IDs while constructing its command environment; user-entered shell commands also call these injection functions. Therefore a process marked as Codex-originated is not necessarily a command chosen autonomously by the model. Preserve that distinction if provider events establish `UserShell` versus other command sources. [Unified execution](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/unified_exec/process_manager.rs#L1382), [user-shell execution](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/tasks/user_shell.rs#L159).

The generic session model maintains logical threads in a shared map of `ThreadId` to `Arc<CodexThread>`. Subagents are therefore not required to have distinct native Codex processes. Keep the logical agent graph separate from the OS process tree. [Thread manager](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/thread_manager.rs#L417).

## Recommended mapping: two linked graphs

The proposed process key is **host/boot identity + PID + process start identity**. A PID alone can be reused. Separately retain provider, root-session ID, logical thread ID, and optional tool-call ID. A launcher/runtime identity must remain distinct from a root-session ID so resuming the same conversation does not merge old and new OS process lifetimes.

```text
OS process identity → observed launch/parent edges → Codex runtime identity
         │                                           │
         └─ allowlisted child markers ─→ thread ID ─→ root-session ID
                                           │
                                  project/context metadata
                                           │
                              optional command invocation ID
```

These are proposed requirements and deductions from the source above, not claims that macOS or Codex publishes this complete graph:

1. **Sample broadly; enrich heavy consumers.** Preserve minimal process identities, parent edges, and resource counters across scans, including for processes currently below thresholds, so later attribution can survive parent exit. Apply thresholds before expensive enrichment and product output. Enrich qualifying consumers and their supporting ancestors with permitted executable, owner, cwd, and command metadata. Resolve each parent link to a particular process lifetime; do not attach a child to a reused PID. Supporting history does not make every sampled process a product result.
2. **Recognize runtime candidates by executable and launch shape.** The Homebrew installation here is native. npm installations add a Node launcher: official `codex.js` locates a platform binary and spawns it with inherited stdio. Account for that wrapper without treating every `node` process as Codex. [npm launcher](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-cli/bin/codex.js#L226).
3. **Read only permitted marker values.** On candidate descendants or unexplained resource consumers, inspect an allowlist containing `CODEX_THREAD_ID`, `CODEX_SESSION_ID`, and `CODEX_VERSION`. Validate syntax and preserve their provenance. Retain no other environment entries. A marker identifies claimed launch context; corroborate with observed ancestry or a verified runtime whenever possible.
4. **Assign per-process thread identity before propagating.** A child with its own valid marker overrides a weaker ancestor-derived thread inference. A separately invoked nested CLI may inherit an outer environment at startup, while its own shell tools receive newly injected IDs. Do not mistake the nested CLI's inherited launch marker for its current active thread.
5. **Group at both levels.** Attribute marked workloads to the logical thread and aggregate under root-session ID. Keep runtime overhead and shared services separate when their cost cannot be divided between logical threads. Count each OS process once.
6. **Add project context independently.** A process's current cwd, a shell invocation's cwd, and a session's original project directory are different values. Display the observed command cwd when available and use provider metadata to label the session project; never infer exclusive ownership merely because two processes share a directory.
7. **Preserve uncertainty.** Report a known Codex runtime with unknown thread when only ancestry is available. Report a known thread with unavailable launcher when a detached child retains its marker. Lack of one edge should not erase the others.

## Recovering identity for sessions already running

**First choice: marked workloads plus live ancestry.** No restart or hook installation is inherently necessary when the OS permits reading those already-running children. The markers are injected into child command environments, so do not expect the top-level Codex executable's own initial environment to contain its current thread ID. This follows from construction of a separate environment map for each shell launch. [Environment injection](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/exec_env.rs).

**Second choice: narrowly inspected runtime file descriptors.** Version 0.162.1 creates per-thread writer locks under `<codex_home>/thread-writer-locks/<thread_id>.lock` and holds their file handles. A permitted process-FD query can therefore be investigated as a runtime-to-thread association without reading conversations. This is a proposed version-specific adapter, not a tested guarantee. File existence alone is insufficient: stale files exist and upstream cleans them by checking locks. Never acquire, remove, or modify these locks in the monitor. [Writer-lock implementation](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/rollout/src/writer_lock.rs#L15).

**Metadata enrichment: bounded, opt-in parsing.** The pinned `SessionMeta` includes thread ID, root-session ID, parent-thread ID, cwd, source, and CLI version. An adapter could read only these allowlisted metadata fields or obtain them through a connected provider API. Do not ingest instructions or messages. Do not assume a rollout filename UUID is always the stable thread ID: source explicitly distinguishes rollout IDs after revert. [Metadata and history identity](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/protocol/src/protocol.rs#L2912).

If there is no readable marker, no historical launch edge, and no verified runtime association, the original session may be unrecoverable. Project and command matches are suggestions only. This limitation particularly affects descendants detached before monitoring began.

## Exact command attribution is a separate problem

For the initial product, a truthful pinpoint is **OS process + executable/command + cwd + logical thread/root session + measured usage + evidence strength**. Mapping to the exact model tool invocation is optional enrichment, not a prerequisite for useful session attribution.

Official hooks document session, working-directory, and tool-call context, but do not promise a general child PID field. A hook's own PID is not the shell command's PID. A future local hook integration can register context and observe its verified ancestors, but timestamp/command matching still cannot establish a unique child when concurrent calls overlap. [Official hooks contract](https://learn.chatgpt.com/docs/hooks).

App-server background-terminal listing is also insufficient as the sole process oracle. Official documentation shows nullable `osPid`, CPU, and RSS values; the pinned core `BackgroundTerminalInfo` contains only item ID, protocol process ID, command, and cwd. Do not promise populated kernel IDs from the installed release. A supported connected client may enrich command context, but monitoring arbitrary terminal sessions must not require silently taking over or resuming them. [Core record](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/codex_thread.rs#L215), [official app-server documentation](https://learn.chatgpt.com/docs/app-server).

If exact invocation-to-PID attribution later becomes required, compare explicit launch registration or an instrumented execution adapter with OS lifecycle observation. Registration must record the actual spawned process identity and invocation ID; a launch wrapper that only tags the Codex root cannot distinguish concurrent commands. This is a design option, not an existing upstream contract.

## Evidence hierarchy and failure cases

| Evidence | Recommended interpretation |
|---|---|
| Explicit, validated launch registration tying process lifetime to provider invocation | Strongest future evidence; not implemented or supplied by generic hooks today. |
| Child thread/session markers corroborated by known runtime or captured launch lineage | Strong provider attribution for the tested version; markers remain mutable, not security credentials. |
| Captured lineage to a marked ancestor | Strong inherited attribution until a closer provider boundary or conflicting marker appears. |
| Live ancestry to recognized native runtime, no thread metadata | Runtime/provider known; thread unknown. |
| Version-specific open writer-lock descriptor | Candidate runtime/thread association to validate; a runtime may own several logical threads. |
| Matching cwd, command text, terminal, or time window | Heuristic only; never break ambiguity by choosing the newest session. |
| No surviving evidence | Unknown; retain measured resource usage. |

Required validation cases include two sessions in one directory; a subagent with shared root ID and distinct thread ID; resume after process exit; nested independent Codex invocation; npm wrapper versus native launcher; `exec` replacement; a shell pipeline; child environment scrubbing; detached descendants both before and after observer startup; PID reuse; permission-denied reads; and a shared compiler/MCP service. Environment reads are opportunistic: permissions, process exit races, rewriting, and scrubbed inheritance can remove the signal. OS-level access and sampling results belong in the separate macOS attribution research.

A shared long-lived daemon's launching session is not proof that all later CPU work belongs to that session. Likewise, a remote execution service may retain useful logical IDs while the measured workload runs on another host. Restrict the terminal adapter's guarantee to observed local processes and surface shared/remote/unsupported cases explicitly.

## Boundaries and next decisions

**Recommendation:** validate passive local attribution for the installed Codex version first, using allowlisted child markers, process lifetime identity, and ancestry. Then test the writer-lock FD fallback for idle sessions. Add optional hooks only if a measured context gap remains; defer a full app-server integration and desktop adapters.

Claude Code can follow the same OS identity model but needs its own provider semantics. Its documented `CLAUDE_CODE_SESSION_ID` and MCP lifecycle caveats differ from Codex's root/thread pair. See [development skills and agent integration](development-skills-and-agent-integration.md). No inference here establishes compatibility with ChatGPT Desktop/Work's host-executed tools or with Codex Desktop's runtime topology.

The unresolved proof is end-to-end behavior on live terminal sessions under normal user permissions. Source inspection establishes where labels originate; it does not establish that a macOS observer can retrieve them reliably in every case. Positive fixtures with readable, valid markers or sufficient recorded lineage must produce the exact correct session association, including multiple simultaneous sessions in the same cwd; returning unknown in these fixtures is a failure. Fixtures with genuinely insufficient or conflicting evidence must produce explicit unknown or ambiguous results instead of a guessed association. Measure attribution coverage among heavy consumers separately from false attribution, reporting unresolved cases and their causes. Passing by classifying every process as unknown is unacceptable; no numerical coverage guarantee is established by this research.

A companion controlled local probe found an important limitation: `KERN_PROCARGS2` succeeded for a synthetic `/bin/sleep` child but returned argv without the known injected markers, whereas a synthetic Python child exposed the marker pair. The mechanism behind that difference was not established. Therefore a successful syscall does not imply a complete environment: distinguish metadata unavailable/incomplete from marker absent, and never infer that an unmarked heavy process is unrelated to an agent merely from this read. This probe does not establish that actual Codex-launched workloads behave identically. See the companion [macOS process-attribution research](macos-process-attribution.md) for local validation evidence.

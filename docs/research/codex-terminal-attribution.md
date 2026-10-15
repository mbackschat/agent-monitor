# Codex process and session identity findings

Sources and local installation checked on 2026-10-14 for Codex CLI 0.162.1. The observations below concern local terminal CLI execution, not desktop, remote or cloud hosts. The implemented attribution contract belongs in [architecture](../architecture.md#agent-attribution-adapters); this note records provider evidence and its limits.

## What the installed version actually provides

A read-only local check resolved `/opt/homebrew/bin/codex` to `/opt/homebrew/Caskroom/codex/0.162.1/bin/codex`; `codex --version` returned `codex-cli 0.162.1`. The version command also reported that creating PATH aliases was denied. No upgrade, configuration change, agent conversation, or environment dump was performed. The executable is locally installed; its full source tree was not available at that installation path.

The official GitHub release tag `rust-v0.162.1` resolves through annotated tag `7a078f6bb4ce0dc2a81408b334ce52979d92c603` to commit **`092d3acd6bec3e3a14bdc7e7a2810ab628ab759d`**, dated October 9, 2026. All source links below pin that commit. This matches the reported version, not a separately verified bit-for-bit build identity. [Tag reference](https://api.github.com/repos/openai/codex/git/ref/tags/rust-v0.162.1), [annotated tag](https://api.github.com/repos/openai/codex/git/tags/7a078f6bb4ce0dc2a81408b334ce52979d92c603).

| Signal | Meaning established by pinned implementation | Contract status |
|---|---|---|
| `CODEX_THREAD_ID` | Logical thread executing the shell command. It is inserted after shell-environment filtering, including `include_only`. | Verified implementation behavior; not established here as a stable documented external API. [Environment construction](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/protocol/src/shell_environment.rs#L81). |
| `CODEX_SESSION_ID` | Shared root-session identity, equal to the **root thread ID**. It groups the logical agent tree; it is not a PID or a fresh identifier for each resumed CLI process. | Verified implementation behavior. [Injection](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/exec_env.rs#L34), [root identity](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/agent/control.rs#L85). |
| `CODEX_VERSION` | Harness package version injected alongside root-session identity. | Useful compatibility hint, not authenticated provenance. [Injection](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/exec_env.rs#L34). |
| Unified-exec `process_id` | A Codex handle allocated randomly in production, independent of kernel PID. | Not a macOS PID. [Allocation](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/unified_exec/process_manager.rs#L420). |
| Tool-call ID | Separate command invocation identity passed with thread ID to exec-server metadata. | Not itself a process mapping; it is not injected as a corresponding generic child-environment marker by the inspected path. [Request metadata](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/unified_exec/process_manager.rs#L212). |

Unified exec injects the current thread and root-session IDs while constructing its command environment; user-entered shell commands also call these injection functions. Therefore a process marked as Codex-originated is not necessarily a command chosen autonomously by the model. Provider events can distinguish `UserShell` from other command sources. [Unified execution](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/unified_exec/process_manager.rs#L1382), [user-shell execution](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/tasks/user_shell.rs#L159).

The generic session model maintains logical threads in a shared map of `ThreadId` to `Arc<CodexThread>`. Subagents are therefore not required to have distinct native Codex processes. The logical agent graph therefore differs from the OS process tree. [Thread manager](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/thread_manager.rs#L417).

The official npm launcher locates and spawns a platform binary with inherited stdio. A Node wrapper is therefore a distinct launch shape from the observed native installation, not evidence that every Node process is Codex. [Pinned launcher](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-cli/bin/codex.js#L226).

## Runtime evidence and metadata

**Child markers.** The markers are injected into child command environments. The top-level executable's initial environment need not contain its current thread ID. This follows from construction of a separate environment map for each shell launch. [Environment injection](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/exec_env.rs).

**Writer descriptors.** Version 0.162.1 creates per-thread writer locks under `<codex_home>/thread-writer-locks/<thread_id>.lock` and holds their file handles. An open descriptor supplies version-specific runtime/thread evidence without reading conversations. File existence alone is insufficient: stale files exist and upstream cleans them by checking locks. A runtime can hold several thread writers. The implemented adapter and conflict rules are documented in architecture; this source review alone did not validate retrieval from a real terminal workload. [Writer-lock implementation](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/rollout/src/writer_lock.rs#L15).

**Session metadata.** The pinned `SessionMeta` includes thread ID, root-session ID, parent-thread ID, cwd, source, and CLI version. The source distinguishes rollout IDs after revert from stable thread IDs, so a filename UUID alone does not establish thread identity. [Metadata and history identity](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/protocol/src/protocol.rs#L2912).

If there is no readable marker, no historical launch edge, and no verified runtime association, the original session may be unrecoverable. Project and command matches are non-unique. This limitation particularly affects descendants detached before monitoring began.

## Exact command attribution is a separate problem

Official hooks document session, working-directory, and tool-call context, but do not promise a general child PID field. A hook's own PID is not the shell command's PID. The reviewed hook fields include session/cwd, tool input and `tool_use_id`; subagent events identify their parent session and agent separately. Timestamp/command matching cannot establish a unique child when concurrent calls overlap. [Official hooks contract](https://learn.chatgpt.com/docs/hooks).

App-server background-terminal listing is also insufficient as the sole process oracle. Official documentation shows nullable `osPid`, CPU, and RSS values; the pinned core `BackgroundTerminalInfo` contains only item ID, protocol process ID, command, and cwd. The documented nullable fields do not establish populated kernel IDs in that release, nor an attachable endpoint for every independent CLI. [Core record](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/codex_thread.rs#L215), [official app-server documentation](https://learn.chatgpt.com/docs/app-server).

## Limits of the evidence

Source inspection establishes where labels originate, not their readability from every process. The [local probes](terminal-process-observations.md) found readable markers on a synthetic orphaned Python child but not on a marked `/bin/sleep` child despite syscall success. A missing marker therefore does not establish non-agent origin. Current live coverage is recorded in the [development guide](../development.md#validation-coverage).

Logical thread/root identity is separate from a PID/start identity, cwd, terminal device or tool-call ID. A shared daemon's launch session does not identify the client responsible for its later load. When no marker, captured ancestry or runtime association survives, the originating session may be unrecoverable; matching directory or command text is not unique evidence.

The reviewed hook schemas do not establish a universal hook-to-child-PID mapping. No source finding here establishes compatibility with desktop-hosted tools, remote workloads or every independently launched Codex server. Claude's marker and lifecycle semantics are recorded separately in [Claude session findings](claude-session-messaging.md#session-markers-and-hooks).

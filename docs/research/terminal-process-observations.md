# Local terminal process observations

Observed on 2026-10-14 on macOS 27.0.1. This initial snapshot investigated terminal Codex roots and a separate nonterminal host. Later provider coverage is recorded in the [development guide](../development.md#validation-coverage). These are small, read-only observations and disposable synthetic fixtures, not a performance benchmark or a completed collector. No real process arguments, environment values, project paths, conversation content, or personal PIDs are retained here.

## What the local process snapshot established

### Takeaway

Three native Homebrew Codex processes were visible as children of `zsh` with controlling terminals. Separately, nested nonterminal Codex processes and `codex-code-mode-host` were visible in the automation environment. Counting every matching name would overstate the number of terminal agent roots.

### Observations and sources

- `proc_listallpids` worked without added privileges. One snapshot listed 805 processes, of which 597 returned a complete `PROC_PIDTBSDINFO` structure; this difference was not investigated process by process. It is evidence to handle unreadable/transient processes, not a permission failure rate. — Local read-only probe, 2026-10-14; [API implementation](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.c)
- Three `codex` executable paths were under Homebrew, each directly parented by a `zsh` process and carrying a controlling terminal. No live descendants of those three roots were present in the sampled snapshot. This does not establish that they were idle, had no detached work, or had never spawned work. Native executable basenames and path categories were observed; no npm wrapper was observed in these three ancestry chains. — Local `proc_pidpath` and `PROC_PIDTBSDINFO` probe, 2026-10-14; [metadata structures](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc_info.h)
- A distinct nonterminal tree contained nested `codex` processes and `codex-code-mode-host`. Its workers lacked controlling terminals, and an outer host and many descendants had different OS session IDs. This environment is useful for testing inspection access but is not evidence of the user's terminal CLI topology. The probes did not establish that it was the Codex Desktop application. — Local restricted metadata probe, 2026-10-14.
- No process name matched Claude in the initial name scan. That is not proof that Claude Code was absent: executable names and launch packaging can differ. No Claude launch topology was empirically validated. — Local process-name filter, 2026-10-14.
- Start time with microsecond resolution and current directory were readable for the inspected Codex roots. Directory values were compared or counted in memory, not printed. OS session IDs were compared only for equality. — Local `PROC_PIDTBSDINFO`, `PROC_PIDVNODEPATHINFO`, and `getsid` probe, 2026-10-14; [Darwin structures](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc_info.h)

Illustrative anonymized trees, with each terminal branch independent:

```text
zsh [TTY]                  zsh [TTY]                  zsh [TTY]
└── codex [native, TTY]    └── codex [native, TTY]    └── codex [native, TTY]

automation codex host [no TTY]
└── codex [no TTY]
    ├── codex-code-mode-host [no TTY]
    └── workers [no TTY; OS session membership can differ]
```

### Inferences

- A terminal runtime can have workers without controlling terminals; the worker's TTY alone does not establish its launch context.
- Process identity, POSIX session identity (`getsid`), process group, terminal device, root agent process, and Codex conversation/thread identity are different concepts. Equality in one does not establish equality in another.
- The observed `zsh → codex` ancestry does not establish npm/shell-wrapper or nested-invocation behavior.

### Gaps

- There was no live terminal-launched workload during the snapshot, so inherited markers in an actual terminal Codex child remain an empirical acceptance test. Upstream launch-source evidence supports the mechanism, but the nonterminal host's workers cannot settle terminal coverage.
- Executable-name filtering was intentionally narrow. It does not establish exhaustive detection of agents, detached processes, or alternate installations.

## Can a process expose session markers after its parent disappears?

### Takeaway

Yes for a controlled same-user Python fixture on this machine: both synthetic Codex markers and cwd remained readable after reparenting to PID 1. However, successful `KERN_PROCARGS2` calls did not consistently expose environments; `/bin/sleep` returned only argument information despite being launched with synthetic markers.

### Observations and sources

- Probes called `sysctl(CTL_KERN, KERN_PROCARGS2, pid)` only for selected Codex trees or controlled children. Real-process parsing retained only `CODEX_THREAD_ID`, `CODEX_SESSION_ID`, `CLAUDE_CODE_SESSION_ID`, and `CLAUDE_CODE_MESSAGING_SOCKET`; output contained presence counts and equality relationships, never their values. The syscall returns a combined argument/environment buffer, so reading it also exposes data outside the marker allowlist. — Local probe, 2026-10-14; [Apple syscall implementation](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_sysctl.c)
- A disposable same-user Python child launched with an explicitly synthetic environment exposed both exact synthetic marker strings. A subsequent forked child outlived its immediate parent: the parent exited, `PROC_PIDTBSDINFO` reported PPID 1, and both markers and the known temporary cwd remained readable. The child was terminated after the check. — Local controlled fixture, 2026-10-14; [reparenting semantics](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/_exit.2.html)
- In a separate fixture, `/bin/sleep` was launched with only the two synthetic environment entries. `KERN_PROCARGS2` returned success and a 33-byte buffer containing argc, executable path, padding, and the two arguments; neither environment entry was returned. A normal synthetic child also had readable start identity and cwd. This observation does not establish whether the difference arose from platform policy, executable behavior, or another condition. — Local controlled fixture, 2026-10-14.
- The three real terminal Codex roots produced no allowlisted markers in their returned buffers. Roots need not contain identifiers that the agent injects only when spawning children; environment coverage was also not proven complete. A single nonterminal descendant exposed both Codex marker names, but no real values were retained. — Local targeted probe, 2026-10-14.
- The parallel upstream investigation found both `CODEX_THREAD_ID` and `CODEX_SESSION_ID` in Codex 0.162.1 launch code. Their distinct thread/root-session semantics come from that source investigation, not this probe. — [Pinned Codex session environment source](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/exec_env.rs), [pinned unified execution launch source](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/unified_exec/process_manager.rs)

### Inferences

- Marker-assisted attribution can survive loss of the current parent link; an already-orphaned child is not automatically hopeless. A marker can associate a process with a known thread/session even when the monitor never observed the original parent, provided the identifier is readable and its semantics are established.
- Syscall success and marker absence do not establish a complete environment read.
- A later empty environment read does not by itself contradict earlier marker evidence for the same process lifetime.
- Session markers are origin metadata, not authenticated proof of current causal workload ownership. They can be inherited, overwritten, removed, or retained by services. They do not authenticate current workload ownership.
- Cwd helps explain a workload but is mutable and can be shared. It cannot uniquely distinguish terminal sessions or establish a shared daemon's current client.

### Gaps

- No broad environment collection was performed and no cause was established for `/bin/sleep` environment omission. This probe alone did not diagnose kernel policy; a later [Claude transport check](claude-session-messaging.md#live-transport-check-2026-10-14) compared Apple platform binaries with a Homebrew child.
- The disposable parser used known simple argument shapes. It did not comprehensively test lengths, argc, padding, empty arguments, truncation or process-exit races.
- Per-process metadata does not identify which tool invocation requested work inside a shared daemon. Exact command/tool-call correlation remains separate from locating an expensive process.

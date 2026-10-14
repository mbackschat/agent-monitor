# Local terminal process observations and a first-release attribution contract

Observed on 2026-10-14 on macOS 27.0.1. Scope is Codex CLI launched in terminals first; Claude Code and desktop variants are later work. These are small, read-only observations and disposable synthetic fixtures, not a performance benchmark or a completed collector. No real process arguments, environment values, project paths, conversation content, or personal PIDs are retained here.

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

- Detect a terminal Codex root from combined executable/ancestry context, then identify its descendants independently of TTY. A worker without a controlling terminal must not be excluded merely for that reason.
- Process identity, POSIX session identity (`getsid`), process group, terminal device, root agent process, and Codex conversation/thread identity are different concepts. None should substitute silently for another.
- Launch packaging detection needs fixtures beyond this installation: native Homebrew, npm wrapper, shell wrapper, and nested invocation. The observed direct `zsh → codex` case is one supported shape to test, not a universal assumption.

### Gaps

- There was no live terminal-launched workload during the snapshot, so inherited markers in an actual terminal Codex child remain an empirical acceptance test. Upstream launch-source evidence supports the mechanism, but the nonterminal host's workers cannot settle terminal coverage.
- Executable-name filtering was intentionally narrow. It does not establish exhaustive detection of agents, detached processes, or alternate installations.

## Can a process expose session markers after its parent disappears?

### Takeaway

Yes for a controlled same-user Python fixture on this machine: both synthetic Codex markers and cwd remained readable after reparenting to PID 1. However, successful `KERN_PROCARGS2` calls did not consistently expose environments; `/bin/sleep` returned only argument information despite being launched with synthetic markers.

### Observations and sources

- Probes called `sysctl(CTL_KERN, KERN_PROCARGS2, pid)` only for selected Codex trees or controlled children. Real-process parsing retained only `CODEX_THREAD_ID`, `CODEX_SESSION_ID`, `CLAUDE_CODE_SESSION_ID`, and `CLAUDE_CODE_MESSAGING_SOCKET`; output contained presence counts and equality relationships, never their values. The syscall returns a combined argument/environment buffer, so a production parser must avoid storing or logging the whole buffer. — Local probe, 2026-10-14; [Apple syscall implementation](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_sysctl.c)
- A disposable same-user Python child launched with an explicitly synthetic environment exposed both exact synthetic marker strings. A subsequent forked child outlived its immediate parent: the parent exited, `PROC_PIDTBSDINFO` reported PPID 1, and both markers and the known temporary cwd remained readable. The child was terminated after the check. — Local controlled fixture, 2026-10-14; [reparenting semantics](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/_exit.2.html)
- In a separate fixture, `/bin/sleep` was launched with only the two synthetic environment entries. `KERN_PROCARGS2` returned success and a 33-byte buffer containing argc, executable path, padding, and the two arguments; neither environment entry was returned. A normal synthetic child also had readable start identity and cwd. This observation does not establish whether the difference arose from platform policy, executable behavior, or another condition. — Local controlled fixture, 2026-10-14.
- The three real terminal Codex roots produced no allowlisted markers in their returned buffers. Roots need not contain identifiers that the agent injects only when spawning children; environment coverage was also not proven complete. A single nonterminal descendant exposed both Codex marker names, but no real values were retained. — Local targeted probe, 2026-10-14.
- The parallel upstream investigation found both `CODEX_THREAD_ID` and `CODEX_SESSION_ID` in Codex 0.162.1 launch code. Their thread/root-session semantics must remain distinct; refer to that investigation rather than inferring meaning from this probe. — [Pinned Codex session environment source](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/exec_env.rs), [pinned unified execution launch source](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/core/src/unified_exec/process_manager.rs)

### Inferences

- Marker-assisted attribution can survive loss of the current parent link; an already-orphaned child is not automatically hopeless. A marker can associate a process with a known thread/session even when the monitor never observed the original parent, provided the identifier is readable and its semantics are established.
- Environment inspection needs a coverage state such as `available`, `partialOrUnknown`, or `unavailable`, separately from `markerPresent`/`markerNotObserved`. Syscall success and marker absence do not establish a complete environment read.
- Preserve prior identity-bound evidence when a later read lacks a marker. An empty read must not revoke a previously evidenced association; a changed process start identity must.
- Session markers are origin metadata, not authenticated proof of current causal workload ownership. They can be inherited, overwritten, removed, or retained by services. Attribute origin explicitly and keep conflicts visible.
- Cwd helps explain a workload but is mutable and can be shared. It should not merge two separate terminal sessions or prove the project responsible for a shared daemon's current work.

### Gaps

- No broad environment collection was performed and no cause was established for `/bin/sleep` environment omission. This is a discriminating acceptance case, not a verified kernel-policy diagnosis.
- The disposable parser used known simple argument shapes. Production parsing must validate lengths, argc, padding, empty arguments, truncation, and process-exit races; these were not comprehensively tested.
- Per-process metadata does not identify which tool invocation requested work inside a shared daemon. Exact command/tool-call correlation remains separate from locating an expensive process.

## Candidate contract and acceptance matrix for terminal Codex first

### Takeaway

The first useful version should show heavy individual processes and identify the specific terminal Codex session responsible for each, including concurrent sessions in the same project. Lightweight processes appear only as attribution context, not as a general process dashboard. Unknown/shared cases must remain explicit; complete historical genealogy, arbitrary shared-daemon causality, Claude adapters, and desktop integration are outside this initial contract.

### Proposed contract

- Each resource row has a process key composed of boot context, PID, and high-resolution start identity; executable identity; optional current cwd; CPU measurement interval and explicit normalization; physical-footprint bytes; and field availability states. See [native measurement research](macos-process-attribution.md) for units and limitations.
- Attribution preserves a terminal Codex root identity when observed, optional Codex thread/root-session identifiers, evidence type (`observedAncestry`, `sessionMarker`, `combined`, `ambiguous`, or `unknown`), observation time, and limitations. A session can exist without a currently live agent root.
- Origin association is not causal accounting. A shared service can be marked shared/ambiguous; processes lacking attribution remain visible when over threshold. Each distinct process contributes at most once to any displayed aggregate.
- Existing-terminal discovery requires no launcher replacement. Optional instrumentation can improve evidence later; failure to read markers does not disable native resource measurement or observed-ancestry tracking.
- The default visible set is processes exceeding the configured CPU or memory threshold. Many small contributors do not enter that list merely because their sum is large. Show smaller ancestors only when needed to explain a heavy process's session association.
- Cheap identity and parent-link history may need broader collection than the visible set: filtering before recording ancestry can discard a short-lived shell that later explains a heavy worker. Expensive enrichment and detailed presentation should focus on heavy candidates. Broad internal discovery and selective output serve different requirements.

### Acceptance matrix

| Case | Required behavior | Evidence status |
| --- | --- | --- |
| Native terminal Codex under `zsh` | Recognize an independent terminal root using executable and ancestry context | Observed three local examples; detection code not implemented |
| Two roots in one project or terminal application | Identify the exact responsible session for a heavy worker; never merge solely by cwd/application | Required fixture, not run |
| Two same-project sessions run the same executable/command | Resolve the heavy process to its specific session using identity/evidence, not command-name similarity | Core required fixture, not run |
| Codex command with a worker lacking TTY | Preserve root attribution when observed ancestry or markers support it | No-TTY automation workers observed; terminal workload fixture still needed |
| Child survives immediate parent | Retain recorded origin; allow readable marker association without live parent | Synthetic reparented Python child passed |
| Readable valid marker uniquely matches a known session | Attribute to that exact session; unknown is a failure for this positive case | Marker readability demonstrated; adapter correlation not implemented |
| Parent exits before first scan | Attribute only with surviving valid evidence; otherwise show unknown | Marker mechanism demonstrated synthetically; complete discovery case not run |
| Environment query succeeds but omits markers | Report unknown coverage; do not conclude non-agent origin | `/bin/sleep` fixture demonstrated omission |
| PID reused or mixed-identity sample | Start a new process record; discard cross-identity measurement | Required fixture, not run |
| `exec` changes executable while retaining PID | Refresh executable context without confusing process lifetime and image identity | Required fixture, not run |
| Nested Codex/helper host names | Avoid counting each matching executable as an independent terminal conversation | Nonterminal nested local example observed |
| Shared build daemon serves multiple sessions | Show origin/shared ambiguity; do not claim request-level causality | Required fixture, not run |
| CPU above 25% / footprint above 1 GB | Show individual process and available attribution; aggregate without duplicates | Metric semantics researched; workload measurement not run |
| Many low-load processes beneath thresholds | Exclude them from the default findings; retain only useful ancestry context | Required presentation fixture, not run |
| Permission failure, process exit, truncated metadata | Preserve availability/error state; never turn unknown into zero | Partial metadata coverage observed; full error matrix not run |
| npm/shell wrapper and future Claude/Desktop | Keep unsupported/untested coverage explicit | Not empirically validated; later adapters |

### Remaining decisions

Recommend making exact session attribution for ordinary terminal Codex workloads the release gate, with explicit unknown/shared states for unsupported cases. Merely displaying CPU and a project name does not satisfy the core problem. Complete causal attribution for shared services would require additional instrumentation; those limits should not silently weaken the ordinary same-project, concurrent-session acceptance case.

Measure attribution coverage separately from incorrect assignments: the proportion of heavy fixtures correctly associated must not be hidden by an all-unknown result with zero false assignments. Positive fixtures with valid readable markers or intact observed ancestry require the exact expected session; only deliberately incomplete/conflicting fixtures permit unknown or ambiguous outcomes.

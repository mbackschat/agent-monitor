# Agent Monitor: product vision

## Vision

Help a developer with many simultaneous coding-agent sessions answer: **Which specific session caused this heavy CPU or memory consumer, and what is it doing?** Focus on the significant consumers among dozens of processes. Naming the agent product or project is insufficient when several sessions share both.

The first PoC uses Swift and a headless core with a command-line harness. Research recommendations remain separate from confirmed scope; see the [implementation README](../../README.md) for current behavior.

## Confirmed scope

- **Platform:** macOS-specific tooling.
- **Agents and priority:** identify processes launched by terminal-based Codex CLI first; add terminal-based Claude Code afterward.
- **PoC update:** after Codex attribution passed its initial tests, the user approved a small Claude session-marker adapter to diagnose the live workloads observed on 2026-10-14. Broader Claude and desktop integrations remain later work.
- **Core result:** identify heavy CPU or memory consumers and map each to its specific originating agent session. Show smaller processes only as context needed to trace a heavy workload.
- **Problem setting:** many concurrent agent sessions make ownership difficult to determine manually.
- **Threshold examples:** CPU above approximately 25% or memory above approximately 1 GB. These illustrate useful attention thresholds; their exact definitions and configurability remain to be agreed.
- **Product progression:** establish a headless capability first, then a CLI; a native application or menu bar interface is a possible later presentation.
- **TUI direction:** an explicit option should open a full-window live report with colors, compact heavy-process rows, sorting by CPU/memory/PID, and on-demand disclosure. Selection should follow a process identity through sorting and refreshes; PID order helps track a particular entry. The same summary/details approach should be usable in a later menu bar UI. Monitoring logic must stay independent of presentation; see the [architecture](../architecture.md). The TUI is implemented and terminal-validated; see [PLAN.md](../../PLAN.md) for evidence and outstanding checks.
- **Initial execution context:** terminal agent sessions. Desktop agent variants, such as ChatGPT Desktop, are potential future extensions and are outside the initial scope; a desktop conversation is not itself evidence of local CLI execution.

## Proposed behavior

The following recommendations support the vision but have not been approved as requirements:

- Show process identity, command context, measured usage, and the specific session; project information provides supporting context.
- Explain the association through observed ancestry or explicit agent metadata, and distinguish uncertain attribution from a known owner.
- Default to heavy processes with agent evidence; keep known agent runtimes/workers visible even when their exact session is unknown or ambiguous. Offer `--all-processes` to include unrelated or wholly unattributed heavy consumers (for example Spotlight or OneDrive), still respecting thresholds and same-user scope. Implemented with explicit scope and ambiguity regressions.
- Make machine output discoverable through `--help`: document all options, defaults, units, and streaming examples. Keep `--json` as one report per line (JSONL), and offer `--json-schema` to print the report contract without starting collection. JSONL and schema discovery are implemented and independently schema-validated.
- Optionally use session totals to reveal consumption spread across children, while keeping significant consumers central.
- Use interval CPU usage with 100% representing one occupied CPU, and explicitly labeled physical footprint for the primary memory measurement.
- Support the current user's local workloads without elevated privileges initially; keep collection and attribution independent of presentation.

## Decisions still open

The PoC currently chooses one-core CPU percentages, one-second waits, decimal GB physical footprint, on-demand sampling or continuous CLI output, and macOS 27 with Swift 6.4. These are initial implementation choices; the broader compatibility and long-term product decisions below remain open.

- **Measurement:** one-core or whole-machine CPU percentages; sample interval; GB or GiB; footprint versus RSS; sustained versus instantaneous threshold crossing.
- **Attribution depth:** identifying the specific session is essential; whether a particular tool invocation is also required remains open, as does handling detached children and shared services.
- **Integration:** whether optional hooks or launch wrappers are acceptable, and which existing sessions must be recognizable without them.
- **Compatibility:** minimum macOS release, Intel support, and supported agent versions.
- **Operation:** on-demand versus continuous collection, retention/history, and eventual distribution channel.

Process termination, notifications, a background daemon, remote/container workload attribution, and an App Store release are **not established requirements**. Researching these constraints does not add them to scope.

On 2026-10-14, the user proposed a TUI key to terminate a process and requested feasibility research for messaging its agent. Recommended behavior and provider-specific limits are recorded in [session actions](session-actions.md). The user subsequently authorized implementation: the current source supports confirmed single-process SIGTERM and Codex queued messaging with verified root/selected recipients and automatic workload PID context. On 2026-10-14 the user also authorized Claude Code messaging through the documented per-session inbox socket, accepting its undocumented message line format; see [Claude session messaging](claude-session-messaging.md). General plugins remain outside scope. See [current action usage](../usage.md#process-actions).

For a future Codex queue-message action, the user prefers delivery to the **root agent**, even when a selected process belongs to a subagent. Show and verify that root recipient; do not silently substitute the child when the root is unresolved. This refines the proposal without authorizing its implementation.

## Session grouping

The user approved optional grouping by agent session, with expandable groups in the TUI. `--group session` opts into grouped text/TUI output, and `g` toggles grouped/process views in the TUI. Groups start collapsed; Enter expands/collapses a session row and retains its existing details behavior on a process row. Each group shows provider, project, session identifier, heavy-process count, and summed CPU/footprint of the displayed heavy processes. These are labeled heavy-process totals, not complete session totals; existing per-process thresholds remain and each process is counted once. Partial totals are marked when measurements are missing.

Prefer corroborated root-session grouping so subagent workloads appear beneath the coordinating agent, consistent with the proposed messaging target. Preserve each process's actual child-thread attribution in its details. If the root cannot be resolved, retain an exact-session group when available; ambiguous or unresolved entries remain separate and must not be combined by project directory, terminal, provider name, or a shared runtime PID. Shared-daemon launch evidence remains qualified. Selection and expansion survive refreshes through stable session/process identities. The PoC corroborates roots only from current snapshot findings with matching provider and runtime lifetime; a root absent from the heavy findings cannot be established through that method. Broader provider metadata lookup remains outside this presentation change.

## Live threshold controls

The user approved live threshold controls on 2026-10-14: `1`/`2` decrease/increase CPU by 10 percentage points, and `3`/`4` decrease/increase footprint by 1 decimal GB, clamped at zero. The TUI shows requested values and keys in both flat and grouped views, retains the CPU OR memory rule, and labels changes pending until a matching snapshot arrives. The collector applies one threshold pair per sample to both enrichment and filtering without restarting its CPU baseline. Lowering thresholds allows newly qualifying processes to appear. Existing selection survives where its identity remains visible. These controls are implemented; startup defaults remain CPU > 25% OR footprint > 1 GB.

## Proposed agent adapters

Keep adding agent providers inexpensive through a small adapter protocol and registry, with built-in Codex and Claude adapters first. The user offered metrics, details, and communication as an initial idea to refine, not a fixed interface. The implemented [built-in adapter boundary](../architecture.md#agent-attribution-adapters) owns attribution evidence; optional structured session inspection remains a proposal and verified messaging is a separate capability. Presentation owns the details view. OS resource measurement and attribution safeguards remain shared. External plugins are a future transport for the same contract, not a plugin loader to build now. The user authorized the built-in attribution extraction on 2026-10-15; optional inspection and external plugins remain outside that implementation scope.

## Research context

See the [research assessment](assessment.md) for recommendations and tradeoffs, the [macOS attribution note](macos-process-attribution.md) for measurement limits, and the [agent integration note](development-skills-and-agent-integration.md) for provider metadata. The [proposed working model](agent-working-model.md) describes contributor roles without activating delegation.

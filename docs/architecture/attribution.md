# Attribution and offline runtime

Attribution uses allowlisted local evidence and exact process lifetimes. Provider adapters interpret that evidence; the shared host owns native access, ancestry and conflict resolution. Runtime helpers must not initiate Internet connections.

[Architecture overview](../architecture.md) · [All architecture guides](README.md)

## In this guide

- [Attribution evidence and inspection scope](#attribution-evidence-and-inspection-scope)
- [Offline runtime](#offline-runtime)
- [Agent attribution adapters](#agent-attribution-adapters)
- [Harness session registries](#harness-session-registries)
- [Harness adapters](#harness-adapters)
- [Deferred adapter capabilities](#deferred-adapter-capabilities)

## Attribution evidence and inspection scope

Each finding identifies a process lifetime, its usage, available working directory, provider session/thread ID, runtime PID and terminal when known, and the evidence supporting that association. Display thresholds default off; enabled thresholds reduce visible rows while all observed in-scope contributors remain available for totals. Ancestors also supply tracing context.

### Codex

Child `CODEX_THREAD_ID` / `CODEX_SESSION_ID` markers identify logical threads and their root session. Open writer-lock descriptors can identify a thread when exactly one candidate exists in the nearest native runtime. With no observed runtime ancestor, a marked workload is linked back to the one live Codex runtime holding a writer descriptor for its exact thread ID, provided that runtime started no later than the process carrying the marker. A matching root-session ID alone is insufficient; multiple matching runtimes leave the runtime unresolved while preserving the marked thread. A runtime started later, including one resuming the same thread, cannot establish launch origin.

### Claude Code

`CLAUDE_CODE_SESSION_ID` identifies launch origin. Native `claude` executables and the versioned native installation are recognized as runtime boundaries only when invoked as themselves: the same executable runs embedded tools selected by `argv[0]` (observed: `ugrep` behind the Bash tool's `grep`), so an `argv[0]` naming neither `claude` nor the executable withdraws the runtime claim and the process resolves as a workload through its own marker. Unreadable arguments keep the executable claim.

Native runtimes carry no marker of their own, and platform-binary children such as Bash-tool shells expose no environment; their exact session may remain unresolved because production [harness session listings](attribution.md#harness-session-registries) are disabled under the offline contract. See [runtime attribution research](../research/claude-runtime-attribution.md).

A workload detached from its runtime (for example a background job whose shell exited and which was reparented to launchd) is linked back to the one live Claude runtime that listens on the inbox socket named by its `CLAUDE_CODE_MESSAGING_SOCKET`, provided that runtime started no later than the process carrying the marker; a later start means PID and socket-name reuse.

The adapter requests native listening-socket paths for recognized runtimes; detached candidates enter enrichment in a second pass after the marker is known.

npm-based Claude roots have not been validated.

### Historical ancestry

Parent relationships survive observed parent exit. PID plus microsecond start time prevents PID reuse from inheriting a different process's history.

### Nested agents

One agent started inside the other (Codex → `claude`, or Claude → `codex exec`) leaves both providers' markers in its workloads. The inner agent is the nearest runtime above the workload and set its own marker last, so its provider's marker attributes the workload; a detached workload carrying both stays ambiguous.

### Uncertainty

Multiple runtime thread candidates, conflicting markers, and incomplete metadata remain explicit. A known runtime/terminal can still be reported when the logical thread is unresolved. Unresolved agent-associated heavy consumers remain visible; unrelated unknown consumers require `--all-processes`.

### Recognition lifetime and fresh evidence

The monitor retains the complete adapter recognition set until a polling-visible execution boundary (path/name change or kernel-peak footprint reset); each boundary invalidates that set and metadata. A read `argv[0]` can only narrow the set for that lifetime through the adapter's invocation check, without repeating path recognition, and an unreadable later read keeps the earlier invocation. A per-snapshot index contains only live runtimes claimed by exactly one provider. Adapter path parsing supplies explicit URL directory hints, avoiding filesystem checks during recognition; the host remains the native I/O boundary. Detached lookup uses that index without re-recognizing every process for every query. Session markers, descriptors and sockets still refresh through the native reader; reuse of resolved ownership follows the [input-invalidation contract](native-app.md#reusing-unchanged-collection-context).

Detached runtime candidates are enriched in a second pass after reading the workload's marker. Every enrichment refreshes all eligible candidates, including after a prior match, so a closed descriptor or competing runtime cannot leave a cached association in place. Sampling and action lookup share this path; it does not invent parent edges in the reported ancestry.

### Shared runtimes are separate populations

The Codex adapter identifies a process as a **shared runtime** only when it is the attributed Codex runtime itself (matching PID and start time), has no exact thread, and carries ambiguous evidence with more than one distinct writer thread ID. This uses existing snapshot evidence; it does not reinterpret unresolved descendants as shared runtimes or change the JSONL contract. The runtime remains a singleton in session grouping because its own resource usage cannot be allocated among the hosted threads. Exact workload markers keep precedence over this label. No terminal or client association follows from the label.

These are **launch-origin associations**. A Gradle, Kotlin, MCP, or other shared daemon can later serve different sessions; its inherited marker does not establish which session caused its current CPU usage. Desktop hosts are labeled nonterminal where identifiable, with no promise of desktop conversation attribution. A terminal-less detached worker can retain a known logical session even when its runtime is unavailable.

The monitor examines only same-user processes. It reads allowlisted session markers, permitted process metadata, and Codex writer-lock descriptor paths, and never launches provider session-listing commands; it does not read conversation transcripts or keep full environment buffers. Attribution history exists only in memory for live processes and their necessary ancestors; the [counter ledger](accounting.md#retained-counter-accounting) independently retains bounded CPU baselines for missing lifetimes. Monitoring after an unmarked process has already detached may not recover its session.

## Offline runtime

### Fail-closed runtime capabilities

Agent Monitor initiates no Internet connections, directly or through launched provider helpers. Provider-listing readers, adapter commands/parsers, scheduling, bindings and listed-name storage are absent from collection and diagnosis. Messaging adapters, transports, recipient/draft types and composer states are absent. Native controls disable Message; the TUI and CLI explain its unavailability without inspecting a recipient or opening an action panel. Provider-listed names/current-session fallback and messaging are therefore unavailable, with a shared explanation in diagnostics/help. No UI or CLI option enables an unsafe provider helper. The retained accounting probe also rejects `--providers` before native collection.

Native process inspection, local attribution, termination and terminal focus remain available. The only production subprocess is fixed `/usr/bin/osascript` code addressing the already-running local Terminal application; it does not execute shell/network commands. There is no HTTP client or remote URL-opening path. This is source-level elimination of the Internet-capable provider paths, not an OS-wide sandbox or a claim that other running agents cannot use the Internet. Internal fixture injection is not a production option; tests use disposable local programs.

## Agent attribution adapters

Implemented on 2026-10-15. Built-in `CodexAttributionAdapter` and `ClaudeAttributionAdapter` conform to the internal [AgentAttributionAdapter contract](../../Sources/AgentMonitorCore/AttributionAdapters/AgentAttributionAdapter.swift) and are registered by [AttributionAdapters](../../Sources/AgentMonitorCore/AttributionAdapters/AttributionAdapters.swift). They live inside `AgentMonitorCore`; they have no OS access, UI dependencies or messaging responsibilities. The internal protocol is a source-code extension boundary, not a public third-party plugin API.

| Owner | Contract |
|---|---|
| Provider adapter | Declare provider identity, recognized executable shapes and accepted invocation names, allowlisted environment keys, required runtime observations. Validate/normalize session markers, decode runtime evidence, supply an exact detached-runtime link, and interpret shared-runtime evidence. |
| `ProcessArguments` | Decode the bounded argument/environment buffer, retain only the registry's allowlisted keys, and delegate marker interpretation. A malformed marker from any adapter rejects the marker set; a valid other provider cannot hide it. |
| `NativeProcessReader` | Perform same-user process inspection and PID/start/executable checks before and after metadata reads. Collect only the requested open-file paths or listening-socket paths; never read their contents. |
| Registry | Collect all recognition claims, restrict each adapter to its declared inputs, and reject duplicate provider registrations and markers carrying another adapter's provider. Fixed built-in registration contains one typed adapter per provider. |
| `Monitor` | Delegate retained CPU baselines/contributions to `CounterLedger`; own footprint observations, process-lifetime history, runtime boundaries, nearest-runtime marker selection, conflict resolution and detached matching per runtime lifetime. Require one live match that predates the marker-bearing process. |
| `MonitoringSession` | Compose serial acquisition/accounting, metadata enrichment and independent delivery. |
| Presentation | Consume resolved provider/session evidence and the core's shared-runtime classification. Own labels, sorting, filters and grouping; never recognize providers from executable paths or environment keys. |

An adapter's `runtimeObservations` declares `openFilePaths` or `listeningSockets`. Its `runtimeEvidence` decodes those observations into writer-thread IDs and listener paths without deciding process ownership. `runtimeLink` supplies either an exact writer-thread ID or an exact listening-socket path; the shared monitor compares that link against candidate metadata and enforces lifetime and uniqueness constraints. Codex requests file paths and decodes UUID writer-lock names; Claude requests listeners and links its validated inbox marker. No adapter receives the full environment, and the Claude adapter never declares or reads the messaging token.

### Recognition conflicts and registration order

Provider registration rejects duplicate providers. Runtime recognition is a set of claims, not a first-match lookup. Multiple adapters recognizing the same runtime establish a runtime boundary but leave provider and thread ambiguous, even when a descendant has a marker or a single writer candidate. Registration order cannot select a winner. A detached candidate must have exactly the marker's provider claim; conflicting candidates cannot supply a runtime. Nested providers retain both markers until the nearest unambiguous runtime selects the relevant provider. Missing, malformed and conflicting evidence remain distinct.

`ProcessSample.runtimeProvider` delegates to the built-in registry for the unique recognized provider. `Monitor`, native metadata enrichment and marker parsing use that same registry in production; internal injection permits tests to demonstrate the complete path with a synthetic adapter. `HeavyProcess.isSharedRuntime` checks the runtime lifetime and delegates evidence interpretation to the registered built-in provider; presentation supplies only the wording. No provider-specific recognition switch belongs in the sampler, ancestry resolver or UI.

## Harness session registries

CLI/TUI monitoring, CPU diagnosis and native collection use local evidence only. The monitor never invokes `claude agents --json`; disabling nonessential traffic did not establish an offline guarantee. Claude runtimes without local session evidence remain `runtimeOnly`, and provider-listed session names are unavailable. Native markers, retained ancestry, writer paths and listening-socket evidence continue to supply only their established attribution. Codex registry integration remains [deferred](../decisions/codex-session-registry.md).

The dormant listing declarations/parsers, execution readers, cadence, runtime bindings and listed-name fields have been retired together with their fixture-only paths. Report/diagnosis schemas omit `sessionRegistry`, `sessionName`, lookup outcomes and provider-lookup failure codes. Historical listing observations remain in [research](../research/claude-runtime-attribution.md); they establish neither current offline safety nor a supported source.

## Harness adapters

Everything specific to one agent harness belongs to that harness's adapters; shared mechanisms stay in the host. Attribution lives in the core adapter described above. Provider messaging has no implementation. Terminal focus is selected by terminal application, not by harness. A new harness such as OpenCode adds an `AgentProvider` case with an explicit JSON schema decision, an attribution adapter with exact positive and conflicting fixtures, and only the optional facets the harness supports. Process lifetimes, ancestry, conflict resolution, bounded commands and action verification remain shared.

The `AgentProvider` enum and marker types are unchanged by the adapter extraction. The report and diagnosis schemas expose only locally supported attribution evidence. Terminal focus stays in `TerminalFocusAdapter` and is not required for attribution; messaging adapters are absent. Actions and sampling use the same attribution path, preserving process identity checks and launch-origin limitations described in [action contract](diagnosis-actions.md#process-and-session-actions).

Contract tests use a synthetic adapter to prove that custom recognition, declared marker keys, observation requests and detached-runtime evidence flow through the shared pipeline. They also cover duplicate registrations, overlapping recognition in both orders, malformed markers, built-in executable shapes and writer-path decoding. The existing attribution fixtures remain the behavioral oracle for nested agents, same-directory sessions, PID reuse, detached children and uncertainty. See [development guidance](../development.md#changing-attribution-adapters).

## Deferred adapter capabilities

Optional session inspection and provider-specific metrics remain proposals; OS CPU/footprint measurements stay in the shared collector. Preserve typed values and units if inspection is added, and keep display strings in presentation. External plugins, dynamic loading and generic capability frameworks are excluded from the current implementation.

A third provider requires an explicit revision of the closed provider enum and JSON schema before it can participate. A future external adapter may use a versioned subprocess protocol with validated stable provider identifiers; its transport, discovery, installation and trust policy remain deferred until requested. The internal built-in interface does not promise binary or wire compatibility for third-party extensions.

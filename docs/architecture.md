# Architecture

Agent Monitor separates measurement, attribution and presentation so every interface answers the same question: which coding agents, sessions and processes are using CPU or memory, and in which working directories?

## Read by task

| If you are changing… | Read |
| --- | --- |
| CPU and memory accounting | [CPU and memory accounting](architecture/accounting.md) |
| Acquisition and adaptive sampling | [Acquisition and adaptive sampling](architecture/acquisition.md) |
| Display windows and bounded delivery | [Display windows and bounded delivery](architecture/display-windows.md) |
| Attribution and offline runtime | [Attribution and offline runtime](architecture/attribution.md) |
| CPU diagnosis and verified actions | [CPU diagnosis and verified actions](architecture/diagnosis-actions.md) |
| Shared presentation state | [Shared presentation state](architecture/presentation-state.md) |
| Terminal presentation and host | [Terminal presentation and host](architecture/terminal.md) |
| Contributor overview and resource history | [Contributor overview and resource history](architecture/contributors.md) |
| Native app lifecycle and interaction | [Native app lifecycle and interaction](architecture/native-app.md) |

The guides below describe accepted contracts and current implementation. They do not close the [remaining accounting and acceptance work](../PLAN.md#resource-accounting-priority). Frozen point attribution is implemented; interval-supported ownership and sustained acceptance retain their separate gates. [Dated research](research/README.md) records evidence rather than shipping guarantees.

## Product experience

The [product contract](product.md) requires Mac and TUI to answer which agents, sessions and processes consume CPU or memory, with their workload CWDs visible in context. Every presentation decision serves comparison of multiple contributors. Use aligned tables, meaningful graphics and structured disclosure; explanations and arguments belong on demand. Measurement semantics, ownership and action guards stay shared, while native and terminal interaction differ.

**Current behavior:** overview and process-group headings lead with provider/session identity, followed by compact workload directory context. Contributor rows pair executable and frozen CWD. Session labels use locally verified provider/session IDs; provider-listed names are unavailable under the offline runtime contract. Directory summaries never establish ownership or invent session names.

## Purpose and status

Agent Monitor exists to identify the agents and processes responsible for CPU and memory use. Sampling and attribution must be reusable by text output, an optional terminal UI, and a native menu bar app. See [PLAN.md](../PLAN.md) for open work and scope, and the [development guide](development.md#validation-coverage) for validation limits.

## Resource visibility requirements

User priority clarified on 2026-10-23 and sharpened on 2026-10-25 in the [product contract](product.md): a full, reliable understanding of agent load and memory is the primary acceptance criterion. Coverage and correct attribution take precedence over collection cost and presentation convenience. Substantially underreporting a busy agent workload is a product failure; documenting that failure does not satisfy the requirement.

- **Transparent attachment:** observe already-running agents without requiring relaunch or cooperative worker instrumentation. A future event source must establish target access, lifecycle identity, loss detection and supported deployment before implementation; no complete transparent backend is currently validated.
- **Population:** agent/session resource totals must account for the relevant observed processes independently of display thresholds. Below-threshold workers and their memory must not disappear from totals merely to shorten a table. CPU and memory need separately stated populations and observation times; a sum of departed workers' last footprints is not current memory use.
- **Lifetime coverage:** evaluate short-lived workers and CPU consumed before exit, not just long-running processes. A shorter polling interval is an improvement only to the extent demonstrated by measurements; it does not prove complete accounting. UI refresh and collection choices must serve coverage rather than silently sacrifice it.
- **Responsibility:** identify the responsible process lifetimes and agents from verifiable evidence. Preserve the distinction between launch origin and current responsibility for shared services. Unattributed, ambiguous, unreadable and unobserved work must remain explicit; host usage minus measured agent usage is not a measured system-load category.
- **Evidence:** validate resource accounting against independent CPU-work and memory oracles, including churn, overlapping workers, nesting, exit and PID reuse. Prevent double counting as well as undercounting. Show coverage limitations where users interpret totals, and do not present a partial sum as the complete load.

The following sections describe the current implementation, which does not yet meet these requirements: collection can miss short-lived work and final exit CPU. Display filters no longer reduce observed session/icon totals and history refreshes with each report. The [active accounting work](../PLAN.md#resource-accounting-priority) tracks the gap. The [exited-descendant counter decision](decisions/exited-descendant-cpu.md) remains a correctness constraint; the new priority does not make unsafe counter addition valid.

## Current implementation

The collector, presentation layer and hosts have distinct ownership. [Shared state](architecture/presentation-state.md#current-implementation) preserves exact-lifetime selection, sticky disclosure and pin identities without retaining stale measurements.

## Attribution evidence and inspection scope

Codex and Claude attribution uses [local markers, verified ancestry and adapter-requested writer/listener evidence](architecture/attribution.md#attribution-evidence-and-inspection-scope). Shared runtimes, missing evidence and conflicts remain explicit; working directories never establish ownership.

## CPU accounting

CPU is measured from [cumulative user/system counter deltas](architecture/accounting.md#cpu-accounting) in one-core units: 100% means one logical CPU. Unique endpoint identities prevent duplicate credit. Host occupancy is a separate population and cannot supply missing agent CPU.

### Retained counter accounting

The ledger retains [compatible last-good baselines](architecture/accounting.md#retained-counter-accounting) through missed reads, with bounded state and conservative eviction. Recovery, interval exclusions and newborn baselines keep their original endpoints; unsupported elapsed-time cuts are not prorated.

### Independent acquisition

A [serial native acquisition worker](architecture/acquisition.md#independent-acquisition) runs independently of metadata and publication workers. Default acquisition is 100 ms; background enrichment and consumers cannot silently replace intermediate CPU observations.

#### Pressure disclosure

Capacity limits may [collapse identity detail or shorten retained history](architecture/display-windows.md#pressure-disclosure). They must preserve admitted CPU, stated populations, uncertainty and loss boundaries; collapsed records never invent actionable process identities.

### Adaptive acquisition

Adaptation is off by default. Its [bounded controller](architecture/acquisition.md#adaptive-acquisition) changes a global requested interval using qualified workload observations, with explicit settings, uncertainty holds and wakeup rules. Modeled usefulness does not establish safe slower defaults or sustained cost acceptance.

### Supplemental inspection observations

Optional TUI inspection can take [bounded discovery readings](architecture/acquisition.md#supplemental-inspection-observations) between complete scans. They remain historical candidates until the next census verifies admission; they cannot establish current membership, final-exit CPU or complete coverage. The experiment defaults off.

## Independent display windows

Interactive hosts normally display every five seconds; text/JSONL every second. Reports combine [whole accounting units](architecture/display-windows.md#independent-display-windows) and divide accepted CPU by their actual enclosing duration. Consumer delay is disclosed without discarding accepted work.

## Memory observations

Current memory is the [latest physical footprint](architecture/accounting.md#memory-observations). The kernel task peak may survive a freed allocation but can reset on exec; neither individual peaks nor departed footprints form a simultaneous session total.

## Finite CPU diagnosis

Diagnosis measures [a baseline plus three one-second waits](architecture/diagnosis-actions.md#finite-cpu-diagnosis), ranks cumulative CPU across the window and returns at most ten processes. It is a separate bounded operation with qualified partial results.

### Window measurements

Diagnosis retains [accepted contributions through departure](architecture/diagnosis-actions.md#window-measurements), compares compatible windows and distinguishes missing counters from measured zero. Host and process populations have separate coverage rules.

### Enrichment, response and boundaries

Diagnosis enriches selected lifetimes after collection and reports their latest supported evidence. Its [versioned response, limits, error behavior and side-effect exclusions](architecture/diagnosis-actions.md#enrichment-response-and-boundaries) are explicit.

### Interactive CPU diagnosis

Mac and TUI own [one cancellable diagnosis run](architecture/diagnosis-actions.md#interactive-cpu-diagnosis), independent of live history. Dismissal invalidates late results; cleanup must finish before another run. Diagnosis has no process actions.

## Boundary for multiple presentations

The core publishes [immutable typed snapshots](architecture/presentation-state.md#boundary-for-multiple-presentations); presentation derives labels and view state; hosts render and accept input. JSON remains flat, and display sanitization never changes underlying identity.

## TUI contract

Terminal layout preserves [identity, resource values, selection and coverage](architecture/terminal.md#tui-contract) under constrained width and height. Scrolling, details focus, chart fallback and monochrome output have explicit rules.

## Verification boundary

Shared-state and terminal tests establish [deterministic composition and transitions](architecture/terminal.md#verification-boundary). Physical terminal rendering and native input remain separate checks.

## SwiftTUI host evaluation

The application uses a narrow host around [unchanged SwiftTUI 0.14.0](architecture/terminal.md#swifttui-host-evaluation). The dependency is not forked; upstream queue/lifecycle limitations remain documented.

### On-demand process arguments

Argument inspection performs [one bounded fresh read](architecture/diagnosis-actions.md#on-demand-process-arguments) for an exact current lifetime. Selection or executable changes invalidate late results, and reading arguments never enables recording.

## Offline runtime

Agent Monitor [must not initiate Internet connections](architecture/attribution.md#offline-runtime), directly or through launched helpers. Provider listing and messaging paths lacking an offline guarantee are unavailable rather than silently invoked.

## Process and session actions

Termination and terminal focus [freeze exact targets and verify them again](architecture/diagnosis-actions.md#process-and-session-actions) before execution. Accepted requests are not confirmed completion, uncertain results are not retried automatically, and messaging is unavailable.

## Agent attribution adapters

Adapters declare and interpret [provider-specific evidence without OS access](architecture/attribution.md#agent-attribution-adapters). The host performs allowlisted reads and shared conflict resolution; registration order cannot choose an owner.

### Harness session registries

Production uses [local evidence only](architecture/attribution.md#harness-session-registries). Provider listing declarations, parsers and execution paths are retired; historical research is not a supported registry source.

### Harness adapters

A new harness extends the [closed provider model](architecture/attribution.md#harness-adapters) and supplies exact positive/conflicting fixtures. Lifetimes, ancestry, bounded execution and action verification remain shared.

## Deferred adapter capabilities

External plugins, generic capability frameworks and optional provider-specific metrics are [outside the current implementation](architecture/attribution.md#deferred-adapter-capabilities). Adding a third provider requires an explicit enum/schema decision.

## Resource history

Normal monitoring retains [bounded working state, a recent accounting window and a scalar chart](architecture/contributors.md#resource-history). No automatic disk recording or extra chart-only archive exists. Contributor lanes and aggregate history have different populations and projections.

## Contributor overview and recent activity

Main contributors exposes [significant observed work, recent contributors and a quantified remainder](architecture/contributors.md#contributor-overview-and-recent-activity). Folding, filtering and pinning change inspection, not total populations or the overall CPU lane.

### Ownership and executable hierarchy

The tree follows [corroborated root, exact session, executable/workload directory and exact lifetime](architecture/contributors.md#ownership-and-executable-hierarchy). Headings omit lifetime multipliers; current process counts and retained populations remain distinct.

### Constrained overview presentation

The [accepted ledger](architecture/contributors.md#constrained-overview-presentation) aligns CPU history and values with identity and workload context. Selection, disclosure, inspection and verified actions remain separate. Mac and TUI use platform-appropriate controls over the same state.

### Immutable compact history

History freezes each accepted contribution’s [point label, workload directory, executable and role](architecture/contributors.md#immutable-compact-history). Later evidence cannot silently move earlier CPU to a new owner. Whole-unit retention preserves boundaries and explicit recovery.

### Statistics and lifecycle

Current CPU, current memory, recent workers and recent CPU-seconds answer [different questions](architecture/contributors.md#statistics-and-lifecycle). The target recent range is 60 seconds within bounded storage; resets, pauses and pressure preserve explicit lifecycle and coverage semantics.

## Native menu bar app

An [AppKit status item and detachable popover](architecture/native-app.md#native-menu-bar-app) host SwiftUI content. One collection lifecycle serves the panel and live icon; sizing, focus, menu tracking and cancellation preserve retained view state.

### Reusing unchanged collection context

Attribution caching reuses only [validated context](architecture/native-app.md#reusing-unchanged-collection-context). Current resource readings and timestamps are rebuilt on every scan, and changes invalidate affected descendants and detached lookup results.

### Acceptance cost instrumentation

Opt-in profiling records [bounded numeric stage/thread timings](architecture/native-app.md#acceptance-cost-instrumentation) without process identities. Overlapping totals are not additive, and collector-plus-helper CPU remains the acceptance metric.

### Native interaction contract

Native [sorting, row selection, disclosure, inspection and contextual help](architecture/native-app.md#native-interaction-contract) share the presentation model. Keyboard and action acceptance require production input evidence as well as headless checks.

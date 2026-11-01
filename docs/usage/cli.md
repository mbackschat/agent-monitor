# Reports, diagnosis and session grouping

Run finite reports for a snapshot, `diagnose cpu` for a short investigation, or JSONL for machine-readable observations. All commands use the installed executable.

[Usage guide](../usage.md) · [All usage topics](README.md)

## Finite CPU diagnosis and local guides

```sh
agent-monitor guide
agent-monitor diagnose cpu
agent-monitor diagnose cpu --json
agent-monitor diagnose cpu --json-schema
agent-monitor guide semantics
agent-monitor guide diagnostics
agent-monitor guide actions
agent-monitor guide tui
```

`diagnose cpu` takes a baseline followed by three one-second waits and scans, then returns the top ten measured current-user lifetimes, including nonagents and the invoking agent but excluding the monitor. There are no tuning options; explicitly supplied report controls are rejected, including default-valued controls. Report thresholds, streaming and grouping do not alter diagnosis. Collection and native metadata inspection add runtime beyond the waits; help, guides and schemas run locally without any sampling or provider queries.

### Read the diagnosis ranking

Contributors rank by observed CPU-seconds, with exact PID/start identity breaking ties. Mean and peak CPU describe each lifetime's own measured coverage; a brief high-rate burst does not outrank more measured CPU. Newborn intervals include zero before birth, earlier contributors retain their measured CPU and latest footprint, and omitted contributors remain in population totals.

`elapsedSeconds` includes scans on the Mach clock, excluding sleep; display timestamps do not define it. Missing observations and CPU after the last observation remain uncounted. Coverage counts observations, not complete visibility or unique inaccessible processes.

### Compare host occupancy

Host occupancy appears beside measured process contribution. Its valid intervals are duration-weighted, with separate coverage and no single capacity when the logical CPU count changes. It is unweighted occupancy (100% = one logical CPU), not equivalent performance/efficiency-core capacity.

Never subtract process totals from it or infer an idle machine from low measured CPU. Missing values are omitted in JSON and explained in text, not invented as zero.

### Diagnosis JSON contract

Diagnosis JSON is one compact document with independent `schemaVersion: 1`; report JSONL also uses its own schema version 1. The [diagnosis schema](../../Sources/AgentMonitorPresentation/Resources/diagnosis.schema.json) rejects unknown properties. Results include numeric coverage, exact identities, bounded executable labels, attribution evidence and timestamps and stable diagnostic codes.

Names and paths are untrusted data. Available attribution is the latest association, not ownership of all window CPU or exclusive ownership of a shared daemon. `notObservedAtEnrichment` does not prove exit; unavailable metadata remains distinct from an unobserved lifetime. Read `guide semantics` and `guide diagnostics` for the published values and next observations.

### Exit statuses and action boundaries

Exit **0** includes valid empty or partial results; **1** emits `collectionFailed` and an explanation on stderr with no success document; invalid usage exits **64**. JSON stdout has no banners, colour or guidance.

Diagnosis does not message, signal, change focus or read transcripts/tokens. Native reads consume resources. Production diagnosis performs no provider listings or provider subprocess launches; no lookup attempt or failure is fabricated for unavailable services. Actions require a separate request and fresh identity verification; `--pid` resolves at invocation rather than binding to a prior diagnosis.

### Inspect memory or repeat reports

For finite memory or repeated observations, use existing reports:

```sh
agent-monitor --json --all-processes --memory-gb 1 --samples 1
agent-monitor --json --all-processes --samples 3 --interval 2
```

With at least one nonzero threshold, report display filters match strictly above any enabled threshold: CPU **or** physical footprint in decimal GB, not RSS. Zero disables that resource filter. Locate a known PID by its PID/start record in the returned findings; there is no PID-report filter. See [report output](#text-and-jsonl-output) for the separate report controls.

## Session grouping

`--group session` groups text output and the interactive process view by launch session. The TUI opens in Main contributors; press `v` for process inspection or `g` to enter it and switch grouping. → expands a group and ← collapses it; `i` opens process Details without changing disclosure. New groups start collapsed; previously expanded session/root groups reopen when the same identity returns after filtering. Explicit collapse stays collapsed. The monitor remembers up to 256 absent expanded groups, evicting the oldest expansion choices first; visible or pinned groups are not evicted.

### Restore inspection and disclosure

Both interactive views also restore the inspected process's details when that exact PID/start lifetime returns. While it is missing, no stale details are shown. Selecting another row, changing disclosure/grouping or pane mode, or opening an action panel cancels that pending restoration, so a returning process cannot override a new inspection choice.

One process is inspected at a time: inline in the Mac app and in the TUI's details pane. Expansion memory lasts for the current collection/view; closing the native panel or restarting the TUI clears it.

### Fold groups at the current level

**Shift+←/→** collapses/expands session groups at the current level in both live views:

| Selection context | Affected groups |
| --- | --- |
| Top-level row or no selection | All displayed session groups, including pinned groups. Individually pinned processes also count as top-level rows. |
| Child process in an expanded group | Only its containing session; siblings hide or reappear. Collapse moves selection/focus to the parent. |
| Flattened single-process Mac row | Treated as top-level, but the row itself has no group disclosure. |
| Processes view without pinned session groups | None; the command has no effect. |

Missing groups are unaffected, repeated presses are idempotent, and choices follow the same sticky expansion rules. Process details remain single-target. The command is disabled in action panels and editors.

### Read group counts and totals

TUI session rows show **#N** in **PID/#** for their process count; child rows show their actual PID. **├─ / └─** mark child membership in the executable column (or the compact identity line), keeping numeric CPU/memory columns aligned. A separately pinned process is a standalone row. The group count covers its measured display-window population, including filtered and departed contributors; it differs from the overview’s latest-sample **Procs** count, as explained in Help.

Unpinned groups appear only when at least one member passes the display filters and is not separately pinned. Explicitly pinned groups remain visible even when all their children are filtered.

Groups show the project, session, process count, and CPU/memory totals of **all observed session members**, including processes hidden by display filters. These totals do not recover work missed between scans. `~` marks a partial total when measurements are missing. CPU/memory sorting orders groups by their totals; PID sorting uses each group's lowest observed PID.

### Interpret session evidence

Unresolved or ambiguous processes stay separate even when they share a project or runtime. Session evidence identifies launch origin: a shared Gradle, Kotlin, or MCP daemon may later serve other sessions. See [attribution evidence](../architecture.md#attribution-evidence-and-inspection-scope) for the exact interpretation and inspection scope.

### Local attribution limits

A Claude Code runtime can lack its own session marker, and macOS system binaries can hide their environment. Automatic `claude agents --json` listings are disabled because provider CLI startup cannot be guaranteed offline. Such runtime/child ownership may therefore remain unresolved; native marker, retained ancestry and verified local descriptor/socket evidence still apply. Diagnostics explains this capability limit.

### Shared runtimes

**Shared runtime** identifies a Codex runtime process with multiple distinct thread writer descriptors and no exact attributed thread. This describes shared runtime usage, rather than a failed workload lookup. It appears consistently in process rows, session groups, details, text output and action targets. Its singleton group remains separate from exact sessions and unresolved workloads.

JSONL retains the original ambiguous evidence and candidate thread IDs. A runtime without a terminal still cannot be focused; the label does not establish a terminal-client mapping.

### Working directories

Project names describe the displayed workloads’ working directories, not session ownership. Session groups show one compact CWD path or **N dirs**, including when one directory is nested inside another. Missing directory evidence is qualified as **CWD unavailable**. These summaries do not establish separate projects or repository roots.

Grouped TUI child rows and Mac process rows show each worker’s compact CWD beside its executable, including sessions with several directories. Matching path suffixes gain leading components; full paths remain in details and native tooltips. A **shared runtime** has no project subtitle because its launch directory may belong to another session.

Expanded details retain both the work directory and runtime directory. This labeling does not change attribution or grouping identities.

## Text and JSONL output

With no options, the monitor acquires at a requested 100 ms period and prints one resolved one-second accounting window after its baseline. `--samples 0` watches until Ctrl-C; `--interval` controls the requested acquisition period (0.1–60 seconds). Each text report includes a UTC timestamp.

Text reports and the `kill`, `message` and `focus` commands use colors only when their output goes to a terminal: the report header in blue, process lines and unresolved sessions in yellow, secondary details in gray, accepted results in green and errors in red. Pipes and files get plain text, and `--no-color` or `NO_COLOR=1` turns colors off everywhere. JSONL is never colored; `--no-color` is accepted with `--json` and has no effect there.

```sh
# Continuous text reports every two seconds
agent-monitor --samples 0 --interval 2

# Three machine-readable reports
agent-monitor --json --samples 3

# Print the report schema without sampling
agent-monitor --json-schema
```

### Report JSONL contract

JSONL contains one complete, compact JSON object per line/report. It retains the flat process list and full attribution evidence, including ambiguous candidate IDs. Schema version 1 retains required `observedFindings`, a flat list independent of display thresholds alongside the filtered `findings`. Both use the same process shape and requested scope.

The required report-level `cpuAccounting` object contains: optional `hostBusyPercent`, `logicalCPUCount`, `measuredUserPercent`, `unmeasuredLifetimeCount` and optional `previousScanSeconds`. Unavailable optional fields are omitted. Report and nested objects reject unknown fields.

Findings remain flat; evidence values describe locally supported attribution.

`--group session` is incompatible with `--json` and `--json-schema`.

### Acquisition and publication coverage

The optional `cpuAccounting.acquisition` object reports run/scan identity, requested QoS, requested/achieved periods, scan work, resolution delay and prompt-capture outcomes. On-demand Diagnostics shows the achieved acquisition period in milliseconds and resolution delay; neither a requested interval nor a successful prompt read guarantees complete coverage.

Each window also reports `acquisitionCoverage`: scan count, maximum gap and overrun count across all scans. `publicationCoverage` distinguishes source units from admitted history units and records backlog-coalesced counts, maximum unit span and the enclosing coalesced time range.

Under delivery pressure, `collapsedContributions` preserves exact older CPU, interval counts and sampled memory maxima with a time range and provable worker-count bounds; identity/category detail loss is explicit. Include collapsed CPU when summing detailed records. A current population exceeding the remaining capacity fails explicitly.

### Include arguments deliberately

`--commands` includes command arguments in reports and process details. Arguments can contain credentials or other sensitive values and are omitted by default. Session IDs and project paths can still appear without this option.

For the complete option reference and defaults, run `agent-monitor --help`.

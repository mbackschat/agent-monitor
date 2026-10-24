# CPU accounting probes

These development-only probes support the [2026-10-23 CPU investigation](../../docs/research/cpu-accounting.md#controlled-exit-and-scheduler-probes--2026-10-23). They are not installed products or a monitoring backend. Retained results are in the [measurement dataset](../../docs/research/cpu-exit-probes-2026-10-23.json). Run from the repository root on macOS; run temporary measurements through [clean-build.py](../../scripts/clean-build.py) and analyze their output before its scratch directory is removed. Retention requires an explicit evidence decision; Git ignoring a file is not a retention policy.

| Probe | Purpose |
| --- | --- |
| [exec-identity.c](exec-identity.c) | Gate an owned child across same-binary exec with a changed synthetic environment and higher allocation; compare fresh/retained task-name-port audit tokens, native birth, image UUID, name and footprint peak. |
| [exit-race.py](exit-race.py) | Register `NOTE_EXIT` before each of 40 owned workers starts; attempt final `proc_pid_rusage` immediately after notification while an independent supervisor reaps with `wait4`. |
| [footprint-peak.c](footprint-peak.c) | Compare current and kernel peak physical footprint before, during and after an owned child touches and frees 64 MiB; `--exec` also verifies reset after replacing the executable without changing birth identity. |
| [task-port.c](task-port.c) | Hold a task-name port across one owned worker's exit and reaping, then retry `TASK_ABSOLUTETIME_INFO`. |
| [trace-workload.py](trace-workload.py) | Four waves of four owned CPU workers, each touching 8 MiB. The default requests 50 ms CPU per worker; `--mixed` requests 10, 50, 200 and 1,000 ms across the waves. Parent `wait4` results provide the independent CPU ledger. |
| [trace-summary.py](trace-summary.py) | Resolve xctrace XML references and sum `Running` thread-state durations only for the controlled ledger's worker PIDs. Use the matching trace and ledger from one run; this diagnostic parser does not resolve arbitrary PID reuse or agent ownership. |
| [LivePipeline.swift](LivePipeline.swift) | Profile optimized production collection at 100 ms with an early one-second report and subsequent five-second reports. Retain every native period, per-window coverage/heap/history diagnostics and own-process CPU plus separately reported reaped provider-helper CPU. Provider listings require explicit `--providers`; UI is excluded. |
| [LiveTiming.swift](LiveTiming.swift) | Record two twenty-second raw-scan windows at 100 ms and 10 ms waits using production reader/accounting, without metadata, provider queries or UI. Retain per-scan aggregate timing/host activity and new/absent counts, not process identities. |
| [CollectionCost.swift](CollectionCost.swift) | Measure optimized production collection at 100 ms and one second, retaining only aggregate timing/counts. Provider listings and UI are disabled. |
| [Conservation.swift](Conservation.swift) | Run the mixed worker fixture under the production collector, without provider listings/UI, and compare accepted raw CPU contributions with `wait4`. `--fast` instead tests a 10 ms scan prototype with metadata only on first observation or executable change; it is not production collection and does not establish attribution freshness. |

## Exit probes

```sh
mkdir -p .build/cpu-coverage
python3 Tools/CPUAccountingProbe/exit-race.py > .build/cpu-coverage/exit-probe.json
clang -O2 Tools/CPUAccountingProbe/task-port.c -o .build/cpu-coverage/task-port
.build/cpu-coverage/task-port > .build/cpu-coverage/task-port.json
```

## Native collection

Compile one main file at a time. Core's `package` declarations require `-package-name`; the process reader and attribution adapters are the actual production sources. Conservation records counters only for direct children of the disposable parent, rejects observed PID reuse, and never queries real provider sessions. The CPU sum retains contributions across reports for comparison; it is not a claim that the live table retains departed workers.

```sh
swiftc -parse-as-library -O -swift-version 6 -package-name agent-monitor Sources/AgentMonitorCore/*.swift Sources/AgentMonitorCore/AttributionAdapters/*.swift Tools/CPUAccountingProbe/CollectionCost.swift -o .build/cpu-coverage/collection-cost
.build/cpu-coverage/collection-cost > .build/cpu-coverage/collection-cost.jsonl
swiftc -parse-as-library -O -swift-version 6 -package-name agent-monitor Sources/AgentMonitorCore/*.swift Sources/AgentMonitorCore/AttributionAdapters/*.swift Tools/CPUAccountingProbe/Conservation.swift -o .build/cpu-coverage/conservation
.build/cpu-coverage/conservation > .build/cpu-coverage/conservation.jsonl
.build/cpu-coverage/conservation --fast > .build/cpu-coverage/conservation-fast.jsonl
```

## Scheduler trace comparison

A single-process `--launch` trace did not include the fixture children in its target process inventory. The successful comparison used `--all-processes`, started the owned workload four seconds after starting the recorder, and allowed recording to finish before export. The raw-span interpreter failed conservation in a second run (246% of its CPU oracle) and must not be used as a trusted accounting backend. A ten-second trace generated gigabytes of temporary data and took minutes to finalize/export on the test machine. Raw traces contain system-wide observations; retain only the owned-worker summary in the repository. The workload's eight-mebibyte allocation is not a measured physical-footprint peak.

```sh
python3 scripts/clean-build.py run -- python3 - <<'PY'
import os
import pathlib
import subprocess
import time

folder = pathlib.Path(os.environ['AGENT_MONITOR_SCRATCH'])
with (folder / 'trace.log').open('w') as log:
    recorder = subprocess.Popen([
        'xcrun', 'xctrace', 'record', '--template', 'System Trace',
        '--time-limit', '10s', '--output', str(folder / 'controlled.trace'), '--all-processes',
    ], stdout=log, stderr=subprocess.STDOUT)
    try:
        time.sleep(4)
        with (folder / 'oracle.json').open('w') as output:
            subprocess.run([
                '/usr/bin/python3', 'Tools/CPUAccountingProbe/trace-workload.py', '--mixed',
            ], stdout=output, check=True, timeout=60)
        if recorder.wait(timeout=600):
            raise RuntimeError('Recorder failed; do not interpret this run')
    finally:
        if recorder.poll() is None:
            recorder.terminate()
            recorder.wait(timeout=30)
subprocess.run([
    'xcrun', 'xctrace', 'export', '--input', str(folder / 'controlled.trace'),
    '--xpath', '/trace-toc/run[@number="1"]/data/table[@schema="thread-state"]',
    '--output', str(folder / 'threads.xml'),
], check=True)
subprocess.run([
    'python3', 'Tools/CPUAccountingProbe/trace-summary.py',
    str(folder / 'threads.xml'), str(folder / 'oracle.json'),
], check=True)
PY
```

Compare every worker and duration group as well as the aggregate. Confirm all workers fall inside the recorded interval; a plausible aggregate alone is insufficient. `Running` spans describe scheduler occupancy, while `wait4` reports kernel CPU accounting, so small differences are expected. The exported state table can contain spans outside actual lifetimes, including suspicious long `Running` spans with missing termination evidence in the failed trial; they are not process birth/death evidence. The parser includes these suspicious Running spans, which explains why its output must not be trusted as conserved CPU. The parser does not diagnose trace-buffer loss, establish exact session attribution or provide a complete memory oracle.

## Kernel footprint peak

```sh
clang -Wall -Wextra -O2 Tools/CPUAccountingProbe/footprint-peak.c -o .build/cpu-coverage/footprint-peak
.build/cpu-coverage/footprint-peak --exec > .build/cpu-coverage/footprint-exec.json
```

The child waits at controlled allocation/free boundaries, then optionally execs `/bin/sleep`; the parent verifies the replacement before reading the final counters. No other process is signaled or suspended.

## Raw timing under live load

Use a live workload only when the user explicitly authorizes observation; otherwise use disposable owned workloads. Run serially with other probes/builds to avoid adding their cost to the measurement. The retained [live-load trial](../../docs/research/cpu-accounting.md#live-load-timing--2026-10-23) is observational, not a CPU-conservation or session-attribution oracle.

```sh
swiftc -parse-as-library -O -swift-version 6 -package-name agent-monitor Sources/AgentMonitorCore/*.swift Sources/AgentMonitorCore/AttributionAdapters/*.swift Tools/CPUAccountingProbe/LiveTiming.swift -o .build/cpu-coverage/live-timing
.build/cpu-coverage/live-timing > .build/cpu-coverage/live-timing.jsonl
```

Compute nearest-rank p50/p99 from each run's `periodSeconds` and `scanSeconds`. Host occupancy is weighted by period; initial observations without a baseline are excluded from period/host summaries and discovery counts. `absentLifetimes` describes disappearance from readable samples, not proven exit. No native failure classification or worker oracle is added by this probe.

## Same-path exec identity

```sh
clang -Wall -Wextra -O2 Tools/CPUAccountingProbe/exec-identity.c -lbsm -o .build/cpu-coverage/exec-identity
.build/cpu-coverage/exec-identity > .build/cpu-coverage/exec-identity.json
```

The pipe protocol observes only the disposable child. `protocol_ok` must be true before interpreting the result; inspect return codes before using token/resource fields. The [retained trials](../../docs/research/exec-identity-2026-10-23.json) do not establish access to arbitrary targets or per-scan audit-token cost.

## Live pipeline profile

Run only with explicit authorization to observe the user's current workload. Compile the production core once with optimization, then link the profile against that object:

```sh
mkdir -p .build/probes
swiftc -module-cache-path .build/module-cache -parse-as-library -O -whole-module-optimization -swift-version 6 -package-name agent_monitor -module-name AgentMonitorCore -emit-object -emit-module -emit-module-path .build/probes/AgentMonitorCore.swiftmodule Sources/AgentMonitorCore/*.swift Sources/AgentMonitorCore/AttributionAdapters/*.swift -o .build/probes/AgentMonitorCore.o
swiftc -module-cache-path .build/module-cache -parse-as-library -O -swift-version 6 -package-name agent_monitor -I .build/probes .build/probes/AgentMonitorCore.o Tools/CPUAccountingProbe/LivePipeline.swift -o .build/probes/live-pipeline
python3 scripts/clean-build.py run -- bash -c '.build/probes/live-pipeline 121 --providers > "$AGENT_MONITOR_SCRATCH/profile.json"; python3 -m json.tool "$AGENT_MONITOR_SCRATCH/profile.json"'
```

The wrapper removes the raw result after the analysis command exits. Replace `json.tool` with a focused analysis when the complete period array is unnecessary; copy a sanitized result outside scratch only when retention is authorized. The reusable optimized object and executable stay under `.build/probes`; overwrite them on rebuild instead of creating dated copies.

The finite run drains accepted windows and records errors if collection stops. `121 --providers` runs at least ten minutes with production provider listings enabled; this requires explicit user authorization. Without `--providers`, listings are replaced with empty results. The probe does not read transcripts, retain process arguments or perform actions. Native marker/metadata reads still occur. Its scalar progress log records each window’s maximum gap and overrun count, including zero overruns. The JSON retains all native start-to-start periods, p50/p99/maximum, process CPU, reaped provider-helper CPU, sampled heap in use and peak allocator use when the allocator supplies it, plus recent-store capacity/discontinuity diagnostics. These are collector costs, not closed-panel AppKit costs. See the [retained live result and limitations](../../docs/research/menu-bar-load-cost.md#live-heavy-load-pipeline-profile--2026-10-24).

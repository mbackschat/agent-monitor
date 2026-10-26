# On-demand workload observations

This development-only recorder is ready to start when a representative build appears. It uses the production `NativeProcessReader` at a nominal 100 ms cadence, recording readable current-user processes without thresholds or provider queries. It does not run a workload, read arguments/environment/transcripts, resolve sessions, or change normal monitoring. Interpretation limits are [below](#interpret-the-file); the [development guide](../../docs/development.md#on-demand-workload-recording) owns validation and retention.

## Prepare before the workload

```sh
swift build -c release --product monitor-workload-capture
.build/release/monitor-workload-capture --help
```

Preparation does not record processes. The executable is a development target, not one of the declared release products. Rebuild after changing the reader or recorder. Record the source commit and whether the checkout is dirty alongside any retained analysis; the header identifies the capture format and OS, not the source commit.

If the default build stalls in `clang-stat-cache`, see the [restricted-environment guidance](../../docs/development.md#restricted-agent-environments) for the local fallback and cache/access setup.

## Start when explicitly requested

```sh
.build/release/monitor-workload-capture /tmp/agent-monitor-workload.jsonl
```

Startup requires no compilation after preparation. The output must not exist; choose a fresh path for each capture. Defaults are 60 seconds and 256 MiB. Optional positional arguments select seconds and maximum MiB, capped at 300 seconds and 1,024 MiB. The first limit stops capture; the disk allowance is not a duration guarantee for every process population:

```sh
.build/release/monitor-workload-capture /tmp/agent-monitor-workload-2.jsonl 120 512
```

Ctrl-C or SIGTERM requests a cancellation footer. After flushing the file, the command prints the actual duration, requested duration, scan count and stop reason to stderr. Normal duration completion exits with status 0; an early file-limit stop exits with status 2, cancellation with 130, and failures with 1. An early file-limit stop preserves the capture; retry with a fresh path and a larger explicit allowance if needed. The duration bounds admission of new scans; an in-flight native read or filesystem operation can delay shutdown. Slow scans skip missed schedule slots instead of attempting a catch-up burst. Disk space is bounded by rejecting a complete encoded scan when it cannot fit, with room reserved for a footer. This is not a heap bound: a native snapshot and its encoded representation scale with process population. Writing is synchronous and its cost can increase observed gaps; this tool is not a collector performance benchmark.

## Interpret the file

The JSONL begins with a header, contains zero or more scan records, and ends with a footer. A missing footer means interruption or failed finalization; a `readerFailure` footer still marks an unsuccessful run. `sizeLimit` means the next scan was acquired but discarded. The footer reports persisted scan count, elapsed time, recorder CPU seconds and maximum persisted listing gap/scan duration. It excludes the footer's own serialization/write cost and includes no provider-helper cost because no providers are started.

Each scan keeps exact PID/start identity, PPID, executable/name, birth/read times, cumulative CPU and raw tick/timebase fields when available, current footprint and kernel peak footprint. Structured read outcomes retain failure categories and native error values. Original absolute/continuous/wall-clock anchors and host tick arrays are preserved; each host array is `[user, system, idle, nice]`. Missing optional fields mean unavailable, never zero. Listed PIDs/outcomes can include out-of-scope users; detailed samples are restricted to the current user and exclude the recorder itself.

Group analysis by exact identity, not PID. `sampledAt - startedAt` gives age at observation; first-to-last observation spans and last-read CPU are partial evidence, not complete lifetimes or final totals. Disappearance, including `lookupUnavailable`, does not prove exit. Workers never observed have no row. Do not add cumulative CPU readings across scans, sum process memory peaks as a simultaneous peak, infer sessions from parent PID alone, or label host-minus-observed CPU as agent loss. Docker observations cover host processes, not guest workers.

Output files are created with owner-only permissions. They contain process identities and executable paths: analyze locally, retain only explicitly authorized evidence in the indexed research note, then remove raw captures. Recording is never automatic.

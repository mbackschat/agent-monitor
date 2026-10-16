# CPU accounting coverage

Research checked on 2026-10-16. This note asks which CPU consumption periodic same-user sampling counts, misses or attributes elsewhere, and which unprivileged macOS counters can close or quantify those gaps. Counter units, process identity and permission evidence remain in [macOS measurement and attribution](macos-process-attribution.md#what-can-a-headless-collector-measure-accurately). Design consequences belong in the [unapproved CPU accounting proposal](../proposals/cpu-accounting.md), not here.

Local observations used a Mac mini (`Macmini9,1`, 8 logical CPUs), macOS 27.0.1 (26A434), Agent Monitor commit `59969b7`, and disposable owned processes only. No agent workload, other user's process or provider session was measured. The probe script was not retained; its results below are single runs, not benchmarks.

## Collector behavior at the inspected commit

- [Monitor.ingest](../../Sources/AgentMonitorCore/Monitor.swift) computes CPU as `100 × Δ(user+system) / Δsample time` only when the same lifetime has a previous sample. A lifetime's first observation has no CPU value, even when it started after the previous sample.
- [NativeProcessReader](../../Sources/AgentMonitorCore/NativeProcessReader.swift) calls `proc_pid_rusage(RUSAGE_INFO_V2)` but uses only `ri_user_time`, `ri_system_time` and `ri_phys_footprint`. The reaped-children counters and `ri_proc_start_abstime` in the same structure are discarded. Lifetime identity uses `proc_bsdinfo` wall-clock start microseconds, while sample times come from `mach_absolute_time`.
- The reader keeps only records whose `proc_bsdinfo` is readable and whose UID matches the current user. Records without readable BSD information count as unreadable; the existing [CLI investigation](existing-solutions.md#local-source-observations-and-limited-agent-experiment) records the limits of that counter.
- `Monitor.finding(for:)` returns nothing for a lifetime absent from the latest sample. A process's CPU between its last sample and its exit is therefore never reported.
- Default cadences are one second for text/JSONL, five seconds for TUI and open native tables, and fifteen seconds for the closed-panel icon; see [resource history](../architecture.md#resource-history) and the [native contract](../architecture.md#native-menu-bar-app).
- [AgentLoadSummary](../../Sources/AgentMonitorCore/AgentLoadSummary.swift) sums available CPU values of live agent-associated lifetimes. History consumes it; the native icon derives its values from filtered findings. Both inherit the per-lifetime gaps above.
- The JSONL [report schema](../../Sources/AgentMonitorPresentation/Resources/report.schema.json) sets `additionalProperties: false` at report and nested object levels. `intervalSeconds` carries the configured interval, not each lifetime's achieved delta. CLI and native collection exclude the monitor's own PID from the process list.

## Platform sources

- `rusage_info_v1` and later contain `ri_proc_start_abstime`, `ri_proc_exit_abstime`, `ri_child_user_time` and `ri_child_system_time` beside the self counters already used. — Local SDK `usr/include/sys/resource.h` (child fields at lines 228–229 and 248–249 in the Xcode 27 SDK); [Apple resource structures](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/resource.h)
- `host_statistics(HOST_CPU_LOAD_INFO)` returns cumulative user, system, idle and nice ticks summed over all CPUs. `getconf CLK_TCK` reported 100 on the probe machine. — Local SDK `mach/host_info.h`; [Apple host information](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/host_info.h)
- `/bin/ps` and `/usr/bin/top` are installed setuid root on the probe machine, which is consistent with per-process counters of other users requiring privilege.

## Probe observations — 2026-10-16

Child workloads were `python3` loops terminating at a fixed `time.process_time()` value, so expected CPU is known independently of wall time.

| Probe | Observation | Limit |
| --- | --- | --- |
| Host versus current user | Over 2 s windows, `HOST_CPU_LOAD_INFO` as an unprivileged user reported 203.6% and 210.9% of one core (8 logical CPUs). Readable current-user lifetimes present in both samples summed to 149.2% and 169.1%. 219 PIDs returned no BSD information and `proc_pid_rusage(1)` failed with `EPERM`. | Two runs on one idle-ish desktop. The difference mixes system and other-user load, current-user work missed between samples and probe overhead. |
| Reaped descendants | A bash parent ran three sequential 0.5 s children and a nested bash whose own child used 0.5 s. The parent's self CPU rose 0.002 s; its child counters rose 2.006 s, including the grandchild reaped by the intermediate shell. | Every level waited for its children. |
| Observed child, then reaped | A child read at 0.816 s CPU mid-life later finished at about 1.5 s; the parent's child counters rose 1.501 s, the child's entire lifetime. | The already observed 0.816 s is counted again by any consumer that adds both. |
| Unreaped child | A forked child used 0.5 s and exited; before `waitpid` the parent's child counters were unchanged (0.000 s); after it they rose 0.500 s. | Accounting is delayed until reaping, not lost, for a parent that eventually waits. |
| Newborn baseline | A process started 0.7 ms after a baseline instant had `ri_proc_start_abstime` on the `mach_absolute_time` clock, an age of 0.903 s and 0.400 s cumulative CPU at its first observation. | The collector reports no CPU for such a first observation today. |
| Orphan | A background child of an exiting bash reappeared with parent PID 1. `launchd` counters were unreadable to the current user. | Not tested: whether any readable counter captures orphan CPU after exit. |

## Inferences

- A lifetime whose `ri_proc_start_abstime` follows the previous sample time has consumed all of its cumulative CPU inside the current interval. Comparing it with wall-clock `proc_bsdinfo` start time instead would mix clocks.
- Work that ends between samples, and the final partial interval of any observed process, can reappear only in a surviving ancestor's reaped-children counters. Adding those counters to observed lifetimes double-counts every portion already sampled; subtracting each departed, previously observed direct child's last cumulative self-plus-child CPU removes the overlap shown by the third probe.
- Reaped CPU belongs to the reaping ancestor's lifetime, not to the original process. When that ancestor is a shared runtime, the counters cannot divide the work between logical sessions.
- Orphans reaped by `launchd`, descendants whose reaping ancestor also exits before the next sample, other users' processes and unreaped zombies (until reaped) remain outside readable current-user counters.
- Host ticks bound total machine load in the same one-core unit after multiplying by logical CPU count. The remainder after current-user sums is unattributed load, not proof of other-user activity. Equal per-CPU weighting ignores performance/efficiency core differences.
- Within one report, surviving lifetimes share approximately the same interval, so CPU ordering is comparable. Mean rates over unequal lifetime coverage, as in a multi-interval window, are not.

## Unresolved empirical questions

- How much agent CPU, especially builds and tests, current sampling misses at 1, 5 and 15 second cadences.
- Whether `mach_absolute_time`, `ri_proc_start_abstime` and host tick counters stay consistent across sleep/wake.
- Whether reaped-children counters behave identically for `posix_spawn`, `exec` chains, sandboxed agents and processes that set `SIGCHLD` to ignore automatic reaping.
- How host tick totals compare with Activity Monitor's CPU load presentation, and their resolution at short intervals.
- How often a reaping ancestor is a shared runtime in real Codex or Claude workloads.

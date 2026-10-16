# CPU accounting coverage

Research checked on 2026-10-16. This note asks which CPU consumption periodic same-user sampling counts, misses or attributes elsewhere, and which unprivileged macOS counters can close or quantify those gaps. Counter units, process identity and permission evidence remain in [macOS measurement and attribution](macos-process-attribution.md#what-can-a-headless-collector-measure-accurately). Accepted semantics belong in [architecture](../architecture.md#cpu-accounting), with deferred work in the [exited-descendant CPU decision](../decisions/exited-descendant-cpu.md).

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
- `host_statistics(HOST_CPU_LOAD_INFO)` returns cumulative user, system, idle and nice ticks summed over all CPUs; `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` returns the same four tick states per logical CPU. `getconf CLK_TCK` reported 100 on the probe machine. — Local SDK `mach/host_info.h` and `mach/processor_info.h`; [Apple host information](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/host_info.h)
- The external review cited XNU calling `update_rusage_info_child` in both the automatic-reaping exit path and `reap_child_locked`, and caching or rate-limiting third-party `host_statistics` requests. These locations were not re-inspected for this note. — [kern_exit.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_exit.c#L2368), [host.c](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/host.c#L703)
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

## Review follow-up — 2026-10-16

An external review of the CPU accounting proposal, since implemented as the [architecture contract](../architecture.md#cpu-accounting), tested the counters further with owned processes on the same OS build. Rows marked *reviewer* were not repeated here; rows marked *reproduced* were rerun for this note with disposable owned processes.

| Evidence | Observation | Source and limit |
| --- | --- | --- |
| Automatic reaping | Two forked children using 0.3 s each raised the parent's reaped-children counters 0.600 s with `waitpid` and **1.200 s** with `SIGCHLD` set to `SIG_IGN`. | *Reproduced* (`python3`, `os.fork`, ctypes `proc_pid_rusage`); the reviewer observed the same doubling at 0.121 s per child. CPU of a never-observed child is doubled; no observation credit exists to offset it. |
| Nested collection | Grandchild C had 0.100 s observed; intermediate B, whose last observed child counters were zero, collected C and exited before the next sample; ancestor A then received C's full 0.200 s. Direct-child credit at A missed C's observed 0.100 s and recounted it. | *Reviewer*: native owned-process reproduction and an arithmetic replay. |
| Zombie readability | A zombie's `proc_pid_rusage` remained readable while `PROC_PIDTBSDINFO` returned `ESRCH`, so the current reader skips it. | *Reviewer*, native probe. |
| Other topologies | `posix_spawn` children rolled up like forked ones. Across `exec`, start time stayed identical and cumulative self CPU kept increasing. Separate PID/start identities prevented credit transfer under PID reuse. | *Reviewer*: native probes for spawn/exec; identity-key replay for PID reuse. |
| `host_statistics` caching | An ad-hoc-signed, linker-signed compiled probe polling `HOST_CPU_LOAD_INFO` saw tick deltas 87, 82, 81 and then five zeros at 0.1 s; 0.25 s was irregular (27 followed by 379); 1 s was regular. | *Reproduced*; the reviewer saw unchanged counters then a catch-up at 0.1 s. A successful zero-delta read is stale data, not idle CPU. |
| `host_processor_info` | The same kind of binary summing `PROCESSOR_CPU_LOAD_INFO` over all CPUs saw regular deltas of 79–87 ticks at 0.1 s and 199–203 at 0.25 s over twelve reads each. | *Reproduced*, one run per cadence: no caching observed at the tested cadences, not proof that the call is never cached. |

## Inferences

- A lifetime whose `ri_proc_start_abstime` follows the previous sample time has consumed all of its cumulative CPU inside the current interval. Comparing it with wall-clock `proc_bsdinfo` start time instead would mix clocks.
- Work that ends between samples, and the final partial interval of any observed process, can reappear only in a surviving ancestor's reaped-children counters. Adding those counters to observed lifetimes double-counts every portion already sampled. Subtracting a departed direct child's last observed CPU removes that overlap only for a child its parent waits for directly; the review evidence shows it fails for nested collection and automatic reaping, and scan ordering, temporary read failures, baseline exclusions and reparenting are further unmodeled cases.
- Reaped CPU belongs to the reaping ancestor's lifetime, not to the original process. When that ancestor is a shared runtime, the counters cannot divide the work between logical sessions.
- Orphans reaped by `launchd`, descendants whose reaping ancestor also exits before the next sample and other users' processes remain outside readable current-user counters. Unreaped zombies are absent from the reader's listing, although their own final counters remain readable until reaped.
- Host ticks multiplied by logical CPU count express unweighted logical-CPU occupancy in the same one-core unit, including on performance/efficiency hardware; they do not measure equivalent computing capacity. Subtracting current-user sums from it does not isolate outside-population load: missed current-user work, scan skew, tick resolution and any delayed recovery enter the difference, and recovered old CPU can exceed an interval's host load.
- Within one report, surviving lifetimes share approximately the same interval, so CPU ordering is comparable. Mean rates over unequal lifetime coverage, as in a multi-interval window, are not.

## Unresolved empirical questions

- How much agent CPU, especially builds and tests, current sampling misses at 1, 5 and 15 second cadences.
- Whether `mach_absolute_time`, `ri_proc_start_abstime` and host tick counters stay consistent across sleep/wake.
- Whether the automatic-reaping doubling occurs on other OS builds, Intel systems and sandboxed agents, and how many real parents reap automatically.
- Whether `host_processor_info` is cached at cadences or loads not tested here.
- Whether final counters of previously identified zombies could recover exited work without lossless tree accounting.
- How host tick totals compare with Activity Monitor's CPU load presentation, and their resolution at short intervals.
- How often a reaping ancestor is a shared runtime in real Codex or Claude workloads.

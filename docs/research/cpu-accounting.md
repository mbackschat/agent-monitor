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

## Live build observation — 2026-10-23

The user explicitly authorized read-only investigation while the reported CPU discrepancy was occurring. At 18:58:22 and 18:58:24 Europe/Berlin, `top` reported 0% idle; `sysctl hw.logicalcpu` returned 8. Thus host occupancy was approximately 800% in the monitor's one-core unit at those instants. A separate native process listing traced `lean`/`clang` workers through `lake` → `timeout` → `zsh` → a native Claude runtime. Half-second process listings showed workers repeatedly replaced within roughly one or two seconds. This establishes an agent-launched build with substantial worker churn, not an exact session ID or a partition of all host CPU. No provider listing, transcript, message, signal or workload modification was used.

A later capture began at 17:02:16.706971 UTC (19:02:16 local time), while the same `lake` parent remained present. The [raw counters and replay results](cpu-churn-2026-10-23.json) retain 168 scans, 46 distinct direct-child PID/birth identities, native Mach timebase, parent/self/child counters and footprints. The probe stopped after 17.395 seconds when the parent usage read was unavailable or its birth identity no longer matched; that condition does not establish normal exit. It consumed 0.273 CPU-seconds, approximately 1.57% of one core. That is the cost of a targeted Python/ctypes counter probe, not the production collector or UI. The earlier saturated-host observations and this later capture are different windows; no 800% ground truth is asserted for the replay window.

The probe used `proc_listchildpids`, verified to return a PID count rather than a byte count, and `proc_pid_rusage(RUSAGE_INFO_V2)` for the parent and its current direct children. It converted user/system/birth ticks with `mach_timebase_info` and recorded each read against `mach_absolute_time`. Requested spacing was 100 ms; actual timing includes scheduling and scan work. An initial exploratory capture divided the list count by the PID size and omitted workers; it was rejected and is not part of the retained dataset. Only the corrected capture is used below.

Replay takes every Nth scan from the first 151 captured scans, preserving identical endpoints and a 15.534-second duration for every row. For each PID/birth identity, it adds consecutive CPU deltas, or cumulative CPU for a newborn whose birth follows the preceding listing; first-scan CPU is excluded. The filtered column accepts an interval only when its per-process CPU exceeds 25% or its footprint exceeds 1 GB. Percentages are accepted CPU-seconds divided by the common window duration, not a claim that workers were simultaneously running at their peak rates. The parent itself is excluded from these worker totals.

| Nominal spacing | Scans | Distinct workers observed | Measured worker CPU | After default filters | Peak observed worker footprint |
| --- | --- | --- | --- | --- | --- |
| 0.1 s | 151 | 45 | 229.7% | 226.9% | 0.586 GB |
| 0.2 s | 76 | 44 | 221.1% | 218.0% | 0.573 GB |
| 0.5 s | 31 | 41 | 201.5% | 196.9% | 0.566 GB |
| 1 s | 16 | 30 | 175.6% | 161.0% | 0.566 GB |
| 5 s | 4 | 13 | 113.4% | 102.8% | 0.539 GB |

In this replay, five-second sampling plus default filtering retained 44.7% of the CPU measured at 100 ms without filtering. This quantifies a loss relative to another partial observation, not 55.3% of all actual build CPU. Faster sampling still misses unseen work and the CPU after each final observation. The footprint column is the maximum simultaneous sum at an observed scan, not a sum of per-worker peaks or a proven allocation peak. The capture excludes nested descendants and other processes; it reads resource counters directly, including any readable zombies, while production additionally verifies BSD metadata and same-user lifetime identity. No agent metadata enrichment or production UI ran in the probe. Therefore these results establish interval/filter sensitivity for this workload, not an end-to-end benchmark or a proof of complete accounting.

The parent reaped-children counters remain raw diagnostic data. They are not added to worker CPU and are not an independent oracle: pre-window work can be reaped in-window, and the [automatic-reaping and overlap evidence](#review-follow-up--2026-10-16) still applies. No exit-counter recovery mechanism was validated by this capture.

## Controlled exit and scheduler probes — 2026-10-23

Follow-up environment: Mac mini M1, eight logical CPUs, macOS 27.0.1 (26A434), Xcode/Instruments 27.1 (27A9275), Apple Swift 6.4. Native conservation/cost probes compiled optimized core revision `8c86886`; provider listings and UI were disabled. All CPU oracles used disposable owned workers and their parent's `wait4` results. The [retained dataset](cpu-exit-probes-2026-10-23.json) and [probe sources and commands](../../Tools/CPUAccountingProbe/README.md) distinguish measured results from production guarantees. Raw system-wide traces and exports remain ignored; only the owned workers' results are retained.

### What top measures

Apple's published [CPU formatter](https://github.com/apple-oss-distributions/top/blob/main/cpu.c) derives process percentages from differences in cumulative task CPU and elapsed time, and initializes a process without a preceding sample to zero. Its [collector](https://github.com/apple-oss-distributions/top/blob/main/libtop.c) reads host-wide ticks separately, samples task/thread counters and removes departed process records. Thus `top` can show a fully busy host while its visible process rows do not account for every short-lived worker. Its source does not establish lossless per-agent accounting. This is a source inspection of Apple's published implementation, not a claim that every detail matches the installed binary.

### Exit notification and retained task ports

An independent observer registered `kqueue` `NOTE_EXIT` before each of 40 workers started. Each worker requested 10 ms of CPU; its supervisor immediately reaped it with `wait4`. All 40 notifications arrived, but only **one final rusage read succeeded**; the others returned `ESRCH`. The oracle summed 0.424603 CPU-seconds. Notification delivery therefore does not ensure the process's final counters remain readable. This experiment deliberately avoids the monitor being the parent that controls reaping.

A separate owned-worker test acquired a task-name port and successfully read `TASK_ABSOLUTETIME_INFO` before execution. After the worker exited and was reaped, the retained port returned `KERN_INVALID_ARGUMENT` (4). Keeping a readable port was not sufficient to recover exit CPU in this test. Neither observation proves that every exit will be missed; they disprove treating notification or port retention as a reliable final-counter mechanism.

### Native polling against an independent oracle

The mixed fixture ran four workers at each requested CPU duration: 10 ms, 50 ms, 200 ms and one second. Each touched eight MiB, and each parent `wait4` result included the worker's actual user plus system CPU. Counter comparisons retained every accepted `Monitor.cpuContribution` across the observation window, including workers absent from its last scan. This measures recoverable CPU from the sequence, not just the final live table. Runs used fresh workers, so their absolute CPU totals and scheduling differ slightly; the percentages below use each run's own oracle.

| Collector | Accepted CPU / oracle | 10 ms workers | 50 ms workers | 200 ms workers | One-second workers |
| --- | --- | --- | --- | --- | --- |
| Production, one-second requested waits | 87.73% | 0% | 0% | 86.57% | 93.64% |
| Production, 100 ms requested waits | 92.95% | 0% | 41.05% | 92.87% | 96.77% |
| Prototype, 10 ms requested waits, first-observation metadata only | 97.62% | 0% | 90.83% | 97.02% | 99.50% |

The 10 ms prototype took 8.389 seconds for 401 scans: a requested wait is not an achieved scan period. It skipped repeated metadata refresh, provider resolution and rendering and therefore is not an attribution-correct production replacement. Every polling configuration missed the shortest group completely. The aggregate is dominated by longer workers; judging coverage only by that aggregate would conceal the failure. These are single controlled runs, not statistical benchmarks or estimates for arbitrary workloads.

An independent cost run of the production collector observed about 670 same-user processes. Thirty reports at 100 ms requested waits took 4.550 seconds and 1.334 CPU-seconds, **29.33% of one core**; mean raw scan time was 5.04 ms. At one-second waits the run took 32.813 seconds and 1.531 CPU-seconds, **4.67% of one core**; mean raw scan time was 7.25 ms. The difference between raw scan time and total collection work supports separating counter observation from repeated metadata/enrichment. This is not a measurement of app rendering, provider lookup time, wakeups or battery cost. No acceptable-overhead ceiling was inferred from it.

### Scheduler evidence

Apple's [System Trace presentation](https://developer.apple.com/videos/play/wwdc2016/411/) describes thread scheduling states; these allow CPU occupancy to be integrated over execution intervals rather than inferred only from surviving process snapshots. A ten-second system-wide `xctrace` recording captured all **16 of 16** 50 ms workers. Summing their exported `thread-state` intervals whose state was `Running` gave **0.847669895 seconds**, versus **0.849265 seconds** from `wait4`: **99.812%**. Per-worker ratios ranged from 98.992% to 100.506%. This is a successful local scheduler/CPU-accounting comparison, not proof of a lossless tracing service or complete session attribution.

A second ten-second system-wide trace used the mixed-duration fixture and **failed CPU conservation**: the same interpreter summed **12.536585701 seconds** against **5.095827 seconds** from `wait4`, or **246.02%**. It observed all four 10 ms workers (105.43% of their oracle CPU), while the 50 ms and 200 ms groups measured 99.71% and 99.11%. The one-second group was badly overcounted at 285.49%. Each of those four workers had an exported `Running` span of approximately 2.448 seconds beginning at trace time 6.5396 seconds, and none had a record in the exported `ThreadTermination` table; the other twelve workers did. Their independent parent ledger confirms normal exit. The export therefore does not provide trustworthy complete scheduling/lifetime boundaries in this run. Missing trace events or exporter reconstruction are hypotheses; no dropped-event marker was established by these exports. Do not repair this by truncating arbitrarily long spans or choosing whichever trial looks plausible.

This second trial prevents treating the first 99.812% result as a validated backend. A production trace path needs explicit completeness and event-boundary checks before integrating CPU, plus lifecycle/session joins. The raw-span parser is retained as the reproducible failed experiment, not included in the product. A successful recording/export exit status is not an accounting oracle.

The stock System Trace template is unsuitable as an always-on default on this evidence: approximately 3.3 GB of temporary trace data was observed during finalization, the saved trace occupied about 1.1 GB, the thread-state XML was 613 MB, and finalization/export took minutes. A target-only trace listed the parent but not its worker children. The successful comparison used system-wide capture and retained only controlled worker summaries. An initial target-launch recording whose parent exited early stalled during finalization; keeping the target alive through the stop boundary worked. These practical limitations matter independently of CPU coverage.

The worker PID ledger is an oracle for this controlled experiment only. A production trace consumer would also need exact lifetime identity, fork/exec ancestry, agent/session evidence collected while it exists, missing-event detection and boundaries for attaching to an already-running system. Scheduler occupancy does not supply those guarantees automatically. Memory also needs a separate contract: current physical footprint and simultaneous observed peaks cannot be replaced by summed allocations, RSS or a sum of each process's independent peak.

### Other macOS mechanisms

| Mechanism | Evidence and limitation |
| --- | --- |
| `proc_pid_rusage` / Mach task CPU | Already native kernel counters; polling alone cannot recover lifetimes never observed or the final post-observation CPU of a reaped worker. |
| `kqueue` process events | Exit-counter race reproduced above. Xcode 27.1 `sys/event.h` states that `NOTE_TRACK`, `NOTE_TRACKERR` and `NOTE_CHILD` have been unsupported since macOS 10.5; `NOTE_FORK` is not recursive discovery with child identities. |
| Endpoint Security | Xcode 27.1 `EndpointSecurity/ESMessage.h` defines exit events with status and reserved space, not final CPU. `ESClient.h` documents macOS 27's [descendants client](https://developer.apple.com/documentation/endpointsecurity/es_new_descendants_client(_:_:)): no root/TCC requirement, but it still requires the Endpoint Security entitlement and observes only the caller's own subtree. That does not let a standalone monitor attach to arbitrary existing agents. No ES client was installed or enabled. |
| Direct kernel tracing | Published [XNU ktrace ownership code](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_ktrace.c) manages system-wide ownership and privileges, including the private `com.apple.private.ktrace-allow` entitlement. A private low-level wrapper is not equivalent to an unrestricted shipping API, nor an isolated per-agent counter. No kernel configuration or security setting was changed manually. |
| Hardware Processor Trace | Apple's [supported-hardware documentation](https://developer.apple.com/documentation/xcode/analyzing-cpu-usage-with-processor-trace) requires M4 or newer Macs for capture. It is not available on the M1 test machine and is distinct from the successful scheduler trace. Instruction-level profiling is also a different requirement from attributing total agent load. |
| BSD process accounting (`acct`) | The installed Xcode 27.1 `sys/acct.h` and Apple’s [published record](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/acct.h) contain user/system CPU, a ten-byte command name, second-resolution birth time and UID/TTY, but no PID or parent PID. CPU uses compressed 1/64-second units. The [kernel implementation](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_acct.c) requires root to configure the system-wide accounting file. This cannot establish exact lifetime/session attribution or precise 10 ms worker CPU; enabling it would not solve the required contract. It was inspected, not enabled. |
| Reaped-child counters | The earlier [overlap and automatic-reaping evidence](#review-follow-up--2026-10-16) still prevents naive addition; these trials did not establish a safe replacement conservation model. |

The evidence supports frequent, independently scheduled native observations for everyday visibility and further validation of bounded scheduler tracing for CPU that polling cannot capture. The tested exporter alone is not a reliable accounting backend. A small process total must continue to be labeled as observed work; the unexplained difference from host CPU must not be called system load or assigned to an agent without evidence.

### Kernel memory high-water mark

The Xcode 27.1 `sys/resource.h` definition of `rusage_info_v4` includes both current `ri_phys_footprint` and `ri_lifetime_max_phys_footprint`. An owned child allocated, touched and then unmapped 64 MiB while its parent read those counters at gated boundaries. Current footprint changed from **721,112** to **68,190,544** to **1,048,864 bytes**; the kernel peak remained **68,190,544 bytes** after unmapping. The [retained native probe](../../Tools/CPUAccountingProbe/footprint-peak.c) demonstrates that a surviving process's kernel peak can reveal a memory burst after current usage has fallen, without relying on observing the burst at its highest point.

A second gated run replaced the child with `/bin/sleep` after freeing memory. Its native birth counter stayed identical, but the peak fell from **68,190,544** to **1,081,584 bytes** (current **1,048,816 bytes**). Thus this is a kernel task high-water mark that can reset on exec, not a peak over the entire PID/start lifetime. Apple’s published [resource collection implementation](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_resource.c) reads `get_task_phys_footprint_lifetime_max(proc_task(p))`, consistent with that result; the experiment establishes behavior on the installed OS. The counter gives neither the time of the peak, a report-window peak nor a simultaneous session-wide peak. Peaks from separate workers must not be summed as concurrent memory use. Reaped workers remain subject to the same lifetime/readability constraints. This trial establishes a useful memory observation mechanism on this OS, independently of the unsettled CPU trace path.

The production reader now requests `RUSAGE_INFO_V4` and carries optional `kernelPeakFootprintBytes` through report JSONL v4 and text/TUI/native process inspection. Current memory, sorting, thresholds, session totals and history continue to use current physical footprint. Later observations replace the peak, including a lower value after exec or an unavailable value; the monitor does not manufacture a PID-lifetime maximum.

## Independent acquisition and adaptation — 2026-10-23

Follow-up provenance: the user proposed a lightweight fast collector with deferred or on-demand enrichment, followed by adaptive sampling. Source inspection used repository revision `be12b99`, specifically [MonitoringSession](../../Sources/AgentMonitorCore/MonitoringSession.swift) and [NativeProcessReader](../../Sources/AgentMonitorCore/NativeProcessReader.swift). No new runtime experiment was performed for this analysis. Existing measurements above remain single-run evidence; no adaptive implementation, safe interval or scheduling guarantee has been validated. The proposed contract belongs in [resource accounting](../proposals/resource-accounting.md#acquisition-and-resolution).

### Observations and inferences

`MonitoringSession.run` serially waits, reads a native snapshot, enriches every observed sample, performs due provider listings and awaits the report consumer before beginning another cycle. Thus metadata, provider and consumer latency extend the interval between native observations. `NativeProcessReader.snapshot` already captures BSD lifetime/parent data, executable path, native counters and a second identity check. Its metadata path additionally reads arguments/markers and cwd, conditionally resolves terminal names and adapter-requested descriptor/socket observations, and checks current lifetime/executable before and after those reads. Splitting the paths must preserve these checks and adapter ownership; removing them would change attribution correctness, not merely performance.

The [polling comparison](#native-polling-against-an-independent-oracle) retained 97.62% of CPU with 10 ms requested waits and first-observation metadata, compared with 92.95% under production collection with 100 ms waits. Both missed every 10 ms worker. This changes cadence and metadata policy together, so it cannot isolate the benefit of deferred enrichment or predict a production asynchronous collector's cost. The 5.04 ms mean raw scan and 29.33% one-core collection cost support investigating repeated enrichment separately, but averages do not establish scan tail latency or attainable deadlines.

Inference: deferred interpretation is useful when its inputs are already captured. Deferred observation is different: markers, executable context and parent relationships may disappear before a worker reads them. The [exit notification trial](#exit-notification-and-retained-task-ports) demonstrates the final-counter race, not a measured success rate for metadata capture. New-process priority may improve evidence coverage, but cannot guarantee it. Long-lived runtime evidence can also change without a PID or executable change; retaining only first-observation metadata is not a validated attribution policy.

Inference: an adaptive policy driven only by measured agent CPU can reinforce its own blind spot. Missing a burst yields low measured load, which could trigger slower sampling and further loss. Host activity and discovery of lifetime changes provide additional signals, but neither establishes attribution or catches every burst. A host/process discrepancy compares different populations and potentially different windows; it is not a quantity of missing agent CPU. Monitor-generated CPU may itself keep a host-triggered policy in its fastest mode. No result above measures these feedback effects.

Inference: different sampling rates per process make report-window accounting and memory freshness harder. Cumulative CPU observed across multiple report windows does not reveal when within those windows it was spent; differently aged footprint samples do not form an exact simultaneous memory snapshot. Global adaptation avoids this additional policy complexity, while still requiring actual per-process observation times and scan-skew qualifications.

### Unresolved empirical questions

| Question | Evidence needed to judge it |
| --- | --- |
| Does independent acquisition improve coverage without losing agent evidence? | Repeated controlled runs with separate observations of retained CPU, exact-session resolution, unresolved lifetimes, scan timing and monitor cost; slow/failing fake provider resolution and consumers. The existing prototype is not this comparison. |
| Can adaptation match fixed fast collection during sudden activity? | Independent `wait4` ledgers by worker duration, quiet-to-busy transitions and bursts at varied phases relative to scans, including lifetimes shorter than the slowest cycle. Compare misses and acceleration delay, not just aggregate CPU. Neither fixed fast polling nor replayed captured samples is a complete workload oracle. |
| What prevents false quiet or permanent acceleration? | Controlled stale/failed host readings, unrelated host activity, monitor overhead, memory growth without substantial CPU, sparse churn and periodic bursts; inspect rate transitions and achieved timing. |
| Does deferred evidence remain attached to the right work? | Fake exact-session fixtures spanning exit-before-capture, PID reuse, same-path exec, reparenting and runtime/session changes while resolution is pending; distinguish unavailable evidence from a wrong confident owner. |
| What happens under capacity pressure? | Bounded-buffer saturation and slow-resolution fixtures measuring preserved CPU contributions, lost evidence, reported gaps and collector memory; no silent latest-snapshot replacement. |
| Is per-process adaptation worth its semantic cost? | A comparison against global adaptation that preserves counter interval boundaries and exposes memory observation age. No such measurement exists here. |

The evidence supports investigating independent acquisition before choosing adaptive thresholds. It does not establish that adaptive polling outperforms fixed fast polling, that any particular quiet interval is safe, or that scheduler tracing has passed the separate conservation gates.

## Diagnostic recording size estimates — 2026-10-23

The user requested recordings after independent acquisition/background attribution exists, then specified opt-in runtime start/pause/resume, lossless compression, chunks of 50 MB uncompressed data and up to 250 MB compressed data in total, with documented editable limits. The [recording proposal](../proposals/diagnostic-recording.md) owns the design. This section contains arithmetic estimates, not a compression benchmark; MB means 1,000,000 bytes and 10:1 means uncompressed bytes divided by compressed bytes.

Source inspection at `009ec7d` of [JSONReport](../../Sources/AgentMonitorPresentation/JSONReport.swift) shows full process records in both displayed `findings` and unfiltered `observedFindings`. Existing synthetic JSONL fixtures measured 1,084 and 1,032 bytes per report, each with one displayed and one observed entry; the compact observed entry alone measured 340 bytes. These fixtures establish repeated report/context overhead, not realistic recording size or compression ratio. A recording format with contextual references and numeric observations has not been implemented or measured.

Assuming **64–128 serialized bytes per process observation**, raw bytes per hour equal process count × achieved observations per second × bytes per observation × 3,600. The range is a planning assumption, excluding extra context checkpoints, lifecycle/resolution events and container overhead. The following conditional estimates assume all records achieve **10:1** compression:

| Recorded processes | Achieved observation rate | Raw MB/hour | Compressed MB/hour at 10:1 | Hours retained in 250 MB at 10:1 |
| --- | --- | --- | --- | --- |
| 100 | 1 Hz | 23–46 | 2.3–4.6 | 54–109 |
| 100 | 10 Hz | 230–461 | 23–46 | 5.4–10.9 |
| 500 | 10 Hz | 1,152–2,304 | 115–230 | 1.1–2.2 |
| 100 | 100 Hz | 2,304–4,608 | 230–461 | 0.54–1.09 |

A full 50 MB chunk becomes approximately 5 MB at 10:1, giving about 50 retained chunks or 2,500 MB of uncompressed history before overhead. At 100 processes and 10 Hz, one full chunk represents roughly 6.5–13 minutes. At 5:1 the same compressed budget retains half as much history as the table; near 1:1 it retains roughly one tenth. Adaptive cadence, process count and churn change the retained duration. Pauses yield partial chunks and explicit time gaps; they do not lower the achieved sampling rate of observations actually recorded.

Inference: repeated JSON strings may compress well, but a compact representation has already removed much of that repetition. A ratio observed on redundant presentation snapshots would not justify promising the same ratio for numeric counter deltas, changing identities or context checkpoints. No evidence here establishes 10:1 or better. Relevant empirical questions are ratio on representative changing data, compression/decompression cost, worst-case output expansion, bounded pending writes and interpretability after oldest-chunk eviction or pause/resume. Round-trip identity verifies compression is lossless; it does not establish collection completeness or undo intentional retention loss.

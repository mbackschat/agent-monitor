# GPU accounting feasibility

## Unprivileged access works; reliable attribution remains unproved — 2026-10-29

The bounded probe on Apple M1/macOS 27.0.1 read host activity and process-associated GPU counters without privileges. This establishes a usable observation route on this machine, but not a stable supported telemetry contract, complete process accounting or reliable agent/session totals. Driver record continuity and metric meaning remain material gaps. The [open proposal](../proposals/gpu-resource-visibility.md) separates those questions from implementation authorization; the [privileged-tracing rejection](../decisions/privileged-resource-tracing.md) remains in force.

### Public registry access does not standardize GPU telemetry

Apple documents [registry-property reads](https://developer.apple.com/documentation/iokit/1514293-ioregistryentrycreatecfproperty/) and [registry entry IDs](https://developer.apple.com/documentation/iokit/1514719-ioregistryentrygetregistryentryi); the latter identify entries until reboot. The installed Xcode 27 SDK declares these public APIs and `kIOUserClientCreatorKey`. A bounded search of IOKit and Metal headers found no declarations for `AGXDeviceUserClient`, `AppUsage`, `accumulatedGPUTime` or `PerformanceStatistics`. That absence does not prove Apple never documents them, but no stable Apple telemetry schema was established in this investigation.

[Stats at `21f866b`](https://github.com/exelban/stats/blob/21f866bb3e8ba606c9c01769f558accbcf1fa27c/Modules/GPU/reader.swift#L102-L145) reads device utilization from driver properties and [process counters](https://github.com/exelban/stats/blob/21f866bb3e8ba606c9c01769f558accbcf1fa27c/Modules/GPU/reader.swift#L380-L543) from accelerator clients. This supports a direct native IOKit candidate. By contrast, [gptop's IOReport bindings at `9265a8c`](https://github.com/evilsocket/gptop/blob/9265a8c260c9c80252da8742bab4043ac0833b63/src/backend/apple/ioreport.rs#L15-L56) declare private functions. Public registry traversal and private IOReport binding are different dependencies; neither makes driver field semantics a supported contract.

### The local probe admitted only a small counter subset

The [sanitized measurement](gpu-feasibility-2026-10-29.json) retains one run ending at 03:51:47 UTC: 12 snapshots over 11.153 seconds on Apple M1/macOS 27.0.1 (`26A434`), compiled with SDK 27.0/Swift 6.4. One-second sleeps separated reads; no workload was generated. Real and effective UIDs were nonzero. Every snapshot found one accelerator and 87 GPU-client registry entries containing 86 creator PIDs. Device utilization reported 3–19 in its driver-labelled percent property; the property’s reporting window and calibration were not independently verified.

Eighty-one client entries had equal same-user process-birth observations before and after reading their counters. Six entries failed at least one lifetime read; errno was not retained, so the causes remain unknown. These checks associate a currently observed process birth with a creator PID; they do not prove that a stale registry entry was originally created by that lifetime. No agent/session attribution was attempted.

Every snapshot contained 47 `AppUsage` records. Eleven client entries held 32 records with repeated `Metal` labels. The only exposed fields were `API`, `accumulatedGPUTime` and `lastSubmittedTime`; no stable accounting-record identifier was present. The probe excluded repeated API records rather than assume array positions or per-client sums preserve continuity. This is a conservative probe choice, not proof that summing is invalid or supported. Fourteen single-record/API counters passed the probe's birth checks; one rose once by 761,791 raw units. Registry membership, matched lifetimes and counter values showed no decreases or replacement during the run. Absence of churn in this short window does not validate churn handling, and even a single-record slot lacks proven continuity.

Reader wall time was 2.564–13.836 ms, median 4.712 ms; CPU time was 2.553–5.793 ms, median 3.750 ms. These include traversal, property conversion and process-birth reads, but exclude compilation/startup, sleep and final JSON output. They establish neither a sustained production budget nor a suitable cadence. The matched subset's tiny counter delta alongside changing host activity cannot quantify missing GPU work: the two sources have unverified alignment and different coverage.

### Driver time is not a GPU-capacity share

An independent [ActivityMonitor validation at `a897096`](https://github.com/wieslawsoltes/ActivityMonitor/blob/a897096acecc95b5e9cb81d32ab93ea77daa9885/docs/GPU_VALIDATION.md) on M3 Pro/macOS 26.6 found a raw counter of 1,233,367,625 matching Apple's displayed 1.23 seconds. Its controlled workload reported 1.226 seconds of driver time but 5.615 seconds of Metal command-buffer elapsed time. This supports nanosecond interpretation on that system, not local calibration or equivalence between metrics. Apple’s [command-buffer timing API](https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpustarttime) describes elapsed execution timing for submitted work, not arbitrary-process capacity monitoring.

The same project's [collector](https://github.com/wieslawsoltes/ActivityMonitor/blob/a897096acecc95b5e9cb81d32ab93ea77daa9885/Sources/ActivityMonitor/GPUCollector.swift) checks client/process identity and baselines changed counters. Such guards do not by themselves prove that equal-length record arrays contain the same accounting objects: replacement with a larger value could evade a monotonicity check. Neither local observations nor inspected sources established stable per-record identity, complete short-client coverage or final-exit accounting.

Two tempting shortcuts are unsuitable evidence for Agent Monitor. [metalps at `97f2d9f`](https://github.com/LoganBarnett/metalps/blob/97f2d9fb70ac52b5f5334de654ae5323baff1894/crates/lib/src/macos/mod.rs#L80-L117) subtracts PID-summed active-client snapshots, which cannot by itself preserve disappeared-client work or distinguish PID reuse. [gptop](https://github.com/evilsocket/gptop/blob/9265a8c260c9c80252da8742bab4043ac0833b63/src/backend/apple/mod.rs#L286-L303) apportions host GPU activity by process memory footprints; that is an estimate, not measured process execution. Device activity therefore cannot be divided among sessions using those weights or reconciled with process rates by inventing a remainder.

### Public task fields and shared memory have separate limits

[Apple XNU at `f6217f8`](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/task.c#L6785-L6906) and its [arm64 implementation](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/arm64/machine_routines.c#L2762-L2776) explain why public task GPU fields can remain zero without useful process instrumentation. This 2025-10-16 source is not proof of the installed macOS 27 kernel. A present field returning zero must not become a fallback claim that GPU work is idle. Apple's [debugger-entitlement documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.debugger) establishes limits on `task_for_pid`, but those must not be transferred to the `TASK_POWER_INFO_V2` task-name-port path examined in the [source follow-up](#task-fields-are-a-diagnostic-candidate-not-a-promised-replacement).

Metal documents [shared CPU/GPU memory](https://developer.apple.com/documentation/metal/mtldevice/hasunifiedmemory), a [recommended working-set budget](https://developer.apple.com/documentation/metal/mtldevice/recommendedmaxworkingsetsize) and [resources allocated through a device](https://developer.apple.com/documentation/metal/mtldevice/currentallocatedsize); these do not provide an arbitrary-PID GPU-memory census or dedicated VRAM capacity on Apple Silicon. The SDK's graphics ledgers have [charged/excluded and compressed/uncompressed balances](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/task.c#L6185-L6196). An upstream [memory investigation](https://github.com/wieslawsoltes/ActivityMonitor/blob/a897096acecc95b5e9cb81d32ab93ea77daa9885/docs/diagnostics/GPU_MEMORY.md) obtained balances through `task_name_for_pid`, with target-dependent failures and values differing from Metal allocations. This route was not tested locally. Whole-process footprint is not GPU memory, and adding a graphics balance to it risks double counting.

### Reproducibility and evidence limits

The [dated probe source](gpu-feasibility-2026-10-29.swift) is retained byte-for-byte as historical evidence, SHA-256 `e70df006799e389fb4777154b08ec74a7af2d97406de0278dd30cffb93f047e5`. It is not a supported collector or production decoder: numeric decoding lacks full finite/integer/range validation, accumulation lacks overflow handling, identity association has the limits above, and its 28-second between-read check cannot preempt a blocked native call. The successful run completed in 11.153 seconds. The JSON summary retains original-output and source hashes, per-read costs, aggregate counts and selected host values; no PID, process name/path, birth timestamp, registry ID or per-process counter is retained.

The original command used the same source under `.build/gpu-feasibility/probe.swift`. This equivalent command locates the retained source and uses the existing temporary-artifact wrapper; rerunning it is a new live observation, not needed to verify these documents:

```sh
python3 scripts/clean-build.py run -- bash -c 'xcrun swiftc -O -module-cache-path "$PWD/.build/module-cache" docs/research/gpu-feasibility-2026-10-29.swift -o "$AGENT_MONITOR_SCRATCH/gpu-probe" && "$AGENT_MONITOR_SCRATCH/gpu-probe"'
```

No provider/helper queries, task ports, private-framework bindings, root access, security changes, synthetic GPU work, messages or signals were used. No comparison against an independent work oracle, Activity Monitor, another GPU/macOS version, application launch/sandbox variant, reset/exit workload or sustained-cost run was performed. The result demonstrates access and useful feasibility questions; it does not establish deployable agent GPU accounting.

## Creator identity and aggregate continuity follow-up — 2026-10-29

Further source inspection and seven deterministic offline cases narrow the unresolved mechanism: **stable record IDs are not necessary if the client exposes a continuous, additive cumulative total**, but the available fields alone do not establish that contract. The creator string also has a concrete generic IOKit limitation. This follow-up generated no GPU work and made no new native observations; the hypothetical counter histories below are not claims about observed AGX behavior.

### The creator string is not an immutable ownership token

Apple labels `kIOUserClientCreatorKey` a diagnostic string in [XNU `f6217f8`, `IOKitKeys.h`](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/IOKit/IOKitKeys.h). [`IOCopyLogNameForPID`](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/Kernel/IOLib.cpp) formats the PID and process name, without birth identity or an audit token. In [`is_io_service_open_extended`](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/Kernel/IOUserClient.cpp), the creator property is written after `newUserClient` returns and before the `!client->opened` check. Thus another open returning a shared instance can replace the string. The same file tracks multiple task owners and calls `clientDied` when the last owner exits; the default implementation delegates to `clientClose`, leaving driver-specific detachment timing unresolved.

This establishes a generic source mechanism, **not observed AGX sharing or stale ownership on macOS 27**. Two matching process-birth reads cannot make that string immutable or establish exclusive ownership of a shared client's work. Advertised shared instances and changed creator strings therefore need separate attribution treatment. The earlier probe did not inspect the shared-instance property or client close timing. No public creator-lifetime getter was established by this bounded review.

Registry IDs remain useful outer identity: [Apple's API](https://developer.apple.com/documentation/iokit/1514719-ioregistryentrygetregistryentryi?language=objc) specifies cross-task identity until reboot, and this [XNU implementation](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/Kernel/IORegistryEntry.cpp) assigns IDs on initial attachment. Their stability does not establish inner record continuity or accounting ownership. The generic owner-cleanup path supports a lifecycle investigation, but does not establish when AGX entries disappear relative to process exit and PID reuse.

### Offline cases separate arithmetic bugs from missing semantics

The temporary stdlib Python study executed seven cases successfully. It modeled the locally observed record fields (`API`, `accumulatedGPUTime`, `lastSubmittedTime`) plus client ID, PID and process birth, with invented counters and hidden source identities. Each ambiguity used equal visible endpoints but different compatible hidden histories; submission timestamps were also equal between the alternative histories. The self-contained examples below preserve the result without adding permanent synthetic production tests or a probe utility. Values are arbitrary accounting units, not nanoseconds or measured loss rates.

| Case | Visible counters | Constructed result and implication |
| --- | --- | --- |
| Record permutation | `[10, 20] → [30, 40]` | Stable source matching gives deltas `[20, 20]` or `[30, 10]`; both totals are **40**. Record identity is ambiguous, but an additive client total is not. |
| Positional subtraction with clamping | `[10, 100] → [110, 20]` | Persisting records change order and each gains 10. The total is **20**; clamping negative positional differences incorrectly reports **100**. |
| Same-length replacement | `[10, 20] → [30, 40]` | Persistent records contribute **40**; retaining the first and replacing the second with a new record born at zero contributes **60**. No old-record final increment is needed. |
| Single-record replacement | `10 → 30` | Persistence contributes **20**; replacement born at zero contributes **30**, even when the outer client identity is unchanged. |
| Disappeared client | `10 → absent` | The unseen final increment can be **0** or **50** with identical observations. Retained history cannot supply that missing tail. |
| PID reuse after discarding exact identity | PID total `10 → 30` | Persistence contributes **20**; a new process/client contributes **30**. Full modeled birth/client IDs distinguish these histories: the ambiguity is created by the weak PID-only projection. |
| Duplicate versus disjoint charges | `[10, 10] → [30, 30]` | Two views of one source contribute **20**; two distinct sources contribute **40**. The field values do not define additivity. |

For a fixed set of distinct cumulative sources, `sum(after) - sum(before)` is invariant under permutation. More generally, a driver-maintained continuous client aggregate could remain valid through internal record reorganization. The needed semantics are disjoint charging, comparable snapshots, retained retired work, no unrelated history inserted between baselines, and detectable reset/rebaseline conditions. Stable per-record identifiers are one possible solution, not a prerequisite when that aggregate contract is established. These examples do not show that AGX permits replacement or duplicate views; they show which assumptions arithmetic alone cannot settle.

An additional [consumer implementation, `gpui-fps` at `7a9ac17`](https://github.com/longbridge/gpui-kit/blob/7a9ac172e804ce89aebac644a02f09813dc9e793/crates/fps/src/gpu/macos.rs#L53-L125), subtracts PID-summed counters with saturation and explicitly handles decreases attributed to departing clients. A survivor gaining 20 while another client removes 100 would consequently report zero. This constructed example explains why per-client baselines are necessary to avoid cancellation; it does not settle continuity inside each client or recover its exit tail. Calling records “queues” in consumer code does not establish their driver-defined meaning.

### Source evidence still does not define the charging metric

Apple's [GPU timeline guide](https://developer.apple.com/documentation/xcode/analyzing-apple-gpu-performance-using-a-visual-timeline) distinguishes overlapping stages, occupancy, utilization and stalls; it does not define `accumulatedGPUTime`. The additional exact-key and lifecycle searches found consumers, not a producer-side definition of units, reporting delay or record retention. This is a bounded negative finding. The earlier M3 Pro comparison remains supporting unit evidence, not local calibration, and Metal command-buffer elapsed time remains a different measurement.

The resulting inference is narrower than rejecting the registry route: a version-scoped cumulative-client contract could support honest observed accounting if lifecycle and charging evidence justify it. A controlled successful trial would characterize that hardware/OS/schema, not guarantee all future drivers or unseen transitions. No new source or offline case closes local metric calibration, exact client ownership, exit coverage or sustained cost. The [proposal's feasibility section](../proposals/gpu-resource-visibility.md#feasibility-gates-and-recommendation) owns the next experiment and its authorization boundary.

## Bounded Metal calibration falsifies client-total retention — 2026-10-29

**The live `AppUsage` sum is not a continuously retained cumulative counter on this M1.** Under one unchanged client identity, releasing application references to queue B removed its record and accumulated value. That rejects treating the live sum as retained history, not a collector that preserves accepted interval contributions: replaying every acquired checkpoint with membership/count/decrease guards retains all **90,569,583 observed raw units**. Sparse observations can still miss entire queue lifetimes or final increments. This single fixture neither validates a production collector nor rejects bounded observed-work accounting.

### Authorized method and successful work oracle

The user explicitly authorized the previously proposed calibration on 2026-10-29. One disposable unprivileged Metal worker ran three serial batches: A, B while A was retained idle, and A after B's application references were released through a drained autorelease pool. One shared 16,384-byte data buffer held 4,096 input-dependent integers; every command applied 256 bounded arithmetic iterations per thread. CPU reference values were computed independently of Metal, including a Python-checked known vector, and every command's full output was compared with them. No pre-existing user process was signalled or instrumented, and no provider, task port, private framework, root access or system security-configuration change was used.

Each batch stopped at 128 completed submissions or 200 ms of valid accumulated command elapsed time, whichever came first. All three hit the submission cap: **384 commands total**, with successful completion, no command errors, verified outputs, no invalid GPU timestamps and no timestamp overlaps. Summed command durations equalled their interval unions; serial `waitUntilCompleted` makes this expected, so the check supplies no concurrent-work evidence. The worker and observations took **3.107 seconds**, including a **0.278-second setup**, delayed reads and a one-second no-submit cooldown. The external 20-second watchdog did not trigger. The explicit buffer bound does not bound compiler/framework/driver allocations, and a watchdog cannot cancel GPU work already submitted.

The CPU-only observer recorded 32 reads, with same-user process birth checked before and after each traversal and creator PID rechecked around each client's property read. It retained only the owned worker's client IDs and individual counters in bounded memory, emitting aggregate counts and values. Samples bracketed device/queue creation, first commands, each batch and reference release; immediate, nominal 50 ms and 200 ms samples have their actual read start/end times in the [sanitized result](gpu-calibration-2026-10-29.json). The supervisor deliberately held the worker, including B's lifetime, around checkpoints; this is not a 100 ms or uncoordinated queue-census validation. The initial restricted-environment attempt returned no Metal device and submitted no GPU work; the authorized retry outside that execution sandbox succeeded without elevated UID. This is not app-sandbox compatibility evidence.

Environment: Apple M1, macOS 27.0.1 build `26A434`, SDK 27.0, Swift 6.4 (`swiftlang-6.4.0.34.1`, `clang-2100.3.34.1`), arm64, optimized standalone Swift fixture. The successful run ended at **17:38:37 UTC**. This is a single bounded run, not a sustained workload or cost acceptance test.

### Queue release removes previously accumulated work

| Observation | Clients | Metal records | Aggregate raw counter |
| --- | ---: | ---: | ---: |
| Before creating a Metal device | 0 | 0 | 0 |
| Device created | 1 | 0 | 0 |
| Queue A created, before work | 1 | 1 | 0 |
| A first batch completed | 1 | 1 | 31,715,000 |
| Queue B created, before work | 1 | 2 | 31,715,000 |
| B batch completed | 1 | 2 | 63,096,500 |
| B application references released | 1 | 1 | 31,715,000 |
| A second batch completed | 1 | 1 | 59,188,083 |
| After no-submit cooldown | 1 | 1 | 59,188,083 |

The same client registry identity remained present after device creation; no client departure or replacement was observed. The inspected `AppUsage` dictionaries exposed `API`, `accumulatedGPUTime` and `lastSubmittedTime`, without a stable record ID. The decoder never read `lastSubmittedTime` values, and this was not an inventory of other client properties or registry classes. Record count followed queue creation/release in this fixture. B's release reduced the aggregate by exactly **31,381,500**, equal to the increase during B's isolated batch. The immediate, 50 ms and 200 ms readings agreed at each of these checkpoints, including release, and no deferred increase appeared during cooldown. “Immediate” means the first completed registry read after the worker checkpoint, not zero reporting latency. Reference release did not force or independently verify driver destruction.

A sparse replay from the end of A's first batch to the end of A's second sees one unchanged client, one record at both endpoints and a rise from 31,715,000 to 59,188,083: **27,473,083**. The dense trace separately observes **58,854,583** from B and A2 together. B's entire lifetime is absent from that sparse reader's observations; the missing 31,381,500 is an unseen accounting-object lifetime, not cancellation of a B counter previously acquired by that reader. This is analogous to a CPU worker born and exited between polls. Equal endpoint counts do not reveal that gap, but this replay does not demonstrate same-count record replacement; that remains a hypothetical risk from the earlier offline cases.

A different sparse replay, `first_b@0ms → after_a2@0ms`, isolates actual cancellation: subtracting 32,059,708 from 59,188,083 gives **27,128,375**, which is **344,708** less than A2's observed increment because B's already-seen first-command counter disappears. B's remaining **31,036,792** is separately an unseen final tail. The total omission against the dense B-remainder-plus-A2 trace is 31,381,500; it comprises cancellation plus final-tail loss. Record count changes **2 → 1**, so a count guard detects and rejects this interval rather than accepting its misleading positive delta.

Consecutive replay accepts increments only when client membership and per-client record counts agree and the aggregate does not decrease, while preserving previously accepted contributions separately. It retains **90,569,583**. Initial client appearance establishes the baseline; the three later rejected transitions are A creation (raw delta 0), B creation (0) and B reference release (-31,381,500). None contains fixture submissions; they are not three zero-delta intervals. This favorable trace does not test survivor growth concurrent with retirement. Guarded retained history is therefore a viable research direction, with real queue lifetimes, last-read/exit tails and material missed work still requiring assessment.

### Raw driver increments do not calibrate Metal elapsed time

| Batch | Verified commands | Raw driver increment | Metal command elapsed/union | Batch wall time including first-command observation |
| --- | ---: | ---: | ---: | ---: |
| A first | 128 | 31,715,000 | 2.834 ms | 38.907 ms |
| B | 128 | 31,381,500 | 2.825 ms | 41.903 ms |
| A second | 128 | 27,473,083 | 2.694 ms | 34.131 ms |

If the raw units were nanoseconds, these increments would represent 31.715, 31.382 and 27.473 ms. Comparing all 128 raw-command increments with all 128 Metal durations gives ratios **11.192, 11.110 and 10.199**. The earlier M3 Pro evidence differs in the opposite direction: driver time was below Metal elapsed time. Neither direction defines a unit or proves either measurement wrong; one workload cannot establish charging semantics, a conversion factor, occupancy or capacity share.

The first-command-to-batch-end raw differences cover the remaining **127** commands. Exact property-read instants were not retained, so the end of the first read to the start of the final read is only the lower bound of the interval; the reverse endpoints give its upper bound. The independent replay gives:

| Batch | Remaining raw increment | Property-read interval bounds | Conditional raw nanoseconds / wall interval |
| --- | ---: | ---: | ---: |
| A first | 31,438,625 | 36.184–38.520 ms | 0.816–0.869 |
| B | 31,036,792 | 39.778–43.439 ms | 0.714–0.780 |
| A second | 26,996,500 | 32.736–35.202 ms | 0.767–0.825 |

These ratios leave nanosecond-scale units plausible under assumed wall-bounded, aligned charging; those premises remain unvalidated. Applying a hypothetical **125/3 ns per unit** instead produces roughly 30–36 times wall time, but the fixture never measured `mach_timebase_info` or the driver's timebase. It cannot establish a tick conversion by exclusion. First-command Metal durations were not retained, so remaining-127 raw values must not be divided by all-128 Metal durations. Submission-cycle wall-time charging is also only a hypothesis. The observer's 32 registry traversals took 0.995–2.589 ms wall time each, median 1.425 ms, 49.139 ms total; reader CPU and sustained overhead were not measured.

### Reproducibility, validation and next decision

The [exact Swift fixture](gpu-calibration-2026-10-29.swift), [CPU-only supervisor](gpu-calibration-2026-10-29.py) and [aggregate result](gpu-calibration-2026-10-29.json) are dated experimental evidence, not production collectors or a supported probe command. SHA-256 values are `3a8da63f5b9dd047c2ce61be27fa98780b5adf5ea63a7edcf410e2d558033907` for Swift, `1c2f89dae20807bde7f877eb70ee0deeb344cf8f676f4d403cfdfb0b529818e8` for Python and `0082b7e37f6acab5a0b8e765a2baef8a854a1f7100a9cd857b5d4587895da797` for the JSON. No PID, process birth, registry ID or individual record values were persisted. Only the disposable worker's aggregate counters were retained.

Swift 6 type checking, Python syntax checking and eight offline numeric/reference checks passed before successful execution. Independent result assertions verified the 384-command cap, output and timing results, unchanged client membership, observed decrease and the actual-endpoint replay. Temporary executables and compilation logs were removed by the scratch wrapper. No production code or permanent test-suite additions were needed. Physical app interaction, other hardware/OS versions, late attachment to existing processes, shared-client ownership, overlapping work, exit tails, graphics memory and sustained cost remain untested.

The retained Python source expects a sibling named `calibration.swift`; reproduce offline preflight by copying both dated sources into the wrapper's scratch directory under their original names. Its default mode compiles and runs only numeric/reference checks; `--authorized-calibration` starts native work. The authorization was consumed by this completed calibration, so the following command intentionally performs **no native observation or GPU workload**:

```sh
python3 scripts/clean-build.py run -- bash -c 'cp docs/research/gpu-calibration-2026-10-29.swift "$AGENT_MONITOR_SCRATCH/calibration.swift" && cp docs/research/gpu-calibration-2026-10-29.py "$AGENT_MONITOR_SCRATCH/run.py" && python3 "$AGENT_MONITOR_SCRATCH/run.py"'
```

**Recommendation:** reject only treating the live client sum as continuously retained history. Continue research into bounded retained contributions and justified per-record matching, with an observed-work contract proportionate to CPU accounting: retain valid acquired increments, expose gaps, and assess material loss against actual workload lifetimes and explicit loss budgets. This coordinated fixture supplies neither that distribution nor those budgets. Producer source or stable record IDs are not mandatory if a separately authorized empirical study can characterize a defensible contract. Creator/lifetime binding and units remain unresolved. [GPU-01](../../PLAN.md#deferred-features) tracks the next research, and the [proposal](../proposals/gpu-resource-visibility.md) remains unapproved for production.

## Review reconciliation and task-counter source check — 2026-10-29

The external review and independent replays use the retained calibration JSON and fixture sources; the additional task-counter source check inspects pinned XNU and the installed SDK. Neither adds native observations or workloads. The reconciliation above corrects the earlier overly broad rejection by separating unseen lifetimes, aggregate cancellation and already-retained contributions, and examines the assumptions behind minimum-delta record matching.

### Task fields are a diagnostic candidate, not a promised replacement

In pinned [XNU `f6217f8`, task aggregation](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/task.c#L6785-L6851), `TASK_POWER_INFO_V2` derives GPU time from saved task totals plus live threads' `ml_gpu_stat`; [thread reaping](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/thread.c#L1061-L1080) retains that supplied statistic. The [arm64 getter returns zero](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/arm64/machine_routines.c#L2762-L2776). Its update path instead routes [`gpu_accumulate_time` deltas](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/energy_perf.c#L46-L52) to the [resource coalition](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/coalition.c#L1622-L1638). This predicts an unhelpful task field on that source revision, not the installed macOS 27 kernel; neither field naming nor coalition retention establishes complete driver charging, compatible `AppUsage` units or agent/session ownership.

SDK 27 declares the flavor and `task_info(task_name_t, …)`. The pinned [dispatch accepts a task-name port](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/task.c#L6445-L6478), without requiring task read/control rights for this flavor. Obtaining another process's name port remains a separate [identity and MAC-policy check](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/kern_proc.c#L5846-L5944); debugger-entitlement requirements for `task_for_pid` must not be transferred to this path. No self-task query was made during this source review; the [later lifecycle experiment](#record-lifecycle-and-aligned-timing-calibration--2026-10-29) checks the installed behavior. A rising self counter would still need units, ownership, queue-lifecycle and external-access validation; zero during verified work means unavailable measurement, not idle GPU use.

### Minimum-delta matching needs an explicit history model

A bounded matching model could minimize persistent-record increments across compatible partial one-to-one assignments, retain past accepted contributions, and admit newly visible counters only under justified baseline rules. Its minimum is a lower bound only if the real history belongs to the modeled alternatives. **No duplicate views is insufficient:** hypothetical `[10] → [100]` can mean that the old record retired and a distinct pre-existing record became visible without doing interval work. Persistence matching reports 90 and zero-at-birth admission reports 100, while true interval work can be zero. This is a counterexample to the proposed guarantee, not observed AGX behavior.

The model therefore needs explicit ownership/accounting scope, disjoint charges, stable units, continuation/reset rules, and treatment of imported or reappearing pre-baseline history and missing reads. Its real mapping must remain among the candidates; bounded computation or storage exhaustion must produce exclusions rather than arbitrary attribution. Under suitable assumptions, `[10, 100] → [20]` can preserve a 10-unit survivor increment despite a falling total. Equal numeric records can be interchangeable for an aggregate objective without proving identity. A finite range across visible matchings does not bound unseen lifetimes or final tails. The [subsequent offline model](#bounded-anonymous-matching-has-a-conditional-lower-bound--2026-10-29) resolves the mathematical question under explicit premises; it does not establish those premises for AGX.

## Bounded anonymous matching has a conditional lower bound — 2026-10-29

The [dated prototype](gpu-matching-model-2026-10-29.py), independent mathematical review and [saved finite corpus](gpu-matching-model-2026-10-29.json) establish a useful lower bound **within a closed-history model**. They do not validate native record semantics, units, ownership, coverage or cost. The prototype contains one synthetic fixed domain; it is not a production collector, multi-domain manager or time-window history implementation. The earlier native JSON lacks individual record values, so this matcher was not applied to invented native tuples.

### The real history must be among the admitted alternatives

One domain fixes acquisition run, device/client identity, exact process lifetime, accounting owner, schema, unit/charge interpretation and reset epoch. Between two coherent observation cuts, each source has a nonnegative, nondecreasing counter for distinct additive charge. Every closing-visible source either persisted from the opening cut or was genuinely born afterward at zero. Retirement is irreversible in its epoch; old hidden history cannot reappear, transfer, split, merge or reset into an apparent birth. True retired tails and wholly unseen lifetimes can add nonnegative charge. These are external admission premises, not facts the matcher can infer from endpoints; the theorem concerns accounted charge between cuts, not necessarily physical execution during their wall interval.

For opening multiset `B` and closing multiset `A`, let `M` be a partial injective matching of record occurrences with `b ≤ a`. Define **`L = sum(A) − max_M sum(matched B)`**. The actual persistence mapping is admissible under the model. Its objective equals survivor increments plus zero-born closing sources' counters; interval work additionally includes nonnegative retired tails and unseen lifetimes. Consequently `0 ≤ L ≤ actual interval charge`. A minimizing matching is a proof witness, not recovered source identity. For `[10, 100] → [20]`, `L = 10` retains a survivor lower bound despite the falling sum. Conversely `[10] → [100]` gives `L = 90` only in this model; previously accumulated hidden history becoming visible can make actual work zero and violates the premises. With unrestricted old-history visibility, every endpoint pair permits a zero-work explanation: the universal lower bound is zero, which is not evidence of idleness.

Sort both multisets descending. Discard an opening value larger than the largest remaining closing value; it cannot match anything remaining. Otherwise match those largest values. An exchange can insert that pair into any optimum without reducing matched opening weight, proving the greedy choice inductively. Complexity is `O((n+m) log(n+m))` with linear scratch; the scan advances at most `n` opening values. This proof covers homogeneous inequality edges, not arbitrary added timestamp constraints. Independently computed bounds conserve charge across nonoverlapping intervals and disjoint domains because each interval's real mapping supplies its own upper witness; guessed identities need not persist between intervals.

### Bounded state retains credits without bridging gaps

The prototype caps each snapshot at **128 records**, validates exact integer counters and checked sums within UInt64, and keeps one baseline, a sequence high-water mark, a reset epoch and a checked scalar credit ledger for one frozen synthetic domain. These are logical state/work bounds, not Python heap, native acquisition cost or production population bounds. A first observation or known new epoch establishes a baseline without crediting old history. Missing, invalid, duplicate/backward or skipped-sequence observations, unsupported history/schema, domain changes and capacity/overflow failures exclude the interval and clear its baseline while preserving accepted credit. A returned client rebaselines without backfill; valid empty records in a surviving client are distinct from client absence. The synthetic domain's frozen owner prevents later observations from reassigning earlier credits; it does not verify native ownership.

Accepted results carry `conditional_lower_bound`, including numeric zero, with `unseen_work_unbounded`. Baseline and unavailable results carry no increment. Even admitted `[10] → [10]` can represent an unchanged source or a zero-born replacement that accrued 10, so a zero lower bound cannot be displayed as idle. `supported_history=True` is an explicit synthetic premise; false produces unavailable rather than silently adopting a trivial zero. The model neither bridges rejected intervals nor derives source admission from numeric success.

### Independent oracle, adversarial review and reproducibility

The saved result records agreement with a recursive oracle that independently enumerates unmatched births and all eligible unused predecessors: **15,876 multiset pairs** and **1,600 ordered-array pairs**. Independently generated actual-work histories satisfy the bound across **80,275 one-interval histories** and **8,192 three-interval histories**, spanning **8,736 checked transitions**. Eight smoke cases and **63 state assertions** cover arithmetic and ledger limits. These finite checks support the implementation; the proof above supplies the general conditional argument. Six retained negative controls expose positional/aggregate clamping and imported, merged, split or nonzero-reset history. The latter histories violate admission premises and are not automatically detectable numeric anomalies.

The red phase's zero-return stub failed the survivor-retirement oracle before the greedy implementation passed. Independent review then corrected skipped-sequence acceptance and distinguished client departure from a valid empty record population, including baseline-only return. The final saved corpus passed after those corrections. No production source or permanent test suite changed, and no native call or GPU workload ran. Real-driver visibility/newborn/reset semantics remain unvalidated; useful coverage still depends on actual queue lifetimes and loss budgets.

The exact [source](gpu-matching-model-2026-10-29.py) has SHA-256 `3aa01b818d7e2282d55623ae4add46f08b2597ff5f5c21790e170195d651871e`; the [result](gpu-matching-model-2026-10-29.json) has SHA-256 `dfcd198cb5b8960631ed1f768514fca6d0212632403ec4a44e20273453b15b1a` and records Python 3.15.2. Both are dated offline research evidence, not a supported collector or shipping metric. This dependency-free reproduction prints the JSON once and performs no native observation:

```sh
python3 scripts/clean-build.py run -- bash -c 'python3 docs/research/gpu-matching-model-2026-10-29.py --output "$AGENT_MONITOR_SCRATCH/result.json"'
```

## Record lifecycle and aligned timing calibration — 2026-10-29

The user's instruction to resolve the reviewed GPU research autonomously authorized this next bounded experiment. It completed **384 verified serial commands and 60 registry reads in 4.907 seconds**, ending at **19:35:23 UTC**; the 20-second watchdog did not trigger. One owned worker used a 16,384-byte explicit buffer and six 64-command batches: A1, B1, A2 before B release, fresh Bprime, A3 before Bprime release, then fresh C1. A and C remained held through the final no-submit cooldown. The [exact fixture](gpu-record-lifecycle-2026-10-29.swift) and [supervisor](gpu-record-lifecycle-2026-10-29.py) retain the method. This authorization covered research, not production collection or UI changes; no existing user workload was manipulated and no root, private API or external task port was used.

### Native tuples support the exercised paths, not general admission

All reads verified the worker lifetime and were available. A, B, Bprime and C each first exposed `(accumulatedGPUTime, lastSubmittedTime) = (0, 0)` before submission; their selected numeric fields used signed Objective-C encoding `q`, retained exactly as decimal strings. Working records changed while idle held records stayed unchanged; released B/Bprime records disappeared. Queue-to-record association is inferred from this controlled sequence, not supplied as driver identity. `lastSubmittedTime` changes during a retained queue's work, and array index 1 is reused by distinct queues: neither is a stable record ID. The 14 immediate/nominal-50/nominal-200 ms triplets agreed, including releases, but application reference release does not prove driver destruction. These observations support zero-at-creation and survivor stability only on the exercised paths; they do not establish no imported/reappearing history, reset behavior, disjoint charging or exclusive ownership generally. [Retained tuples and observation bounds](gpu-record-lifecycle-2026-10-29.json).

The full-plane inventory found associated `AGXDeviceUserClient` and `IOSurfaceRootUserClient` entries. AGX initially exposed `AppUsage` and `IOUserClientCreator`; `CommandQueueCount` and `CommandQueueCountMax` appeared after A creation. Only those property names were inventoried, not their values or semantics. All **32** worker-self `TASK_POWER_INFO_V2` queries returned **KERN_SUCCESS**, word counts **26/26**, and GPU field **0** despite verified work. That field was unhelpful in this fixture, not evidence of GPU idleness or a permission failure; external-process accessibility and coalition accounting were not tested.

### Actual retirement and replacement permit useful conditional matching

Dense guarded aggregation and the retained anonymous matcher both preserve **66,835,624 raw units**, equal to the six isolated driver increments. The guarded replay excludes six zero-submission creation/release transitions after its baseline. Two selected-endpoint replays use the actual ordered counters; the independent exhaustive oracle agrees with the matcher:

| Selected interval | Opening → closing counters | Aggregate delta | Conditional lower bound | Isolated driver increments |
| --- | --- | ---: | ---: | ---: |
| B completed → B released after A2 | `[10,750,541, 11,538,458] → [22,148,625]` | −140,374 | **10,610,167** | A2: **11,398,084** |
| Bprime completed → C completed after A3 and Bprime release | `[22,148,625, 11,075,500] → [33,336,166, 10,885,500]` | 10,997,541 | **22,073,041** | A3 + C: **22,073,041** |

The first bound loses **787,917** to anonymous matching ambiguity: the larger old counter can match the surviving endpoint, although the fixture knows it belonged to B. The second recovers all isolated increments because C's final value is below Bprime's old value, excluding that false persistence edge. Different numeric ordering could yield a smaller conservative result; this is not general replacement recovery. The supervisor deliberately held queues around diagnostic checkpoints. These are replays omitting intermediate observations, **not independent 100 ms polling or a real queue census**. The comparison oracle is isolated driver increments, not calibrated physical GPU time, and none of the closed-history admission premises follows globally from this success. [Reproducible analysis](gpu-record-lifecycle-2026-10-29-analysis.py).

### Timing comparisons now align command populations

Each batch has 64 verified outputs, successful completion, no command errors and valid GPU/kernel/host timing summaries. GPU interval unions equal their sums with no overlap, as expected from serial waits. The following durations cover the same 64 commands; they are different measurements, not exclusive stages to add together.

| Batch | Raw increment | GPU elapsed ms | Metal kernel API ms | Commit → handler ms | Commit → wait return ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| A1 | 10,750,541 | 1.239291 | 1.179539 | 12.345750 | 12.804543 |
| B1 | 11,538,458 | 1.291375 | 1.155042 | 12.834873 | 13.412916 |
| A2 | 11,398,084 | 1.280124 | 0.896624 | 12.990664 | 13.619082 |
| Bprime | 11,075,500 | 1.284875 | 1.178625 | 13.075709 | 13.536460 |
| A3 | 11,187,541 | 1.414335 | 0.949876 | 12.940248 | 13.330914 |
| C1 | 10,885,500 | 2.587041 | 0.999084 | 14.718750 | 15.180168 |

First-command durations are retained separately, allowing aligned **63-command** counter/timing differences without mixing denominators; those values and property-read interval bounds are in the compact result. Assuming nanoseconds for comparison only, raw/GPU ratios are **4.208–8.935**, while raw/host-handler ratios are **0.740–0.899**. Raw values are nearer host completion durations here but not identical; this neither proves units nor defines a charging rule or GPU capacity share. The full-plane inventory reader took **15.189–33.456 ms per read**, median **17.661 ms**, total **1,178.545 ms**. This diagnostic observer is broader than the earlier narrow AGX reader; it supplies neither a production cost budget nor measured CPU overhead.

### Compact evidence and offline verification

The [compact result](gpu-record-lifecycle-2026-10-29.json) preserves all 60 labels/read bounds/ordered tuple arrays through 19 tuple-state and three inventory catalogs, all six timing summaries, and all 32 self-task readings as their asserted-identical result plus ordered checkpoint labels. Catalog references are compression indices, not record identities. Selected tuples belong only to the owned worker; no raw PID, registry ID, birth, creator string or user path was retained. The compact artifact is 32,222 bytes, derived from a 189,893-byte original result whose SHA-256 is `768b2c468355663a3599c02cfe9355c21b9eb7553885d4d08bc619faf59e95ae`.

Device Apple M1 comes from the worker; Swift 6.4/SDK 27.0 come from preflight. macOS **27.0.1**, build **26A434**, arm64 were separately queried after execution, not emitted by the worker. Both source defaults run offline preflight checks rather than native worker/observer modes; the exact supervisor expects its Swift sibling under the original name `calibration.swift`, not the dated archive name. Preflight passed Swift type checking and pure numeric/schema/lifetime-intent checks; independent analyses verified compact data and matching/timing arithmetic without another native run. Exact retained hashes are:

| Evidence | SHA-256 |
| --- | --- |
| [Swift fixture](gpu-record-lifecycle-2026-10-29.swift) | `2382396916dcbc8e3fce3e3b3a7b6e983723ea3dbb5ab07fc240b856828169a3` |
| [Supervisor](gpu-record-lifecycle-2026-10-29.py) | `cc3187fb86a085bbe3ff364a1b3c370f0b113857a2c04e77c0aaa55b43244499` |
| [Compact result](gpu-record-lifecycle-2026-10-29.json) | `f058af5f8fe480efd0d3285ea36e22f8c0c1a75829c007a8117f4961a0434ffc` |
| [Analyzer](gpu-record-lifecycle-2026-10-29-analysis.py) | `e8cb0897644352099e60c564df8d7f012e51bf395438a6eeaf66df57f479b25a` |

The analyzer verifies the compact result against the retained matching model without the original output, native calls or a new workload:

```sh
python3 scripts/clean-build.py run -- python3 -B docs/research/gpu-record-lifecycle-2026-10-29-analysis.py --compact docs/research/gpu-record-lifecycle-2026-10-29.json --model docs/research/gpu-matching-model-2026-10-29.py
```

The evidence supports continued bounded observed-contribution research for characterized paths. Native history admission beyond those paths, actual counter units/charging, exclusive process ownership, real queue-lifetime coverage and sustained collector cost remain unresolved. Repeating this same held-queue fixture cannot settle those gaps; production remains unapproved.

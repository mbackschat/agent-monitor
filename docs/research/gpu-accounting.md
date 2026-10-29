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

[Apple XNU at `f6217f8`](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/task.c#L6785-L6906) and its [arm64 implementation](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/arm64/machine_routines.c#L2762-L2776) explain why public task GPU fields can remain zero without useful process instrumentation. This 2025-10-16 source is not proof of the installed macOS 27 kernel. A present field returning zero must not become a fallback claim that GPU work is idle. Apple's [debugger-entitlement documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.debugger) also establishes that same-user identity alone is not a sufficient `task_for_pid` access guarantee.

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

**The live client total is not a continuously retained cumulative counter on this M1.** Under one unchanged client identity, releasing application references to queue B removed its record and its accumulated value. More seriously, selecting two actual observations around B's entire lifetime yields the same record count and an increasing client total while omitting all of B's already-observed increment. This falsifies the proposed cumulative-client shortcut; neither monotonicity nor equal endpoint record counts repair it. It does not establish that every driver version behaves identically or that no other GPU accounting route is possible.

### Authorized method and successful work oracle

The user explicitly authorized the previously proposed calibration on 2026-10-29. One disposable unprivileged Metal worker ran three serial batches: A, B while A was retained idle, and A after B's application references were released through a drained autorelease pool. One shared 16,384-byte data buffer held 4,096 input-dependent integers; every command applied 256 bounded arithmetic iterations per thread. CPU reference values were computed independently of Metal, including a Python-checked known vector, and every command's full output was compared with them. No pre-existing user process was signalled or instrumented, and no provider, task port, private framework, root access or system security-configuration change was used.

Each batch stopped at 128 completed submissions or 200 ms of valid accumulated command elapsed time, whichever came first. All three hit the submission cap: **384 commands total**, with successful completion, no command errors, verified outputs, no invalid GPU timestamps and no timestamp overlaps. Summed command durations equalled their interval unions. The worker and observations took **3.107 seconds**, including a **0.278-second setup**, delayed reads and a one-second no-submit cooldown. The external 20-second watchdog did not trigger. The explicit buffer bound does not bound compiler/framework/driver allocations, and a watchdog cannot cancel GPU work already submitted.

The CPU-only observer recorded 32 reads, with same-user process birth checked before and after each traversal and creator PID rechecked around each client's property read. It retained only the owned worker's client IDs and individual counters in bounded memory, emitting aggregate counts and values. Samples bracketed device/queue creation, first commands, each batch and reference release; immediate, nominal 50 ms and 200 ms samples have their actual read start/end times in the [sanitized result](gpu-calibration-2026-10-29.json). The initial restricted-environment attempt returned no Metal device and submitted no GPU work; the authorized retry outside that execution sandbox succeeded without elevated UID. This is not app-sandbox compatibility evidence.

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

The same client registry identity remained present after device creation; no client departure or replacement was observed. `AppUsage` exposed only `API`, `accumulatedGPUTime` and `lastSubmittedTime`, without a stable record ID. Record count followed queue creation/release in this fixture. B's release reduced the aggregate by exactly **31,381,500**, equal to the increase during B's isolated batch. The immediate, 50 ms and 200 ms readings agreed at each of these checkpoints, including release, and no deferred increase appeared during cooldown. “Immediate” means the first completed registry read after the worker checkpoint, not zero reporting latency. Reference release did not force or independently verify driver destruction.

A deterministic replay using actual endpoint observations reproduces a second manifestation of the same mechanism: compare the end of A's first batch with the end of A's second. Both have one record, one unchanged client and verified worker lifetime; the total rises from 31,715,000 to 59,188,083. Endpoint subtraction reports **27,473,083**, although the separately observed B and second-A increments sum to **58,854,583**. It misses B's entire 31,381,500 without a negative delta or record-count change at either endpoint. This replay is not another native trial; it demonstrates how a reader with a longer interval can miss the retirement seen by the tightly coordinated observer.

Keeping per-client baselines prevents cross-client cancellation but cannot fix this within-client loss. Clamping a decrease to zero or rebaselining on a detected count change cannot detect the replay above. Stable accounting-record identity could preserve previously observed contributions, but it would still leave final increments and records born and removed between observations unmeasured. The existing product coverage priority prevents describing those unknown losses as complete agent/session GPU use.

### Raw driver increments do not calibrate Metal elapsed time

| Batch | Verified commands | Raw driver increment | Metal command elapsed/union | Batch wall time including first-command observation |
| --- | ---: | ---: | ---: | ---: |
| A first | 128 | 31,715,000 | 2.834 ms | 38.907 ms |
| B | 128 | 31,381,500 | 2.825 ms | 41.903 ms |
| A second | 128 | 27,473,083 | 2.694 ms | 34.131 ms |

If the raw units were nanoseconds, these increments would represent 31.715, 31.382 and 27.473 ms, substantially greater than the Metal elapsed times. That is a conditional comparison, not a unit determination or evidence that either measurement is wrong. The workload does not establish what the driver charges, a conversion factor, GPU occupancy or percentage of capacity. These very short cap-limited batches also do not characterize arbitrary workloads or concurrent execution. The observer's 32 registry traversals took 0.995–2.589 ms wall time each, median 1.425 ms, 49.139 ms total; reader CPU and sustained overhead were not measured.

### Reproducibility, validation and next decision

The [exact Swift fixture](gpu-calibration-2026-10-29.swift), [CPU-only supervisor](gpu-calibration-2026-10-29.py) and [aggregate result](gpu-calibration-2026-10-29.json) are dated experimental evidence, not production collectors or a supported probe command. SHA-256 values are `3a8da63f5b9dd047c2ce61be27fa98780b5adf5ea63a7edcf410e2d558033907` for Swift, `1c2f89dae20807bde7f877eb70ee0deeb344cf8f676f4d403cfdfb0b529818e8` for Python and `0082b7e37f6acab5a0b8e765a2baef8a854a1f7100a9cd857b5d4587895da797` for the JSON. No PID, process birth, registry ID or individual record values were persisted. Only the disposable worker's aggregate counters were retained.

Swift 6 type checking, Python syntax checking and eight offline numeric/reference checks passed before successful execution. Independent result assertions verified the 384-command cap, output and timing results, unchanged client membership, observed decrease and the actual-endpoint replay. Temporary executables and compilation logs were removed by the scratch wrapper. No production code or permanent test-suite additions were needed. Physical app interaction, other hardware/OS versions, late attachment to existing processes, shared-client ownership, overlapping work, exit tails, graphics memory and sustained cost remain untested.

The retained Python source expects a sibling named `calibration.swift`; reproduce offline preflight by copying both dated sources into the wrapper's scratch directory under their original names. Its default mode compiles and runs only numeric/reference checks; `--authorized-calibration` starts native work. The authorization was consumed by this completed calibration, so the following command intentionally performs **no native observation or GPU workload**:

```sh
python3 scripts/clean-build.py run -- bash -c 'cp docs/research/gpu-calibration-2026-10-29.swift "$AGENT_MONITOR_SCRATCH/calibration.swift" && cp docs/research/gpu-calibration-2026-10-29.py "$AGENT_MONITOR_SCRATCH/run.py" && python3 "$AGENT_MONITOR_SCRATCH/run.py"'
```

**Recommendation:** reject the cumulative-client-total design for contributor rates on the observed schema. A replacement requires evidence of suitable accounting identity and retention semantics, or a different accounting source, before further load calibration or production implementation. The generic creator/lifetime problem remains open but solving it alone cannot repair this demonstrated loss. Device-level activity remains a separate possible context feature; it must not be presented as agent GPU attribution or silently substituted for the user's accountability request. [GPU-01](../../PLAN.md#deferred-features) tracks that decision, and the [proposal](../proposals/gpu-resource-visibility.md) remains unapproved for production.

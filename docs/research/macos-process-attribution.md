# macOS process measurement and attribution

Research checked on 2026-10-14. This note separates platform evidence from proposed behavior; no collector was implemented and no user process arguments or environment variables were inspected. Apple open-source `main` and online documentation can be ahead of a deployed operating system, so the installed SDK and intended minimum OS must settle availability before implementation.

This platform review preceded targeted local inspection. The [terminal observations](terminal-process-observations.md) record later allowlisted marker probes and synthetic orphan experiments; the [Codex terminal investigation](codex-terminal-attribution.md) adds pinned provider semantics. Read their evidence alongside the untested cases below. The current product priority is heavy-consumer attribution to specific terminal Codex sessions, followed by Claude Code.

## What can a headless collector measure accurately?

### Takeaway

A same-user collector built on Darwin/libproc is a feasible foundation. Define CPU as an interval measurement and memory as physical footprint, with RSS separately labeled; neither an executable name nor a PID alone is sufficient identity.

### Cited Findings

- `proc_listpids` enumerates processes; `proc_pidinfo` retrieves selected metadata; `proc_pidpath` retrieves an executable path; `proc_pid_rusage` returns resource counters. These are direct process-information calls rather than a requirement to obtain another process's Mach task port. — [Apple libproc implementation](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.c)
- `proc_bsdinfo` exposes PID, parent PID, effective/real user IDs, process group, controlling terminal, and start time with microseconds. `proc_vnodepathinfo` includes current/root directory paths. `proc_taskinfo` distinguishes resident and virtual memory. — [Apple process information structures](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc_info.h)
- Resource information contains CPU user/system counters, resident size, physical footprint, and process start/exit absolute times. Later versions add child accounting and I/O. — [Apple resource structures](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/resource.h)
- The kernel populates resource CPU values from task power accounting; the inspected implementation carries Mach time values, so raw counters must not casually be called nanoseconds. Both CPU and elapsed time must use a consistent timebase. — [Resource population](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c), [task power accounting](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c)
- A self-only local check on 2026-10-14 compared `proc_pid_rusage(RUSAGE_INFO_V0)` user+system counters with Python `time.process_time_ns()`, without a load loop. The Mach timebase was 125/3; raw counters were approximately 0.024 times CPU nanoseconds, while applying that timebase yielded a ratio of 1.000 to three decimal places. This corroborates the Mach-unit interpretation on the observed machine; it is not a cross-platform benchmark. — Local disposable probe; [source assignment at `bsd_kern.c` lines 1196–1197](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c#L1196), [Mach source counters at `task.c` lines 6391–6392](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c#L6391)
- Physical footprint includes internal and compressed memory, certain IOKit mappings, nonvolatile purgeable memory, and page tables, with accounting corrections. It differs from resident memory. — [Apple task ledger definition](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c)
- `proc_pid_rusage` applies same-user checks and mandatory access-control checks; a process can disappear during lookup. Some lighter metadata queries have different permission checks. Same-user access is therefore a practical baseline, not a promise that every field is always readable. — [Apple `proc_security_policy` and `proc_pid_rusage`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/proc_info.c)
- Rust `sysinfo` exposes CPU percentages that can exceed 100%, requires successive refreshes for meaningful CPU deltas, reports RSS through `memory()`, and exposes process start time only in seconds through its public accessor. Its generic memory value is not a substitute for macOS footprint. — [sysinfo Process documentation](https://docs.rs/sysinfo/latest/sysinfo/struct.Process.html)

### Inferences

- Recommended CPU contract: `cpuPercent = 100 × Δ(userCPU + systemCPU) / Δelapsed`, using matching units and a monotonic elapsed clock. One fully occupied CPU is 100%; four occupied CPUs can approach 400%. A threshold of 25% therefore means one quarter of one CPU, not one quarter of the whole machine. Display the sample interval and treat the initial sample as unavailable, not zero.
- Recommended memory contract: compare `physicalFootprintBytes` with an explicit byte threshold, initially `1_000_000_000` for 1 GB; offer RSS as a secondary diagnostic. If choosing binary units instead, label 1 GiB and use `1_073_741_824`. Virtual address space is unsuitable as the primary alert metric.
- Key a process by PID plus high-resolution start identity, with a boot boundary when retaining history. Revalidate identity around multi-call sampling; discard a mismatched sample rather than attaching another process's counters to an old PID. Do not use executable UUID as process identity: the kernel resource path obtains an executable UUID. — [Apple resource initialization](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_resource.c)
- Sum each distinct attributed process once for a session total. Do not add cumulative child counters to a sum that already includes those children. Label a memory sum as aggregate process footprint, not exact unique physical RAM or guaranteed reclaimable RAM.
- Expose denied, exited, unsupported, and unsampled states independently from measured zero. Query richer metadata selectively and cache identity-bound values to limit the collector's own cost.

### Gaps

- No supported-OS permission matrix or sampling-overhead benchmark was run. Same-user native terminals, agent sandboxes, signed applications, and privileged children require separate validation.
- The exact match between footprint and the current Activity Monitor Memory column was not established. A comparison must account for different refresh timing and accounting definitions rather than promise byte-identical output.
- CPU sleep/wake behavior, reset behavior, and any supported Intel configuration need explicit fixtures. The self-only Mach-time check corroborates units on this one machine, not the complete CPU sampling contract.

## How reliably can a workload be assigned to its agent session?

### Takeaway

Observed ancestry plus explicit session metadata can provide useful attribution, including retained attribution after a known parent exits. Polling alone cannot recover every missed short-lived ancestor or prove responsibility for work delegated to a shared service; attribution must preserve evidence and uncertainty.

### Cited Findings

- An exiting parent normally leaves its children reparented to PID 1, erasing the original link from a later ordinary parent-PID snapshot. — [Apple `_exit(2)` manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/_exit.2.html)
- `EVFILT_PROC` reports events such as fork, exec, and exit for a watched process. Darwin's header explicitly says the fork child's PID is not passed through in the delivered kevent; `NOTE_TRACK`, `NOTE_TRACKERR`, and `NOTE_CHILD` have been unsupported since macOS 10.5. Therefore BSD examples using automatic recursive kqueue child tracking do not establish macOS support. — [Apple kqueue manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/kqueue.2.html), [current Darwin event header](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/event.h)
- Endpoint Security can notify clients about execution and fork activity. It provides a parent audit token, available from message version 4, and sequence counters for detecting dropped events. Event-driven collection must therefore still detect coverage loss. — [Endpoint Security](https://developer.apple.com/documentation/endpointsecurity), [parent token](https://developer.apple.com/documentation/endpointsecurity/es_process_t/parent_audit_token), [sequence counter](https://developer.apple.com/documentation/endpointsecurity/es_message_t/seq_num)

### Inferences

- Preserve the ancestry observed while processes coexist, including the identity of each parent, observation time, and session assignment. A current PPID of 1 need not invalidate a previously evidenced association. An already-orphaned process first seen after monitoring starts requires other evidence or remains unattributed.
- Distinguish OS process identity, agent conversation/session identity, project identity, and command/tool invocation identity. A session can span multiple commands, and multiple sessions can share one project, executable, terminal host, or build service.
- Prefer explicit agent-issued session identifiers or registered launch metadata when available; cross-check with ancestry and start identity. Current working directory and executable name are contextual evidence, not unique session identifiers. Agent integration details belong in the companion research on development skills and agent metadata.
- A daemon such as a shared build server may have been started by session A while doing work requested by session B. Descendant attribution answers origin; it does not by itself establish the causal owner of each later request. Preserve an explicit shared/ambiguous state instead of charging all activity confidently to the creator.
- A minimal attribution result should name the process, session/project when known, observed ancestor chain, attribution basis, confidence/limitations, CPU interval, and memory metric. Keep unmatched high-resource processes visible so detection failure does not hide the user's actual problem.
- kqueue is useful for promptly invalidating known process records or prompting a rescan. It should not be advertised as a lossless process genealogy mechanism.

### Gaps

- The remaining false-positive and false-negative rates depend on actual Codex CLI and Claude Code process topologies and their metadata lifecycle. Those must be exercised rather than inferred from process names.
- Required validation cases include an intermediate shell that exits before the next scan, a child that outlives its agent, PID reuse, `exec` preserving a PID, two sessions in the same directory, two agents under one terminal host, a shared build daemon, and unreadable metadata. These are proposed correctness oracles, not completed tests.
- A workload inside a VM/container or on a remote host may appear locally only as its VM/service/transport process. Host libproc evidence does not establish individual remote task consumption.

## What permissions and technology choices fit the product progression?

### Takeaway

Recommend a Swift package containing a headless collection/attribution library and a small executable harness, with no privileged service initially. Swift keeps the path to a native menu bar app direct; Rust remains credible if its ecosystem or existing reusable implementation provides a stronger starting point.

### Cited Findings

- Swift packages can contain library, executable, and test targets, including C-family modules. Swift interoperates with C and Objective-C by default. Apple maintains Swift Argument Parser for command-line interfaces. — [Swift packages](https://docs.swift.org/latest/documentation/packagemanagerdocs/introducingpackages/), [Swift interoperability](https://www.swift.org/documentation/cxx-interop/), [Swift Argument Parser](https://github.com/apple/swift-argument-parser)
- SwiftUI `MenuBarExtra` supports a persistent menu bar control, including a richer window-style presentation. A menu-bar-only application can terminate when its extra is removed; that matters if collection is intended to continue independently of UI presence. — [Apple MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- Conventional Endpoint Security clients require Apple's restricted endpoint-security entitlement. Apple supports daemon-based clients as well as system extensions, and Full Disk Access is required for conventional client creation. The installed SDK additionally documents a non-root failure condition. — [Apple entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.endpoint-security.client), [Apple DTS clarification](https://developer.apple.com/forums/thread/791996), [client result documentation](https://developer.apple.com/documentation/endpointsecurity/es_new_client_result_err_not_privileged)
- A newer `es_new_descendants_client` API is documented as beta. The installed Xcode SDK declares macOS 27.0 availability and states that it requires the entitlement but neither root nor TCC approval. Its visibility is limited to the caller and its descendants, including existing descendants. This was checked by reading `ESClient.h` on 2026-10-14, not by creating a client. — [Apple descendants-client documentation](https://developer.apple.com/documentation/endpointsecurity/es_new_descendants_client(_:_:)), [local SDK declaration](/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/EndpointSecurity/ESClient.h:798)

### Inferences

- Start with normal user privileges and support the current user's agent workloads. Public libproc bindings plus a narrow native adapter avoid requiring `task_for_pid`, Endpoint Security approval, or a system extension merely to measure CPU and memory. Validate any sandboxed distribution separately; kernel access checks mean an unsandboxed prototype does not establish App Store feasibility.
- Keep platform sampling, process/session attribution, and presentation separate. The headless stage can expose typed snapshots and structured output for validation; CLI formatting and SwiftUI can consume the same domain model. No long-running daemon is necessary to prove collection correctness.
- Swift is the smallest overall choice for an explicitly Mac-only product with possible native UI. Rust plus `sysinfo`/libproc is feasible, but footprint and high-resolution identity still require a macOS-specific path, and a native SwiftUI shell introduces another boundary. This is a recommendation from the stated scope, not a measured performance claim.
- Treat full Endpoint Security as an optional later evidence source if polling plus agent metadata proves insufficient. It introduces entitlement approval, deployment/permission work, event backpressure, and coverage bookkeeping; do not require it for the first useful version.
- The descendants-only API is interesting for a future opt-in launcher, but it cannot observe arbitrary already-running sessions outside its subtree. Its entitlement and deployment floor also prevent assuming it is a universal unprivileged replacement for global observation.
- Do not request Full Disk Access as a generic remedy for sampling errors. Permission requests should follow the precise failed capability; reading agent metadata and collecting process counters are separate access questions.

### Gaps

- The minimum supported macOS release, Intel support, App Store ambition, always-on behavior, and acceptable wrapper/hook installation remain product decisions. None prevents initial same-user collection research.
- No entitlement application, permission changes, dependency installation, or project scaffolding was performed. No assertion is made that Apple will grant an Endpoint Security entitlement to this product.
- The installed SDK exposes descendants-only monitoring while the website still labels it beta; deployment status and semantics require rechecking when implementation begins. For the present recommendation it is an optional research lead.

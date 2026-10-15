# macOS process measurement and attribution

Research checked on 2026-10-14. This platform investigation inspected source and ran a self-only counter probe; it did not implement a collector or inspect other processes' arguments or environments. Current contracts and validation belong in [architecture](../architecture.md) and [development](../development.md#validation-coverage). Apple open-source `main` and online documentation can be ahead of a deployed operating system, so these sources alone do not establish availability on every deployment target.

This platform review preceded targeted local inspection. The [terminal observations](terminal-process-observations.md) record later allowlisted marker probes and synthetic orphan experiments; the [Codex terminal investigation](codex-terminal-attribution.md) adds pinned provider semantics. Read their evidence alongside the untested cases below.

## What can a headless collector measure accurately?

### Cited Findings

- `proc_listpids` enumerates processes; `proc_pidinfo` retrieves selected metadata; `proc_pidpath` retrieves an executable path; `proc_pid_rusage` returns resource counters. These are direct process-information calls rather than a requirement to obtain another process's Mach task port. — [Apple libproc implementation](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.c)
- `proc_bsdinfo` exposes PID, parent PID, effective/real user IDs, process group, controlling terminal, and start time with microseconds. `proc_vnodepathinfo` includes current/root directory paths. `proc_taskinfo` distinguishes resident and virtual memory. — [Apple process information structures](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc_info.h)
- Resource information contains CPU user/system counters, resident size, physical footprint, and process start/exit absolute times. Later versions add child accounting and I/O. — [Apple resource structures](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/resource.h)
- The kernel populates resource CPU values from task power accounting; the inspected implementation carries Mach time values, rather than nanoseconds; a CPU/elapsed ratio requires consistent units. — [Resource population](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c), [task power accounting](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c)
- A self-only local check on 2026-10-14 compared `proc_pid_rusage(RUSAGE_INFO_V0)` user+system counters with Python `time.process_time_ns()`, without a load loop. The Mach timebase was 125/3; raw counters were approximately 0.024 times CPU nanoseconds, while applying that timebase yielded a ratio of 1.000 to three decimal places. This corroborates the Mach-unit interpretation on the observed machine; it is not a cross-platform benchmark. — Local disposable probe; [source assignment at `bsd_kern.c` lines 1196–1197](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c#L1196), [Mach source counters at `task.c` lines 6391–6392](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c#L6391)
- Physical footprint includes internal and compressed memory, certain IOKit mappings, nonvolatile purgeable memory, and page tables, with accounting corrections. It differs from resident memory. — [Apple task ledger definition](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c)
- `proc_pid_rusage` applies same-user checks and mandatory access-control checks; a process can disappear during lookup. Some lighter metadata queries have different permission checks. Same-user access is therefore a practical baseline, not a promise that every field is always readable. — [Apple `proc_security_policy` and `proc_pid_rusage`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/proc_info.c)
- Rust `sysinfo` exposes CPU percentages that can exceed 100%, requires successive refreshes for meaningful CPU deltas, reports RSS through `memory()`, and exposes process start time only in seconds through its public accessor. Its generic memory value is not a substitute for macOS footprint. — [sysinfo Process documentation](https://docs.rs/sysinfo/latest/sysinfo/struct.Process.html)

### Inferences

Consistent time units permit `100 × Δ(userCPU + systemCPU) / Δelapsed`, with one occupied core represented by 100%. A first observation supplies no delta. Physical footprint and RSS measure different things; summing process footprint is not necessarily unique physical RAM or reclaimable memory.

PID reuse and multi-call sampling can combine observations from different lifetimes. An executable UUID identifies an image, not a process lifetime ([resource initialization](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_resource.c)). Read failures and vanished processes do not establish zero resource use.

### Gaps

- No supported-OS permission matrix or sampling-overhead benchmark was run. Same-user native terminals, agent sandboxes, signed applications, and privileged children require separate validation.
- The exact match between footprint and the current Activity Monitor Memory column was not established. A comparison must account for different refresh timing and accounting definitions rather than promise byte-identical output.
- CPU sleep/wake behavior, reset behavior, and any supported Intel configuration need explicit fixtures. The self-only Mach-time check corroborates units on this one machine, not the complete CPU sampling contract.

## How reliably can a workload be assigned to its agent session?

### Cited Findings

- An exiting parent normally leaves its children reparented to PID 1, erasing the original link from a later ordinary parent-PID snapshot. — [Apple `_exit(2)` manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/_exit.2.html)
- `EVFILT_PROC` reports events such as fork, exec, and exit for a watched process. Darwin's header explicitly says the fork child's PID is not passed through in the delivered kevent; `NOTE_TRACK`, `NOTE_TRACKERR`, and `NOTE_CHILD` have been unsupported since macOS 10.5. Therefore BSD examples using automatic recursive kqueue child tracking do not establish macOS support. — [Apple kqueue manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/kqueue.2.html), [current Darwin event header](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/event.h)
- Endpoint Security can notify clients about execution and fork activity. It provides a parent audit token, available from message version 4, and sequence counters for detecting dropped events. The sequence counters make coverage loss observable. — [Endpoint Security](https://developer.apple.com/documentation/endpointsecurity), [parent token](https://developer.apple.com/documentation/endpointsecurity/es_process_t/parent_audit_token), [sequence counter](https://developer.apple.com/documentation/endpointsecurity/es_message_t/seq_num)

### Inferences

A captured parent edge can outlive the parent's appearance in a later snapshot. A process first observed after detachment instead needs surviving metadata or another runtime association. Cwd, executable and terminal can be shared by several sessions and are not unique ownership evidence.

An inherited marker establishes launch origin, not the requester of later work inside a shared daemon. kqueue can indicate that a rescan is useful but cannot provide a lossless genealogy on Darwin under the documented event limitations.

### Gaps

- The remaining false-positive and false-negative rates depend on actual Codex CLI and Claude Code process topologies and their metadata lifecycle. Process names alone do not establish those rates.
- A workload inside a VM/container or on a remote host may appear locally only as its VM/service/transport process. Host libproc evidence does not establish individual remote task consumption.

## Process access and Endpoint Security

### Cited Findings

- Conventional Endpoint Security clients require Apple's restricted endpoint-security entitlement. Apple supports daemon-based clients as well as system extensions, and Full Disk Access is required for conventional client creation. The installed SDK additionally documents a non-root failure condition. — [Apple entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.endpoint-security.client), [Apple DTS clarification](https://developer.apple.com/forums/thread/791996), [client result documentation](https://developer.apple.com/documentation/endpointsecurity/es_new_client_result_err_not_privileged)
- A newer `es_new_descendants_client` API is documented as beta. The installed Xcode SDK declares macOS 27.0 availability and states that it requires the entitlement but neither root nor TCC approval. Its visibility is limited to the caller and its descendants, including existing descendants. This was checked by reading `ESClient.h` on 2026-10-14, not by creating a client. — [Apple descendants-client documentation](https://developer.apple.com/documentation/endpointsecurity/es_new_descendants_client(_:_:)), [local SDK declaration](/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/EndpointSecurity/ESClient.h:798)

### Inferences

The libproc interface can collect these counters without a Mach task port. That does not establish access to every process, every field or sandboxed distribution. Endpoint Security's entitlement and event coverage are separate from permission to read ordinary process metadata.

The descendants-only API cannot discover arbitrary sessions outside the caller's subtree. This visibility limit persists even if its non-root client creation succeeds.

### Gaps

- No entitlement application, permission changes, dependency installation, or project scaffolding was performed. No assertion is made that Apple will grant an Endpoint Security entitlement to this product.
- The installed SDK exposes descendants-only monitoring while the website still labels it beta; deployment status and semantics require rechecking when implementation begins.

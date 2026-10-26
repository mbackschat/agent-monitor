# Swift terminal UI findings

Checked 2026-10-14 with Swift 6.4 on Apple Silicon/macOS 27. Sources and an isolated synthetic SwiftTUI probe were inspected; the probe was subsequently removed. The adopted host and dependency boundary are documented in [architecture](../architecture.md#swifttui-host-evaluation); this note records the evidence behind them.

## Libraries inspected

| Library | Findings and limits |
|---|---|
| [SwiftTUI/swift-tui](https://github.com/SwiftTUI/swift-tui/tree/0.14.0) | Version 0.14.0, revision `581c3ab7e2383ce86fcebe36e81041aecac443a5`, built with Swift 6.4. `SwiftTUIRuntime` and `SwiftTUICLI` expose a terminal host without compiling the umbrella's web host. The scene launcher has a separate discovery-socket requirement. |
| [phranck/TUIkit](https://github.com/phranck/TUIkit) | Documentation describes tables, lists, focus, keyboard handling and lifecycle. Upstream labeled the API work in progress; no local runtime comparison was performed. |
| [rensbreur/SwiftTUI](https://github.com/rensbreur/SwiftTUI) | A distinct repository with a SwiftUI-like API, scrolling and keyboard focus. Compatibility with this toolchain was not tested. |
| [Tuist Noora](https://noora.tuist.dev/components/tables/static) | Documentation establishes CLI components and static tables, not the complete continuously updating screen lifecycle needed here. |

## Sandbox-compatible terminal host

The scene-based probe rendered once and exited with `Failed to bind discovery socket ... Operation not permitted`. The tagged [TerminalRunner](https://github.com/SwiftTUI/swift-tui/blob/0.14.0/Platforms/CLI/Sources/SwiftTUITerminalCLI/TerminalRunner.swift) creates a discovery server even for a single window. Selecting a terminal-only package product did not avoid that IPC.

The documented [RunLoop entry point](https://github.com/SwiftTUI/swift-tui/blob/0.14.0/Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Running-Apps.md) worked with `TerminalHost`, `InputReader`, `SignalReader`, state and focus tracking. The probe did not start `TerminalRunner`, a browser or a discovery service. SwiftTUI retained ownership of raw mode, drawing, input and cleanup; no upstream fork or permission change was needed. Test-only screen helpers used the pinned framework's testing SPI.

## Observed behavior and limits

The synthetic PTY journey passed refresh, disclosure, resizing from 100×24 to 60×16, Ctrl-C and restoration of terminal flags, cursor and alternate screen. Separate runs passed color/NO_COLOR and SIGTERM cleanup. Debug smoke runs used about 6.3% of one core and 42 MB peak RSS; optimized smoke runs used 1.28–1.60% and 26.2 MB. These short, startup-inclusive measurements describe the probe, not the production collector or physical footprint.

The PTY peer had to keep draining output while awaiting exit: the tagged POSIX controller's `TCSAFLUSH` restoration waited for queued output. Stopping reads falsely reported a hung child with both Foundation `Process` and `posix_spawn`; draining corrected it. This probe finding does not explain every later PTY timeout.

An uninterrupted optimized build completed in 482 seconds. Earlier terminated builds did not establish an upstream compiler incompatibility. The tagged styling API was `.foregroundStyle`; examples for other revisions or the similarly named repository are not evidence of 0.14.0 compatibility.

The probe did not inspect processes or validate attribution. Production [terminal checks](../development.md#terminal-and-machine-output-checks), [coverage limits](../development.md#validation-coverage) and [measurements](README.md#retained-measurements) are separate evidence.

## Ordered input and retention boundary — 2026-10-26

Provenance: source review of Agent Monitor `e798ec9` and the locked SwiftTUI 0.14.0 revision `581c3ab7e2383ce86fcebe36e81041aecac443a5`, independently checked by a read-only review. No build, terminal stress test, native profile or workload observation was performed for this investigation. These are source mechanisms, not measured heap sizes or observed user failures. The earlier [retained-state audit](menu-bar-load-cost.md#retained-state-ownership-audit--2026-10-26) identified the streams; the following review traces the entire input path.

| Stage | Pinned source | Finding |
| --- | --- | --- |
| Raw read turn | [TerminalInputStreamReading.swift](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Sources/SwiftTUIRuntime/Input/TerminalInputStreamReading.swift#L103) | `drainAvailableTerminalInput` appends 256-byte reads until EAGAIN, EOF or error; 256 bounds a syscall, not the accumulated array. A continuously readable descriptor can keep the dispatch handler occupied. |
| Partial decoding | [TerminalInputParser.swift](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Sources/SwiftTUIRuntime/Input/TerminalInputParser.swift#L770) | An incomplete bracketed paste remains in `bufferedBytes`. Completion creates a payload array and a String. A single paste can exceed any event-count-only allowance before the composer sees it. |
| Reader stream | [InputReader.swift](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Sources/SwiftTUIRuntime/Input/InputReader.swift#L468), [stream helper](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Sources/SwiftTUIRuntime/Support/AsyncStreamTeardown.swift) | The native reader uses the helper's default-unbounded AsyncStream and produces independently of dispatch. |
| Host wrapper | [ActionInputReader.swift](../../Sources/AgentMonitorTUI/ActionInputReader.swift) | Adds another default-unbounded stream. Paste is applied immediately to shared state on MainActor, while keys are yielded for later runtime dispatch. |
| Pump and dispatch | [EventPumpBuffer.swift](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Sources/SwiftTUIRuntime/RunLoop/EventPumpBuffer.swift), [RunLoop+EventPump.swift](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Sources/SwiftTUIRuntime/RunLoop/RunLoop+EventPump.swift) | The pump eagerly consumes events into uncapped batches, then accumulates all pending batches before dispatch. Charging only queued batches would miss drained-but-undispatched events. |

The wrapper also creates an ordering defect independent of retention. A queued Return or Escape can still be awaiting runtime dispatch when the producer applies a later paste to the composer. Its effect is therefore evaluated against an earlier action phase. Actor isolation serializes these mutations but does not restore input order across the two paths. A deterministic regression must stall consumption, submit key → paste → key, then check effects at dispatch; existing PTY tests cover ordinary interaction rather than this backlog condition.

The public reader seam returns `AsyncStream<InputEvent>`. That type can support pull production with `AsyncStream(unfolding:)`; changing the protocol is not inherently necessary. The concrete reader and eager pump still need coordinated admission. The public custom-host RunLoop seam offers a key handler but no equivalent ordered paste callback. The [paste dispatcher](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Sources/SwiftTUIRuntime/RunLoop/RunLoop+EventDispatch.swift#L329) and focused text-control paste registration are package-owned. The capability-probe read-suspension API is also package-owned and does not reserve downstream dispatch capacity.

Conclusion: neither a bufferingNewest wrapper nor a bounded custom reader establishes the required bound. The former can drop command text or confirmations; the latter merely moves the backlog into the runtime. Fixing this requires a dependency-level input contract, or replacing the runtime's input ownership. The [bounded terminal input proposal](../proposals/bounded-terminal-input.md) recommends the smaller dependency extension, with FIFO paste dispatch and reservations held through handling. It does not authorize a dependency fork or claim a process-wide heap ceiling.

### Upstream 0.16.0 comparison

The [0.16.0 release](https://github.com/SwiftTUI/swift-tui/releases/tag/0.16.0) advertises bounded input ownership. Read-only comparison against the already available local tag object `9ef8feec9fee6fc199767a52aa1c913976bdb2c9` shows that its bounded ingress applies to WebHost, not this native reader path. No checkout, fetch or dependency update was performed. The raw drain and public custom-host initializers are unchanged; native reader production, partial paste storage and the eager event pump remain unbounded. Chunk recovery and recursive-parser fixes do not supply a storage limit.

The new [InputAdmission](https://github.com/SwiftTUI/swift-tui/blob/9ef8feec9fee6fc199767a52aa1c913976bdb2c9/Sources/SwiftTUIRuntime/Input/ScopedInputReading.swift) follows scoped events through their queued/dispatched lifetime, but it and the pulling interfaces are package-only. WebHost uses that machinery; ordinary macOS `InputReader` does not. Public host paste dispatch is still missing. A simple version bump therefore does not close TUI-INPUT-01. Extending the existing reservation mechanism to native/custom-host input is a more focused candidate than introducing another parallel queue model; source review establishes feasibility direction, not an implemented solution.

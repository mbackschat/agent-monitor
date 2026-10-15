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

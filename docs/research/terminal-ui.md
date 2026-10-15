# Terminal UI options

Checked on 2026-10-14. This assessment includes a compiled, isolated SwiftTUI probe; the main monitor now declares the regular upstream package dependency. The requested interface is an opt-in, full-window live report with colors and disclosure, while keeping monitoring logic reusable by a later native GUI. See the [architecture contract](../architecture.md).

## Candidates

| Candidate | Evidence | Assessment for this PoC |
|---|---|---|
| [SwiftTUI/swift-tui](https://github.com/SwiftTUI/swift-tui) | Swift declarative views, state, focus, layout, input, drawing, and terminal ownership; upstream labels it public beta. It also documents a browser companion offered on interactive launches. | The pinned 0.14.0 probe uses the public runtime directly for one terminal screen. Its high-level scene launcher requires discovery IPC; current main-branch browser-companion documentation describes a separate startup concern. |
| [phranck/TUIkit](https://github.com/phranck/TUIkit) | Pure Swift framework with tables, lists, colors, focus, key handling, lifecycle, and terminal control. Upstream explicitly calls it work in progress with changing APIs. | Credible second candidate if the first has unsuitable runtime behavior or compatibility. Its documented components fit the proposed table and disclosure interaction. |
| [rensbreur/SwiftTUI](https://github.com/rensbreur/SwiftTUI) | SwiftUI-like API, scroll views, keyboard focus, controls, and ANSI/true color. This is a different repository from `SwiftTUI/swift-tui`. | Useful reference; validate current Swift 6 compatibility and the required keyboard/resize behavior before adoption. Name similarity is not evidence that these projects share an API. |
| [Tuist Noora](https://noora.tuist.dev/) | Themable Swift CLI components, including [static tables](https://noora.tuist.dev/components/tables/static). | Well aligned with CLI presentation, but the inspected documentation does not establish the complete continuous-screen lifecycle needed here. It is not the first candidate for this particular interaction. |

## Recommendation and acceptance criteria

Evaluate `SwiftTUI/swift-tui` first against the installed Swift toolchain. Selection depends on a small executable proving full-screen redraw, input during sampling, resize handling, stable selected rows, disclosure, clean exit, and acceptable overhead. Keep it behind a presentation boundary; do not change attribution rules to suit a widget library. Current evaluation-package and download status are recorded below.

Reuse the same compact-summary and on-demand-details approach in a later GUI. Share snapshots and identity-based interaction semantics; do not require terminal view types to render in a native window. Avoid adding browser support, animation, charts, or theming controls to the initial TUI PoC.

## Source evaluation and local status

The evaluation package (removed after validation) pins [SwiftTUI 0.14.0](https://github.com/SwiftTUI/swift-tui/tree/0.14.0), revision `581c3ab7e2383ce86fcebe36e81041aecac443a5`. It builds with the installed Swift 6.4 toolchain and imports `SwiftTUIRuntime` and `SwiftTUICLI`, excluding the umbrella’s web host from the compiled product graph. Resolved external dependencies are Argument Parser 1.8.2, Async Algorithms 1.1.4, and Collections 1.7.3. The framework also contains vendored components; these two product names do not imply a small implementation.

The probe shows synthetic data, updates a counter every second, and has a focused disclosure button. It does not inspect processes or implement the monitor’s `--tui` option. Release pinning matters: web results currently show later-version examples, while this evaluation tests only 0.14.0. The tagged text styling API is `.foregroundStyle`, not `.foregroundColor`.

## Sandbox-compatible terminal host

The initial scene-based executable rendered its first frame and then exited with `Failed to bind discovery socket ... Operation not permitted`. The mechanism is in the tagged [TerminalRunner](https://github.com/SwiftTUI/swift-tui/blob/0.14.0/Platforms/CLI/Sources/SwiftTUITerminalCLI/TerminalRunner.swift): its POSIX launch path creates a discovery server for scene attachment even for a single window. Changing to the terminal-only product does not remove that behavior. This failure concerns local IPC, not terminal drawing.

The supported solution is the documented public [RunLoop entry point](https://github.com/SwiftTUI/swift-tui/blob/0.14.0/Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Running-Apps.md). The probe supplies a `TerminalHost`, `InputReader`, `SignalReader`, state container, and focus tracker. SwiftTUI continues to own rendering, raw mode, task reconciliation, and terminal cleanup. The application never starts `TerminalRunner` or its discovery server. No upstream fork, private runtime API, permissions change, browser, or installation is required. Test-only ANSI-screen helpers use the pinned framework’s testing SPI.

Targeted searches for SwiftTUI with Codex CLI and the discovery-socket error found no documented integration recipe for this repository. Results for the similarly named `rensbreur/SwiftTUI` and Codex’s own terminal UI do not establish compatibility here. The recommendation rests on the tagged upstream runtime contract and local PTY observations, not an asserted community workaround.

## Terminal validation

On 2026-10-14, the Swift Testing PTY journey passed against the debug executable: one-second refresh, disclosure while the counter advances, resize from 100×24 to 60×16 with visible geometry confirmation, collapse, Ctrl-C exit code 0, restored cursor/alternate screen, and unchanged terminal flags. The initial scene-launcher executable failed this same startup/refresh guard with the discovery-socket error before the direct-host change.

An independent Python PTY check passed color output, `NO_COLOR`, Ctrl-C, SIGTERM, complete `termios` restoration, cursor visibility, and alternate-screen exit. The test peer must keep draining output while awaiting exit: the tagged POSIX controller restores attributes with `TCSAFLUSH`, which waits for queued output. A harness that stops reading can falsely report a hung child even after cleanup escape sequences were emitted. This reproduced with both Foundation `Process` and native `posix_spawn`; draining the output corrected it.

Early bounded optimized builds expired without diagnostics. A later uninterrupted build completed; see the optimized evaluation below. The debug measurement here is retained only for comparison.

The final debug-only measurement used the standalone Python PTY check with ten seconds of one-Hz synthetic updates per run. The color/Ctrl-C run used 0.656 CPU seconds over 10.320 wall seconds (6.36% of one core); the `NO_COLOR`/SIGTERM run used 0.641 over 10.311 seconds (6.22%). The child-process peak RSS high-water mark was 41.7 MB. CPU includes startup and shutdown; RSS is not physical footprint, and the process-wide children high-water mark is cumulative across the two runs. These are short measurements on the busy development machine, not a sustained-use bound or the combined collector/UI cost.

## Decision and limits

The public runtime host solves the sandbox compatibility problem for a single-screen PoC. Optimized compilation and the short release overhead check passed, supporting adoption for this PoC. Retain the terminal acceptance checks during integration. Keep the exact pin and the UI-independent monitoring boundary. Stable selection, real snapshot delivery, compact scrolling/disclosure, and the option contract are now implemented. Integrated [terminal checks](../development.md#terminal-and-machine-output-checks), [coverage limits](../development.md#validation-coverage) and [retained measurements](README.md#retained-measurements) are documented separately; a synthetic probe alone cannot validate them.

## Completed optimized evaluation and cleanup

A later uninterrupted optimized build succeeded in 482.26 seconds on 2026-10-14. The ten-second color/Ctrl-C run used 0.165 CPU seconds over 10.314 wall seconds (1.60% of one core); the `NO_COLOR`/SIGTERM run used 0.132 over 10.313 seconds (1.28%). Child peak RSS high-water mark was 26.2 MB. Both terminal-cleanup checks passed. This supersedes the earlier bounded-build limitation, though the measurement remains synthetic and short.

The roughly 1 GB `Evaluations/` directory was removed at the user’s request after the build finished. Reusable test sources and the terminal verifier were retained under `Tests/` and `scripts/`; only dependency caches and the measured binary remain under ignored `.build/`. Git was initialized in this work session; the evaluation directory was never committed, and `/Evaluations/` is explicitly ignored. Research findings remain in this document.

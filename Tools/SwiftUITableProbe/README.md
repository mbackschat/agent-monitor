# Standalone SwiftUI table expansion probe

[Probe.swift](Probe.swift) imports only AppKit and SwiftUI. It creates synthetic hierarchical tables in unshown windows, without Agent Monitor models, collectors, providers, third-party dependencies or desktop automation. The dated [research result](../../docs/research/native-menu-design.md#standalone-swiftui-table-expansion--2026-10-27) records the tested platform and interpretation.

Run from the repository root with the installed Xcode toolchain:

```sh
python3 scripts/clean-build.py run -- bash -c 'swiftc -parse-as-library -swift-version 6 -module-cache-path "$AGENT_MONITOR_SCRATCH/cache" Tools/SwiftUITableProbe/Probe.swift -o "$AGENT_MONITOR_SCRATCH/probe" && "$AGENT_MONITOR_SCRATCH/probe"'
```

The wrapper deletes the executable and compiler cache after completion. If running inside an agent sandbox, compilation may need the normal development-tool exception for the Observation macro plugin, and execution needs local AppKit service access. No window is ordered onto the screen.

The matrix covers shared-set and direct per-node `@Bindable` expansion bindings, one or thirty roots, and two or three disclosure levels. Each case starts expanded, collapses, reopens and mounts a fresh table with retained expansion state. All IDs are fixed, and only the last root's branch is expanded. The 420 × 240-point viewport puts the thirty-root case's descendants below the visible area.

The JSON result records row counts after layout and twenty task yields, expected/actual indentation levels, viewport position and the selected leaf identity. Inspection uses public `NSOutlineView` APIs on the backing view; it does not name private SwiftUI classes, inspect private items or force expansion through AppKit. The expected row count and level sequence are independent of the view builder. Selection is cleared before selecting the last leaf, and the binding must report that exact ID. A bounded two-second readiness wait accommodates deferred framework updates; it is a probe timeout, not an application workaround.

Exit status is zero only if every checkpoint agrees with its hierarchy, selection and offscreen oracle. Status one means a mismatch (including a missing backing outline); status two means JSON encoding failed. If a future SDK changes the backing control, a missing outline is a probe incompatibility, not evidence of an expansion defect. The result does not establish physical keyboard/VoiceOver behavior or correctness of the full Agent Monitor table composition.

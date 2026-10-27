# Standalone SwiftUI table expansion probe

[Probe.swift](Probe.swift) imports only AppKit and SwiftUI. It creates synthetic hierarchical tables in unshown windows, without Agent Monitor models, collectors, providers, third-party dependencies or desktop automation. The [initial control result](../../docs/research/native-menu-design.md#standalone-swiftui-table-expansion--2026-10-27) and [following-root triage](../../docs/research/native-menu-design.md#swiftui-following-root-triage--2026-10-27) record the tested platform and interpretation.

## Interactive example

[Demo.swift](Demo.swift) shows the failing and control row orders side by side. It uses synthetic rows only. Build and open it from the repository root:

```sh
bash Tools/SwiftUITableProbe/build-demo.sh
open ".build/SwiftUI Table Demo.app"
```

The left table puts Session B after the expanded Session A branch; the right puts Session B first. Both models initially mark Session A and its executable group expanded. On the recorded toolchain the left shows three rows and the right five. Collapse Session A on the left, then expand it: its process rows appear. **Recreate both tables** (⌘R) restores the initial comparison; closing the window quits the demo. This is the original failure/recovery example, not the hidden-restoration prototype.

The same view has an unshown-window check:

```sh
".build/SwiftUI Table Demo.app/Contents/MacOS/SwiftUITableDemo" --check
```

The expected sorted row counts are `[3, 5]` initially, `[2, 5]` collapsed, `[5, 5]` reopened and `[3, 5]` after recreation. The development-only bundle is ignored and remains local for the user's interaction check; rebuild it with [build-demo.sh](build-demo.sh).

## Automated standalone probe

Run from the repository root with the installed Xcode toolchain:

```sh
python3 scripts/clean-build.py run -- bash -c 'swiftc -parse-as-library -swift-version 6 -module-cache-path "$AGENT_MONITOR_SCRATCH/cache" Tools/SwiftUITableProbe/Probe.swift -o "$AGENT_MONITOR_SCRATCH/probe" && "$AGENT_MONITOR_SCRATCH/probe"'
```

To reproduce the failure, add `--following-root` to the executable invocation:

```sh
python3 scripts/clean-build.py run -- bash -c 'swiftc -parse-as-library -swift-version 6 -module-cache-path "$AGENT_MONITOR_SCRATCH/cache" Tools/SwiftUITableProbe/Probe.swift -o "$AGENT_MONITOR_SCRATCH/probe" && "$AGENT_MONITOR_SCRATCH/probe" --following-root'
```

On the recorded toolchain, the control passes all 32 checkpoints with exit zero. The following-root arm exits one: all 16 initial/remount checkpoints fail, while collapse/reopen passes. This nonzero exit is the reproduced defect, not a build failure.

The wrapper deletes the executable and compiler cache after completion. If running inside an agent sandbox, compilation may need the normal development-tool exception for the Observation macro plugin, and execution needs local AppKit service access. No window is ordered onto the screen.

The matrix covers shared-set and direct per-node `@Bindable` expansion bindings, one or thirty roots, and two or three disclosure levels. Each case starts expanded, collapses, reopens and mounts a fresh table with retained expansion state. All IDs are fixed, and only one root's branch is expanded. The control places it last. `--following-root` appends one collapsed root after it without changing any expansion binding or existing ID. The 420 × 240-point viewport puts the thirty-root case's descendants below the visible area.

The JSON result records row counts after layout and twenty task yields, expected/actual indentation levels, viewport position and the selected leaf identity. Inspection uses public `NSOutlineView` APIs on the backing view; it does not name private SwiftUI classes, inspect private items or force expansion through AppKit. The expected row count and level sequence are independent of the view builder. Selection is cleared before selecting the last leaf, and the binding must report that exact ID. A bounded two-second readiness wait accommodates deferred framework updates; it is a probe timeout, not an application workaround.

Exit status is zero only if every checkpoint agrees with its hierarchy, selection and offscreen oracle. Status one means a mismatch (including a missing backing outline); status two means JSON encoding failed. If a future SDK changes the backing control, a missing outline is a probe incompatibility, not evidence of an expansion defect. The result does not establish physical keyboard/VoiceOver behavior or correctness of the full Agent Monitor table composition.

The opt-in [production-state reconstruction](../../Tests/AgentMonitorMenuBarTests/SwiftUITableIntegrationProbeTests.swift) uses the same synthetic snapshot as the AppKit regression tests. It tests live and constant bindings, records the exact initial mismatch as a Swift Testing known issue, and requires collapse/reopen, refresh and restored selection to work. A different initial mismatch is not accepted as that known issue. It is a reconstruction, not the unavailable original SwiftUI source.

```sh
SWIFTUI_TABLE_TRIAGE=1 swift test --filter swiftUITableProductionOverviewFollowingRootReproduction
```

## Retained-table alternative

The [lifecycle probe](../../Tests/AgentMonitorMenuBarTests/SwiftUITableRetentionProbeTests.swift) starts collapsed, opens a synthetic branch, then keeps the table mounted beneath inspection content. It checks native identity, row depths, selection, disclosure, scroll position and stable pixel bytes after returning. This tests avoiding recreation; it does not use the collapse/reopen repair or change production UI. See the [dated findings and limits](../../docs/research/native-menu-design.md#hidden-swiftui-restoration-prototype--2026-10-27).

```sh
SWIFTUI_TABLE_RETENTION=1 swift test --filter retainedSwiftUITableSurvivesCoveredInspection
```

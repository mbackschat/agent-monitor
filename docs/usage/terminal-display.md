# Terminal display reference

This reference describes layout and rendering behavior. For everyday controls, use [the terminal guide](terminal.md); for metric definitions, use [the overview guide](overview.md).

[Usage guide](../usage.md) · [All usage topics](README.md)

## Summary and resource alignment

The contributor summary uses three lines. When the terminal has room, CPU and Memory headings and totals align above their table columns at the top right, with Recent CPU beneath them; narrower layouts retain the inline totals and table headings.

Its cadence/update/chart-range line uses the same subdued text style as footer hints; process-view cadence follows the same style, while chart bars retain their own colors.

## Hierarchy and identity

Section dividers include their P/S/O shortcut and disclosure state, including when folded.

Session rows have a leading `▸` when collapsed and `▾` when expanded. Connected `├─`/`└─` branches show ownership and continue through wrapped paths; a dot marks a leaf.

Blue names and executables identify contributors, including the explicitly labelled Unresolved / uncertain group; blue bars show CPU history without brackets.

## Resource and selection emphasis

CPU and Memory totals in the summary are both bold; the active sort metric is cyan, matching its column and direction-marked heading. Other resource values stay bold; paths and process counts retain normal contrast.

The selected headline and its CPU/memory cells use reverse video plus the leading `>` marker; charts stay unhighlighted, and color is not required to navigate.

Grouped and flat process tables use the same blue identities and cyan sorted resource values.

## Help and footer layout

| Surface | Layout and emphasis |
| --- | --- |
| Keyboard Help, at least 100 columns | Two columns: left sized to its content, right gets the remainder. Sections stay together; read down the left, then the right. |
| Keyboard Help, narrower | One column; paging uses the rendered row count. |
| Help keys | Cyan, bold and underlined only inside Keyboard Help. |
| Chart legend | One line per symbol; `G` opens the complete explanation. |
| Report/reference footer | Subdued neutral shortcuts, a separator and at most two hint lines: three rows total. Narrow widths prioritize view, Help, pause, quit and warning access; other bindings remain in Help. |
| Reference titles | Blue and bold, with normal-contrast explanations. |

## Details and narrow layouts

Both Details panes use blue field labels, readable neutral values and targeted resource/uncertainty accents.

Supporting status uses secondary emphasis, while uncertainty is marked beside the affected value.

Section rules and spacing between contributors separate groups; CPU and memory stay aligned at every depth.

At 100 columns or wider, workload context wraps within the contributor column; below 100 it can use the full row width.

Compact-height terminals omit extra spacer lines.

## Filled chart geometry

| Mode | Geometry | Placement |
| --- | --- | --- |
| Stacked | Three rows, eighth-cell steps: 24 heights. Full cells below the cap use solid backgrounds; the fractional top block is not rounded to a whole row. | Beside contributor identity, process count and workload context. When summary text fits, the overall chart spans all three summary rows from the screen's top, aligned with contributor charts. |
| Compact | One glyph row, eight heights; the same CPU range and numeric values. The summary labels it `compact`. | Overall chart on the final summary row; contributor charts beside their headlines. |

Exact percentages remain in numeric columns; color and monochrome use the same chart heights. Narrow layouts put workload context below the plot and omit the overall chart before clipping summary information.

| Symbol or appearance | Meaning |
| --- | --- |
| Warning-colored bar, usually amber/yellow | Above the selected range. |
| **↑** in monochrome | Above range, distinct from an exactly full bar. |
| **·** | No measurement. |
| **_** | Measured zero. |
| **~ spans** | Measurements cross sampling gaps. |
| **b** | Change the common chart range. |

Read oldest on the left and newest on the right. Equal-width bars represent retained interval averages and can cover unequal durations.

A three-line legend appears at the bottom right only when contributor charts are visible and every shortcut line leaves enough room. It adds no footer rows and hides as a unit when space is insufficient. Keyboard Help and the glossary also explain its symbols.

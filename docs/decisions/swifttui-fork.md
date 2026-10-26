# SwiftTUI fork

Status: **rejected**, 2026-10-26. The user explicitly declined maintaining a SwiftTUI fork.

## Decision

Keep SwiftTUI as an official upstream dependency. Do not introduce a fork, vendored modifications or checkout patches to implement the [bounded terminal-input proposal](../proposals/bounded-terminal-input.md).

The user rejected the fork after its purpose and maintenance implications were explained; no further rationale was supplied. This does not waive input ordering, memory or other product acceptance requirements. The [source findings](../research/terminal-ui.md#ordered-input-and-retention-boundary--2026-10-26) remain open defects/limits, and the proposal is on hold for an upstream solution.

An official upstream fix or a verified solution using supported public APIs may be evaluated without reopening the fork decision. Reconsider maintaining a fork only on explicit user instruction. Replacing the terminal framework is not implied by this decision.

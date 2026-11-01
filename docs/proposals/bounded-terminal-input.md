# Bounded, ordered terminal input

Status: **on hold**, 2026-10-26. Waiting for an upstream solution or a verified public-API alternative; the user rejected a SwiftTUI fork.

## Purpose and scope

Keep TUI input memory bounded during a slow renderer without losing accepted command order or treating paste as commands. The [source audit](../research/terminal-ui.md#ordered-input-and-retention-boundary--2026-10-26) establishes that the pinned reader, partial decoder and event pump can each accumulate input; the current host discards paste only after that upstream storage. Removing the composer eliminates its producer-side state mutation, but cannot bound the reader or runtime.

Required: a focused extension of SwiftTUI's existing input reader and custom-host runtime. Agent Monitor keeps the current renderer, state model, keyboard controls and explicit action confirmations. Mac input and resource accounting are unchanged.

## Required contract

### Ordering and admission

Accepted keys remain typed and are consumed in FIFO order. Agent Monitor discards paste; pasted Return, Escape, Ctrl-Y and other command-looking content must never become confirmation, focus or process actions. Paste rejection must preserve the order of surrounding accepted keys.

A shared reservation covers each accepted event until handling completes, including reader delivery, queued events and drained-but-undispatched batches. Admission suspends before exhausting either event count or payload bytes; it never drops an accepted key or confirmation. Pulling from the reader stops when there is no capacity. No side queue or unstructured task may retain uncharged events.

A stalled consumer therefore stops upstream advancement after the declared in-flight allowance; dequeuing alone does not release its reservation.

The proposed host configuration uses positive, typed limits:

```swift
struct TerminalInputLimits: Sendable {
    let maximumPendingEvents: Int       // 256, including dispatch in flight
    let maximumPendingPayloadBytes: Int // 256 * 1024, decoded UTF-8 payload
    let maximumReadBytes: Int           // 8 * 1024 per native read turn
    let maximumPartialSequenceBytes: Int // 4 * 1024, excluding paste content
    let maximumPasteBytes: Int          // 64 * 1024, UTF-8 payload before sanitization
}
```

These are proposed logical admission limits, not measured allocator sizes. Reader scratch and incomplete decoding have separate bounded storage; the public contract states their maximum in-flight counts.

Native read turns yield at their byte allowance rather than draining indefinitely. The parser cannot emit an arbitrarily large local event array before admission. The existing AsyncStream-based reader interface may remain if its production honors these requirements.

### Paste and malformed input

An oversized paste is discarded as a whole with one ordered, visible notice. After the limit, the parser retains only bounded framing state and discards through the paste end marker. It must not reinterpret discarded bytes as commands, even when markers span reads. EOF with an incomplete paste rejects it. Oversized control sequences likewise cannot escape into command input.

An unterminated rejected paste remains in discard mode until its terminator, input termination or cancellation; cancellation must not wait for more input.

### Cancellation and guarantee boundary

Cancellation wakes suspended admission and native reads, deregisters read sources before terminal restoration, and prevents late dispatch into a replacement input session. Runtime shutdown must remain possible while the consumer is stalled; it must not depend on making queue space or receiving a paste terminator. The host's existing termination path remains independent of input admission.

The guarantee begins with bytes admitted by the reader. It does not claim that the operating system or terminal emulator preserves unlimited input while backpressured. It bounds this input path's retained state, not all SwiftUI/AppKit/SwiftTUI allocations or the process's RSS.

## Optional and excluded

Optional: scalar diagnostics for current/peak reservations, rejected paste count and producer suspension count. No pasted text or key history is recorded.

Excluded: dropping old/new keyboard events to achieve a cap; manufacturing key events to carry paste; replacing the TUI renderer; new input recording; private runtime hooks; dependency changes unrelated to ordered input, bounded storage and cancellation. Paste editing and message composition are excluded; the monitor has no text-input consumer.

## Decision and feasibility

Recommend extending SwiftTUI's existing admission machinery to native/custom-host input rather than replacing its runtime in Agent Monitor. The [0.16.0 comparison](../research/terminal-ui.md#upstream-0160-comparison) and [0.19.1 follow-up](../research/terminal-ui.md#upstream-0191-comparison--2026-10-29) confirm that admission/pulling interfaces remain package-only and the native reader, parser and dispatch buffers remain unbounded; upgrading alone is insufficient. It preserves the established terminal behavior and fixes every retaining stage under one owner.

The user [rejected a SwiftTUI fork](../decisions/swifttui-fork.md). Integration waits for an official upstream fix or a verified solution using supported public APIs. No change to the current dependency pin is implied.

The numeric limits and whole-paste rejection are proposed host policy. The dependency must expose a deterministic dispatch-stall seam and reservation diagnostics so tests can establish backpressure, FIFO effects and cancellation without native load generation. Those guards must observe upstream advancement, not merely the size of Agent Monitor's wrapper. A logical input bound does not close CPU-01's whole-process memory, native cost or short-worker coverage gates.

Deferred GitHub issue preparation is captured in the [dedicated upstream follow-up](../swifttui-upstream-follow-up.md), including the proposed split, evidence requirements and changes to request. No issue publication or dependency change is authorized by that follow-up.

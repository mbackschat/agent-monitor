# Menu bar front end: retained direction

Status: superseded by the maintained, source-built menu bar app authorized on 2026-10-15. The implemented contract is in [architecture](../architecture.md#native-menu-bar-app); this note retains deferred product decisions. Platform evidence and unanswered feasibility questions belong in [menu bar research](../research/menubar-app.md); current product scope is in [PLAN.md](../../PLAN.md#scope-and-pending-decisions).

## Confirmed constraint

On 2026-10-15 the user decided that a future menu bar app must do nothing while its popover is closed, prioritizing battery use. Closing cancels sampling, schedules no timer and leaves no observer that wakes the process. The status item is a static icon; there is no live closed-state count or threshold notification. Owned provider subprocesses must finish or be cancelled and reaped.

While open, the proposed cadence uses the existing one-second default. Reopening takes a fresh sampling baseline, with CPU available after the first interval. The decision accepts losing observed ancestry history between openings; explicit markers and runtime descriptors can still be inspected afresh. A ten-minute closed-state CPU/wakeup observation would test this constraint; it has not been performed.

## Decisions still needed

- Further UI capabilities: AppKit `NSStatusItem`/`NSPopover` with native SwiftUI content, shared grouping and reviewed actions is implemented. Broader TUI control parity and launch at login are not included.
- Distribution: signing identity, formula versus cask, installation location and whether the app also distributes the CLI. No signing or Gatekeeper behavior has been established by a GUI install test.
- Concurrent use: independent app/TUI collectors or a separate sharing mechanism. No IPC service is authorized by this proposal.

Any extension must preserve the [monitoring and action boundaries](../architecture.md). Target names, file changes and effort estimates are implementation planning, not established requirements.

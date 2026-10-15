# Menu bar front end: retained direction

Status: superseded by the maintained, source-built menu bar app authorized on 2026-10-15. The implemented contract is in [architecture](../architecture.md#native-menu-bar-app); this note retains deferred product decisions. Platform evidence and unanswered feasibility questions belong in [menu bar research](../research/menubar-app.md); current product scope is in [PLAN.md](../../PLAN.md#scope-and-pending-decisions).

## Earlier constraint (superseded)

The initial 2026-10-15 direction required no work while closed, prioritizing battery use. Later that day the user explicitly authorized a live load icon with a 15-second closed cadence; the original no-sampling behavior is now an optional static mode. The remaining paragraph records the earlier constraint, not current live-mode behavior. Closing cancels sampling, schedules no timer and leaves no observer that wakes the process. The status item is a static icon; there is no live closed-state count or threshold notification. Owned provider subprocesses must finish or be cancelled and reaped.

While open, the proposed cadence uses the existing one-second default. Reopening takes a fresh sampling baseline, with CPU available after the first interval. The decision accepts losing observed ancestry history between openings; explicit markers and runtime descriptors can still be inspected afresh. A ten-minute closed-state CPU/wakeup observation would test this constraint; it has not been performed.

## Decisions still needed

- Launch at login remains deferred. Implemented native controls and their relationship to the TUI are described in [architecture](../architecture.md#native-menu-bar-app).
- Distribution: signing identity, formula versus cask, installation location and whether the app also distributes the CLI. No signing or Gatekeeper behavior has been established by a GUI install test.
- A shared collector or IPC service remains deferred; the implemented app and TUI use independent collectors.

Any extension must preserve the [monitoring and action boundaries](../architecture.md). Target names, file changes and effort estimates are implementation planning, not established requirements.

# Menu bar app: login item, distribution and shared collector

Status: **deferred**, 2026-10-15. The maintained, source-built menu bar app is specified in [architecture](../architecture.md#native-menu-bar-app); platform evidence and open feasibility questions are in [menu bar research](../research/menubar-app.md).

## Decision

Keep these product questions out of the maintained app:

- Launch at login.
- Distribution: signing identity, formula versus cask, installation location and whether the app also distributes the CLI.
- A shared collector or IPC service; the app and the TUI keep independent collectors.

## Reason

No signing or Gatekeeper behavior has been established by a GUI install test, and production distribution, login items and background services are outside the current [scope](../../PLAN.md#scope-and-pending-decisions).

## Reconsider when

The user schedules distribution or background operation. Any extension must preserve the [monitoring and action boundaries](../architecture.md).

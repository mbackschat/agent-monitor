# Menu bar app: login item, distribution and shared collector

Status: **deferred**, 2026-10-15. The maintained, source-built menu bar app is specified in [architecture](../architecture.md#native-menu-bar-app); platform evidence and open feasibility questions are in [menu bar research](../research/menubar-app.md).

## Decision

Keep these product questions out of the maintained app:

- Launch at login.
- A Homebrew cask, installer, automatic updater or an app-bundled CLI.
- A shared collector or IPC service; the app and the TUI keep independent collectors.

## Reason

The user authorized direct Mac app distribution on 2026-11-01: a Developer ID-signed and notarized app ZIP on GitHub, separate from the CLI formula. The [release workflow](../macos-release.md) owns signing, Gatekeeper checks and installation validation. Login items, additional packaging and background services remain outside that scope.

## Reconsider when

The user schedules distribution or background operation. Any extension must preserve the [monitoring and action boundaries](../architecture.md).

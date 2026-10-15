# Menu bar app as an alternative front end

Checked 2026-10-15 on macOS 27.0.1 (build 26A434), Xcode 27.0 (27A266a), Swift 6.4, against source at commit `edd163b`. Question: how feasible is a macOS menu bar app as an alternative front end to the terminal UI, and what would it change in this repository, its permissions model and its distribution? Feasibility only; nothing was implemented, built or launched. Every claim cites a URL or a local command and is tagged **Doc** (Apple, Homebrew or upstream documentation), **Local** (observed on this machine or in this repository), or **Inference** (reasoned, not verified).

Local checks were read-only: reading repository sources and docs, `sw_vers`, `xcodebuild -version`, `swift --version`, SDK reads (SwiftUI `.swiftinterface`, `SMAppService.h`, `NSRunningApplication.h`, `paths.h`), `security find-identity -v -p codesigning`, `command -v`, `launchctl getenv PATH`, `man launchd.plist`, and the generated SwiftPM resource accessor under `.build/`. Apple documentation pages were read through their JSON data endpoint because the HTML pages need JavaScript. No GUI binary was run, nothing was put in the menu bar, and no permission or setting was changed.

## Verdict

**Feasible; prototype first, then decide on Developer ID before promising distribution.** The architecture already anticipates this consumer: `MonitoringSession`, `LiveReportState`, `SessionGrouping`, `ActionPanel`'s state machine, `SessionActions` and `TerminalFocus` can drive a SwiftUI `MenuBarExtra` with little or no change, and the app must run outside the App Sandbox, which rules out the Mac App Store but matches the CLI's current same-user model. The real costs sit outside the view code: (1) provider messaging resolves `claude`/`codex` through the inherited `PATH`, which a Finder- or login-launched app does not have; (2) only a Developer ID-signed, notarized app gives a stable code identity for the Automation grant and passes Gatekeeper for a downloaded app, which needs the paid Apple Developer Program; (3) a long-lived agent needs a different sampling cadence than the TUI, and the current live-interval wait wakes four times per second regardless of the interval. A minimal read-only menu bar view is **S–M**; feature parity with actions, composer, focus, notifications, login item and a notarized cask is **L**.

## Local observations

- **Local** Toolchain: macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), target `arm64-apple-macosx27.0.0`.
- **Local** Signing identities: one valid identity, of type "Apple Development". No "Developer ID Application" identity is installed, so notarized distribution is not possible from this machine today (`security find-identity -v -p codesigning`).
- **Local** The macOS 27 SDK's SwiftUI interface declares `MenuBarExtra` (macOS 13+) with initializers taking an optional `isInserted: Binding<Bool>`, and the styles `.automatic`, `.menu` (`PullDownMenuBarExtraStyle`) and `.window` (`WindowMenuBarExtraStyle`). It declares no binding or action for the extra's presentation state (open/closed), and no access to its status item or window (`grep MenuBarExtra` in `SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`).
- **Local** `SMAppService.h`: registering `mainApp` launches the app "on subsequent logins"; status `requiresApproval` means "the user needs to take action in System Settings"; registration fails with `kSMErrorInvalidSignature` "if the app bundle is not properly code signed".
- **Local** `NSRunningApplication.h`: it "is thread safe, in that its properties are returned atomically", but time-varying properties "persist until the next turn of the main run loop".
- **Local** Provider CLIs are not on the standard path: `claude` resolves to `~/.local/bin/claude` and `codex` to `/opt/homebrew/bin/codex` in this shell, `launchctl getenv PATH` is empty (no PATH set for the GUI launchd domain), and `_PATH_STDPATH` is `/usr/bin:/bin:/usr/sbin:/sbin` (`paths.h`; `launchd.plist(5)` resolves relative programs with it). Both messaging adapters start `/usr/bin/env claude` / `/usr/bin/env codex` ([ClaudeMessaging.swift](../../Sources/AgentMonitorActions/ClaudeMessaging.swift), [CodexMessaging.swift](../../Sources/AgentMonitorActions/CodexMessaging.swift)).
- **Local** The SwiftPM-generated `Bundle.module` accessor for `AgentMonitorPresentation` searches `Bundle.main.resourceURL` first ("Bundle should be present here when the package is linked into an App"), then the framework, then `Bundle.main.bundleURL` (command-line tools). Copying `AgentMonitor_AgentMonitorPresentation.bundle` into `Contents/Resources` therefore satisfies the schema lookup inside an app (`.build/out/.../AgentMonitorPresentation-t.build/DerivedSources/resource_bundle_accessor.swift`). Only `JSONReport` uses it, and a menu bar app need not touch the schema.
- **Local** `Package.swift` exports only the `AgentMonitorCore` library and the `agent-monitor` executable as products. An app target in a separate Xcode project could not depend on `AgentMonitorPresentation` or `AgentMonitorActions` without new library products; a new target inside the package can.
- **Local** Sampling cost already measured: the headless ten-minute watch at one-second intervals averaged 0.805% of one core with 8.37 MB peak physical footprint ([PoC validation](../poc-validation.md#sustained-optimized-watch-2026-10-14)); short TUI runs measured roughly 1.9–4.2% of one core including startup and rendering ([PoC validation](../poc-validation.md)).
- **Local** CPU is computed as CPU-time delta divided by the measured `mach_absolute_time` delta between samples (`Monitor.swift` line 25, `NativeProcessReader.swift`), so a delayed or throttled wake changes the averaging window, not the correctness of the percentage.
- **Local** `MonitoringSession.wait` with a live interval supplier sleeps in slices of at most 0.25 s and re-reads the supplier each slice ([MonitoringSession.swift](../../Sources/AgentMonitorCore/MonitoringSession.swift)); `ContinuousSamplingClock` uses `Task.sleep(for:)` without tolerance.

## 1. Technical approach

### Status item technology

| Option | What it gives | Limits | Evidence |
|---|---|---|---|
| SwiftUI `MenuBarExtra`, `.window` style | "A popover-like window" with standard controls; suits "more complex or data rich" content: lists, disclosure, text fields, buttons | No first-party API to open, close or observe the popover, or reach its window/status item; third-party packages patch this through AppKit internals | **Doc** [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra), [WindowMenuBarExtraStyle](https://developer.apple.com/documentation/swiftui/windowmenubarextrastyle); **Local** SDK interface above; [MenuBarExtraAccess README](https://github.com/orchetect/MenuBarExtraAccess) (third party, states the missing first-party API) |
| SwiftUI `MenuBarExtra`, `.menu` style | A native pull-down menu built from `Button`, `Toggle`, `Picker` | Menu items cannot host an editable composer or a scrolling details pane; live refresh of an open menu is untested | **Doc** [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra); refresh behavior is **Inference** |
| AppKit `NSStatusItem` + `NSPopover` hosting SwiftUI | Full control: programmatic show/hide, right-click menu, popover behavior, status-button title updates | More AppKit glue; still SwiftUI inside | **Doc** [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem): created by `NSStatusBar.statusItem(withLength:)`, customized through `button` |

**Recommendation (Inference):** start with `MenuBarExtra(.window)`; it covers a list with disclosure, a details section and buttons with the least code. Switch to `NSStatusItem` + `NSPopover` only if the prototype shows that programmatic dismissal (for example after focusing a terminal) or composer text-field focus does not work acceptably; developer-forum reports describe focus and menu-bar auto-hide quirks with the window style ([text field focus](https://developer.apple.com/forums/thread/729920), [auto-hide](https://developer.apple.com/forums/thread/761204)), unverified here.

### Agent-app behavior

- **Doc** A menu-bar-only app "will be automatically terminated if the user removes the extra from the menu bar"; to hide it from the Dock and app switcher, set `LSUIElement` to true ([MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)). `NSApplication.ActivationPolicy.accessory` "corresponds to" `LSUIElement` = 1: no Dock icon or menu bar, but it "may be activated programmatically or by clicking on one of its windows" ([accessory](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory)).
- **Inference** Setting `.accessory` programmatically lets an unbundled `swift run` prototype behave like an agent app before any bundle exists; the shipped app should use `LSUIElement` so no Dock icon flashes at launch.
- **Doc** macOS 26 and later list third-party items under System Settings › Menu Bar › "Allow in the Menu Bar", each "Select to show in the menu bar" ([Apple Mac Help, macOS 26](https://support.apple.com/en-gb/guide/mac-help/mchlad96d366/26/mac/27)). Whether hiding the item there counts as removal (and so terminates a menu-bar-only app) is unverified.

### Sampling in a long-lived agent

The TUI is a foreground tool that runs while the user watches; a menu bar app runs all day. Three cadences are needed (**Inference**):

| State | Proposed interval | Why |
|---|---|---|
| Popover open | 1 s (TUI default) | Matches what users know from the TUI |
| Popover closed, status label or notifications enabled | 5–10 s | The label and threshold notifications need data; 0.805% of one core at 1 s suggests roughly a tenth of that at 10 s, unmeasured |
| Popover closed, label shows no live data and notifications off | Paused (cancel the session task) | No consumer, so no sampling; a fresh baseline is taken on reopen, at the cost of one interval before the first CPU value |

- **Local/Inference** `MonitoringSession` already supports live interval changes, so switching between 1 s and 10 s on open/close needs no core change. Pausing means cancelling the `run` task; process history is then lost, so detached-child attribution that relies on observed ancestry weakens after a pause. Prefer a slow interval over a pause when attribution quality matters.
- **Local/Inference** The quarter-second re-read in `MonitoringSession.wait` costs four wakeups per second even at a 60 s interval. That is harmless for a foreground TUI but is the wrong shape for an always-on agent; Apple's guidance is to respond to events rather than poll and to give timers at least 10% tolerance ([Energy Efficiency Guide: timers](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html)). A change notification (for example an `AsyncStream` of interval updates) plus a tolerance on the sleep ([`Task.sleep(for:tolerance:clock:)`](https://developer.apple.com/documentation/swift/task/sleep(for:tolerance:clock:)), macOS 13+) would fix it at the root in the core, for every host.
- **Doc** App Nap may throttle a non-foreground app's timers when it has not "recently updated content in the visible portion of a window" and holds no `NSProcessInfo` assertion; Apple warns not to rely on App Nap to idle ([App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html)). **Inference** Throttling only widens the averaging window (see the CPU observation above); it does not corrupt values. Do not take a `beginActivity` assertion for background sampling.
- **Inference** A longer interval turns the threshold into a longer average: at 10 s, a 3-second spike to 100% reads as about 30%. This touches the open "sustained versus instantaneous threshold" decision in [PRODUCT.md](PRODUCT.md#decisions-still-open) and must be stated in the UI.

### Login item and notifications (optional)

- **Doc** `SMAppService.mainApp` configures "the main app to launch at login" (macOS 13+) ([SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)); **Local** the header requires a properly code-signed bundle and reports `requiresApproval` when the user must approve in System Settings. Offer it as an explicit opt-in toggle, never on first launch (also required for the Mac App Store by [guideline 2.4.5(iii)](https://developer.apple.com/app-store/review/guidelines/#2.4.5), and good practice regardless).
- **Doc** `UNUserNotificationCenter` manages notifications "for your app or app extension" ([UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)); a developer-forum report shows it throwing `bundleProxyForCurrentProcess is nil` in a command-line tool without a bundle ([forum 724249](https://developer.apple.com/forums/thread/724249)). Notifications therefore require the app bundle, and are not a reason to add them to the CLI.
- **Inference** Notifications need a debounce rule (for example "above threshold for N consecutive samples", once per process lifetime) or they will fire on every short spike. Notifications are explicitly "not established requirements" in [PRODUCT.md](PRODUCT.md#decisions-still-open); treat them as a separate scope decision.

### What the menu would show (proposal, Inference)

- **Status item label:** an SF Symbol plus the number of heavy processes (or launch groups), tinted when any exceed a threshold. No numbers beyond a short count: menu bar space is scarce and a changing width shifts neighbors.
- **Popover header:** thresholds (CPU % OR GB) and interval with the same "(pending)" semantics as the TUI, a freeze toggle, and the update time.
- **Body:** session groups by default (`--group session` semantics): provider, project, abbreviated session ID, heavy-process count, CPU/GB heavy-process totals with the partial marker; expanding a group lists its processes. Unknown and ambiguous attribution stays visible and labeled, never merged.
- **Details:** for the selected process, the same facts the TUI details pane shows (full session ID, executable, project directory, runtime, terminal, evidence, shared-daemon qualification), with copy buttons.
- **Actions per row:** Focus terminal; Message…; Terminate… Each opens an explicit review/confirm step mirroring `ActionPanel` phases; results distinguish accepted from delivered.
- **Footer:** Settings (thresholds, background interval, notifications, launch at login), Quit.

## 2. Reuse and architecture fit

| Component | Reuse | Notes |
|---|---|---|
| `MonitoringSession` (`@concurrent run`, live thresholds/interval suppliers, snapshot backpressure) | Unchanged | Same call the TUI makes; the receive closure hops to the main actor. Exclude the app's own PID. Energy fix above is optional but recommended |
| `MonitoringSnapshot`, `HeavyProcess`, attribution models | Unchanged | Already `Sendable`, UI-free |
| `SessionGrouping`, `SessionGroup`, `LiveReportRow` | Unchanged | Typed rows and totals are what SwiftUI lists need |
| `LiveReportState` | Mostly unchanged | Sorting, grouping, freeze, selection identity, pruning on refresh all apply. Missing for pointer UIs: `select(_ id: LiveReportRowID)` (only `moveSelection(by:)` exists), direct `setThresholds`/`setInterval` (only ±10 %/±1 GB steps and a 0.5–60 s step list), and a group-toggle that does not also drive the TUI details pane. TUI-only fields (`detailsMode`, `detailsPercent`, `detailOffset`) are harmless noise |
| `ActionPanel`, `ActionEffect`, `ActionResult`, `MessageWording`, `FocusWording` | Phases and effects reusable | Input is keystroke-shaped (`.text` appends, `.backspace`, `.confirm` = Ctrl-Y); a SwiftUI `TextField` needs a whole-text setter that keeps the existing control-character filter and 4,000-character cap. `lines(width:height:)` is terminal rendering and internal |
| `SessionActions`, `ProcessActions`, `AgentMessaging` | Unchanged API | `@concurrent` methods are callable from a `@MainActor` model; the TUI's `TerminalOutcome.perform` pattern (one cancellable action task, result mutation on the main actor) ports directly |
| `TerminalFocus`, `TerminalAppFocus`, `NativeActions` | Unchanged mechanism | Same router and adapter; permission attribution changes (section 3). `NSRunningApplication` properties refresh with the main run loop, which an app runs (**Local** header note) |
| `LiveReportLayout`, `ReportLine`, `ReportTable`, `ANSIText`, `TextReport` | Not usable for the GUI | They produce fixed-width padded lines, column caps, ellipses, key hints and pane geometry for a character grid. A GUI needs typed values, not pre-laid-out strings |
| Details content (`LiveReportLayout.detailLines`) | Must be extracted | It is `private` and returns width-wrapped strings. Extract a neutral details model (ordered label/value facts plus evidence entries) in `AgentMonitorPresentation`; the TUI formats it into lines, the GUI into a form. The README preview check then guards that the TUI text did not change |

**SwiftUI view model (Inference).** One `@MainActor @Observable final class MenuBarModel` owning a `LiveReportState` value, the sampling `Task`, the current action `Task`, and the cadence state (popover open/closed). It starts `session.run(thresholds: { await model.state.thresholds }, interval: { await model.interval }) { snapshot in await model.receive(snapshot) }` exactly like `TerminalReportView.task`. Views read the model and send intents; they never call `MonitoringSession` or actions directly. Keep the model in a separate library target without `import SwiftUI` so it can be unit-tested with fake `ProcessReading` and fake `ProcessActions`, the way `TUIFixture` drives the TUI today.

**Isolation (Inference).** SwiftUI views and the model are main-actor isolated; `MonitoringSession.run` and `SessionActions` are `@concurrent`, so native inspection, provider subprocesses and `osascript` stay off the main actor. Snapshots and action values are `Sendable`, so no new `@unchecked Sendable` is needed. On quit (`NSApplication` termination or `MenuBarExtra` removal), cancel and await the action task so owned provider subprocesses are reaped, as [CLAUDE.md](../../CLAUDE.md) requires.

## 3. Permissions and security

| Topic | Finding | Evidence |
|---|---|---|
| Process inspection without sandbox | Unchanged from the CLI: same user, same `proc_pidinfo`, `proc_pid_rusage`, `KERN_PROCARGS2`, `proc_pidfdinfo` calls, no TCC prompt involved. The Hardened Runtime restricts task-port access ("Debugging Tool" exception), which the monitor does not use | **Local** no `task_for_pid` in `Sources/`; **Doc** [Configuring the hardened runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime) runtime-exception table; same-user behavior is **Inference** from the CLI running unsandboxed today |
| App Sandbox | Ruled out. `<libproc.h>` APIs "are also blocked by the App Sandbox, failing with EPERM", and no entitlement lifts the restriction | **Doc** Apple DTS: [forum 776473](https://developer.apple.com/forums/thread/776473) (2025), [forum 691857](https://developer.apple.com/forums/thread/691857) ("No.") |
| Mac App Store | Ruled out: Mac App Store apps "must be appropriately sandboxed" | **Doc** [App Review Guidelines 2.4.5(i)](https://developer.apple.com/app-store/review/guidelines/#2.4.5), [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox) |
| Environment hiding on macOS 27 | Unchanged: Apple platform binaries' environments are not readable through `KERN_PROCARGS2`; this is kernel policy, not host-dependent | **Local** [Claude session messaging](claude-session-messaging.md#live-transport-check-2026-10-14); host independence is **Inference** |
| Automation (Apple Events) attribution | When an app spawns a helper, "the system treats the app as the responsible code"; from Terminal, the responsible code is Terminal. The consent prompt therefore names Agent Monitor instead of the hosting terminal, and the grant no longer covers every program run in that terminal | **Doc** [Apple DTS, forum 756510](https://developer.apple.com/forums/thread/756510) ("not documented, has changed in the past"); consequence is **Inference** |
| Usage string | `NSAppleEventsUsageDescription` "is required if your app uses APIs that send Apple events" | **Doc** [NSAppleEventsUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription) |
| Hardened runtime entitlement | `com.apple.security.automation.apple-events` indicates "whether the app may prompt the user for permission to send Apple events"; enabled under Hardened Runtime › Resource Access | **Doc** [Apple Events entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events), [Configuring the hardened runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime) |
| `osascript` child of a hardened app | tccd appears to check the responsible app's entitlement, so the app needs the entitlement even though `osascript` sends the events | **Inference**; supported only by third-party reports ([Spotify community](https://community.spotify.com/t5/Desktop-Mac/Studio-agent-generates-AppleScript-calendar-workflows-the-app/td-p/7508458), low confidence). Must be confirmed in the prototype |
| Grant persistence across updates | macOS records an app's designated requirement for privacy grants; ad hoc signed code "has a DR but it's tied to that specific version of the code", so each ad-hoc update loses the Automation grant | **Doc** [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) |
| Cooperative activation | An app can `yieldActivation(to:)`; "the other app must request activation in the future". An active accessory app (popover open after a click) can yield to the terminal before it activates, which a CLI cannot | **Doc** [yieldActivation(to:)](https://developer.apple.com/documentation/appkit/nsapplication/yieldactivation(to:)); applicability is **Inference**, part of the open gate in [terminal focus](terminal-focus.md#recommended-minimal-design) |
| Provider CLI discovery | `/usr/bin/env claude`/`codex` searches the inherited `PATH`; a Finder- or login-launched app gets the standard path, which excludes `~/.local/bin` and `/opt/homebrew/bin` where the CLIs live here. Messaging would fail with "Cannot start … Ensure its CLI is on PATH." | **Local** observations above; launch-environment PATH is **Inference** |

**Security posture (Inference).** Moving Automation consent from the terminal to a dedicated, Developer ID-signed app narrows the grant: today the consent lets anything run in that terminal script Terminal ([terminal focus](terminal-focus.md#3-macos-permission-and-activation-model)). The adapter allowlist (select, unminimize, order, activate; never type or read contents) stays the guard. Resolving provider CLIs must not reintroduce a `PATH`-hijack risk: resolve once to an absolute path (user-configured, or the login shell's `command -v`), verify it is a regular file owned by the user or root and not world-writable, and show the resolved path in Settings.

## 4. Packaging and distribution

### Building the bundle

| Approach | Pros | Cons |
|---|---|---|
| Scripted assembly from a SwiftPM `executableTarget` (recommended) | Keeps one build system; `swift build`, `swift test`, `swift format` and CI stay as they are; mirrors the existing `package-release.py` | Hand-written `Info.plist`, entitlements, bundle layout, `codesign --options runtime --timestamp --entitlements`, `notarytool`, `stapler`; no Xcode Organizer |
| Xcode project with an app target depending on the local package | Standard archive → Developer ID → notarize workflow in Organizer; asset catalogs | Second build system to keep in sync; needs new library products in `Package.swift`; Xcode project files in review diffs; CI must run `xcodebuild` |
| Third-party bundler (for example swift-bundler) | Automates bundling and signing | New dependency on the release path, against the project's minimal-dependency stance |

- **Doc** SwiftPM has no app-bundle product; community practice is to build the executable and assemble `MyApp.app/Contents/{MacOS,Resources,Info.plist}` by script ([Swift Forums](https://forums.swift.org/t/building-an-app-from-a-swift-package-manager-executable-for-macos/64409)).
- **Inference** Bundle contents: `Contents/MacOS/Agent Monitor` (stripped, like the CLI), `Contents/Info.plist` (`CFBundleIdentifier`, `CFBundleShortVersionString` from `AgentMonitorVersion.current`, `LSMinimumSystemVersion` 27.0, `LSUIElement` true, `NSAppleEventsUsageDescription`), `Contents/Resources/` (icon, the presentation resource bundle if the schema is ever needed, licenses). Swift packages link statically into the executable, so library validation under the hardened runtime has nothing extra to load.

### Signing, notarization, Gatekeeper

- **Doc** Developer ID-distributed software "must be notarized" (since macOS 10.15); notarization requires a Developer ID certificate ("Don't use a Mac Distribution, ad hoc, Apple Developer, or local development certificate"), the Hardened Runtime, a secure timestamp, and no `get-task-allow`; `notarytool` and `stapler` integrate into scripts ([Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)).
- **Doc** Since macOS Sequoia, "users will no longer be able to Control-click to override Gatekeeper"; they must allow software in System Settings › Privacy & Security ([Apple developer news, 2024-08-06](https://developer.apple.com/news/?id=saqachfa)).
- **Doc** The Apple Developer Program costs $99 per year and covers distributing "outside the Mac App Store using your Developer ID certificate and Apple's notarization process" ([Apple Developer Program](https://developer.apple.com/programs/)).
- **Local/Inference** The installed "Apple Development" identity gives a stable designated requirement for local development builds (so the Automation grant survives rebuilds), but cannot be notarized. An ad-hoc signed downloaded app would be blocked by Gatekeeper until the user allows it in System Settings, and would lose its Automation grant on every update (TN3127 above).

### Homebrew cask versus the formula

- **Doc** A cask's `app` stanza moves the bundle to `/Applications`; `binary` can link an executable "contained in an application bundle"; `depends_on macos:` and `arch:` express requirements; `uninstall quit:` and `login_item:` clean up; `zap` removes support files on request ([Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)).
- **Doc** Homebrew 5.0.0 deprecated `--no-quarantine`/`--quarantine` because Homebrew "does not wish to easily provide circumvention to macOS security features", deprecated casks without codesigning, and announced disabling `Homebrew/homebrew-cask` casks that fail Gatekeeper checks in September 2026 ([Homebrew 5.0.0](https://brew.sh/2025/11/12/homebrew-5.0.0/)); official casks must pass Gatekeeper ([Acceptable Casks](https://docs.brew.sh/Acceptable-Casks)). Neither page says whether third-party taps are held to it.
- **Inference** The current formula works with an ad-hoc binary because it installs a command-line tool, not a quarantined app. A cask in `mbackschat/homebrew-tap` with an ad-hoc app would install, then hit Gatekeeper on first launch, with no supported bypass flag; Homebrew's direction makes a signed, notarized app the only durable cask. Use a distinct token (for example `agent-monitor-app`) so `brew install agent-monitor` keeps meaning the formula. Keep the CLI in the formula; shipping it also through the cask's `binary` stanza raises a resource-bundle lookup question (the CLI would then run from inside an app bundle) and a formula/cask conflict, so defer it.

### Release-process impact

- **Inference** `scripts/package-release.py` stays for the CLI tarball. Add a sibling (for example `scripts/package-app.py`) that assembles, signs with Developer ID and hardened runtime, submits with `notarytool --wait`, staples, zips, verifies with `codesign --verify --strict` and `spctl --assess`, and checks the version from the bundle. Credentials stay in the keychain (`notarytool store-credentials`), never in the repository or CI by default.
- **Inference** [Releasing](../releasing.md) gains: Developer ID prerequisites, the app packaging and notarization step, a second release asset (`.zip` or `.dmg`), the cask update in the tap, and a manual first-launch check on a clean user account. The statement "ad-hoc signed and not notarized" must then be split per artifact. If Developer ID is adopted, signing and notarizing the CLI tarball becomes cheap and would remove the download warning in [installation](../installation.md#install-the-release).

## 5. Blast radius

### New

| Item | Purpose |
|---|---|
| Library target, for example `AgentMonitorMenuBarModel` | `@MainActor` view model over `LiveReportState`, cadence policy, action dispatch; no SwiftUI import, unit-testable |
| Executable target, for example `AgentMonitorMenuBar` | SwiftUI `App` with `MenuBarExtra`, views, settings, optional `SMAppService` and `UserNotifications`; depends on Core, Presentation, Actions and the model |
| Test target, for example `AgentMonitorMenuBarTests` | Model tests with fake `ProcessReading`/`ProcessActions`: cadence switching, selection by ID, action flow, cancellation on quit |
| `Info.plist` and `.entitlements` templates outside `Sources/` (or excluded from the target) | Bundle metadata, `LSUIElement`, usage string, Apple Events entitlement |
| `scripts/package-app.py` | Bundle assembly, signing, notarization, verification |
| Cask in the tap repository | Distribution |
| App icon asset | Status item symbol can be an SF Symbol; the app still needs an `.icns` for Finder and Settings |

### Changed

| File or area | Change |
|---|---|
| [Package.swift](../../Package.swift) | New targets; no new external dependency for a `MenuBarExtra` design |
| `Sources/AgentMonitorPresentation/LiveReportState.swift` | Add `select(_:)`, direct threshold/interval setters, group toggle independent of TUI details |
| `Sources/AgentMonitorPresentation/LiveReportLayout.swift` | Extract details facts into a neutral model; TUI output unchanged (preview check guards it) |
| `Sources/AgentMonitorPresentation/ActionPanel.swift` | Whole-text composer setter with the same filtering; host-neutral focusing note (today it says "the terminal running Agent Monitor") |
| `Sources/AgentMonitorActions/TerminalFocus/Adapters/TerminalAppFocus.swift` | Error texts name "the terminal running Agent Monitor" and "press f again"; wording must come from the host |
| `Sources/AgentMonitorActions/ClaudeMessaging.swift`, `CodexMessaging.swift` | Injectable absolute executable path instead of `/usr/bin/env` lookup for GUI hosts |
| `Sources/AgentMonitorCore/MonitoringSession.swift` (recommended) | Event-driven interval changes and sleep tolerance instead of quarter-second polling |
| [.github/workflows/verify.yml](../../.github/workflows/verify.yml) | Nothing required (`swift test` builds the new targets); optionally an unsigned bundle-assembly check |
| Docs | [README](../../README.md) features/install/support, [installation](../installation.md) (cask), [usage](../usage.md) (menu bar section), [architecture](../architecture.md) (GUI adapter, Automation attribution per host), [development](../development.md) (run/debug the app), [releasing](../releasing.md), [PLAN.md](../../PLAN.md) and [PRODUCT.md](PRODUCT.md) (scope: a menu bar UI, packaging and notifications are currently listed as outside the PoC plan), [CLAUDE.md](../../CLAUDE.md) (target list and boundaries), [terminal focus](terminal-focus.md) permission notes |

### Untouched

`NativeProcessReader`, `Monitor`, attribution rules, `Model.swift`, the JSONL contract and schema, `TextReport`/`ReportTable`/`ANSIText`, the CLI target and its options and subcommands, the SwiftTUI host and its PTY tests, the README preview generator and SVG, `scripts/verify-*.py`, the skills setup, and the existing formula.

### Effort

| Scope | Content | Estimate |
|---|---|---|
| Prototype | Unbundled `swift run` with `.accessory` policy, `MenuBarExtra(.window)`, read-only grouped list and details from the real `MonitoringSession`, cadence switching; measured CPU/energy with the popover closed | **S** (one to two days) |
| Minimal viable app | Prototype plus settings (thresholds, background interval), bundle script, Apple Development or ad-hoc signing for personal use, model tests, docs | **M** |
| Feature parity and distribution | Terminate/message/focus with review and confirmation, composer, provider CLI resolution, Automation permission UX, notifications with debounce, launch at login, Developer ID signing, notarization, cask, release docs | **L** |

## 6. Risks, open questions and recommendation

### Risks (ranked)

1. **Distribution requires a paid Developer ID.** Without it, a downloaded app is blocked by Gatekeeper until the user approves it in System Settings, Homebrew offers no supported bypass, and every update silently drops the Automation grant. Decide this before promising a cask.
2. **Provider messaging breaks outside a shell environment.** `/usr/bin/env` cannot find `claude` or `codex` from a launchd-started app. Resolving an absolute path safely, and keeping it valid across provider updates, is new work and a new trust decision.
3. **Long-lived energy cost.** The quarter-second wait loop, a 1 s default, and SwiftUI redraws of an unseen popover could make the app a visible entry in Activity Monitor's Energy tab. Needs the cadence policy and a measurement gate before release.
4. **`MenuBarExtra` gaps.** No first-party presentation control; possible text-field focus quirks for the composer. The `NSStatusItem` fallback is known, but costs AppKit glue.
5. **Automation attribution is undocumented.** TCC's responsible-process algorithm "has changed in the past"; the app-as-responsible behavior and the entitlement need for an `osascript` child must be observed, not assumed.
6. **Scope.** [PLAN.md](../../PLAN.md) and [PRODUCT.md](PRODUCT.md) currently list a menu bar UI, packaging and notifications as outside the PoC; building this requires an explicit scope decision.

### Open questions

- Does hiding the item via System Settings › Menu Bar terminate a menu-bar-only app, as removing the extra does?
- Does focus from an active accessory app (with `yieldActivation(to:)`) reliably bring Terminal's window forward on macOS 27, including other Spaces and full screen?
- Should the app also own a long-lived history (for detached-child attribution) while the popover is closed, or is a slow cadence enough?
- Should the menu bar app and a running TUI share one collector? Today each would sample independently, doubling the cost when both run; sharing would need IPC that the architecture deliberately avoids.
- Is one cask that also links the CLI wanted later, or should formula and cask stay separate?

### Pre-existing issues found (not fixed here)

- **Host-specific wording inside `AgentMonitorActions`.** `TerminalAppFocus` errors say "the terminal running Agent Monitor" and "press f again"; the same text already reaches the `focus --pid` CLI subcommand, which has no `f` key. Presentation wording belongs to each host; the action layer should return a typed failure (for example permission denied, timed out) that hosts word. This is a separate change.
- **Polling wait in `MonitoringSession`.** Fine for the TUI, but four wakeups per second independent of the interval; see section 1.

### Recommendation

**Prototype first (go for a prototype, no-go for distribution until Developer ID is decided).** The smallest sensible first step: add an `AgentMonitorMenuBar` executable target that runs unbundled via `swift run` with `.accessory` activation policy, shows a read-only `MenuBarExtra(.window)` with session groups and details driven by the existing `MonitoringSession` and `LiveReportState`, and switches between a 1 s interval when open and 10 s when closed. Its acceptance criteria are: no change to core, CLI or TUI behavior; and a measured background cost (CPU and wakeups with the popover closed over ten minutes) compared with the headless watch. Actions, bundling, signing and distribution follow only after that gate passes and the Developer ID question is answered.

## Gaps

- Nothing was built or launched; all GUI behavior (popover refresh, focus, App Nap, energy) is unobserved.
- Live refresh of an open `.menu`-style extra and composer focus in `.window` style are untested.
- Whether TCC requires the Apple Events entitlement on the app when an `osascript` child sends the events is supported only by a low-confidence third-party report.
- The launch environment `PATH` of a Finder- or login-started app on macOS 27 was inferred, not printed from a running app.
- Homebrew's Gatekeeper policy for third-party taps after September 2026 is not stated in the inspected pages; Homebrew's post-September behavior was not checked.
- Pricing and membership terms were read from Apple's program page on 2026-10-15 and can change.
- Background sampling cost at 5–10 s intervals is extrapolated from the 1 s measurement, not measured.

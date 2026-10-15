# Menu bar app feasibility findings

Checked 2026-10-15 on Apple Silicon, macOS 27.0.1, Xcode 27 and Swift 6.4. The investigation inspected repository code, SDK headers, installed Homebrew 7.0.9-110 source and the linked documentation. No GUI prototype was built or launched, no signing identity was created, and no permission was changed. These are dated findings, not a distribution guarantee. The user's energy constraint and pending product choices are retained in the [separate proposal](../proposals/menubar-app.md).

**Local** means a read-only code, header or command observation; **documented** means the cited upstream material; **third-party** means a report not independently reproduced; **inference** identifies a conclusion beyond those observations.

## UI and lifecycle APIs

| Surface | Findings | Evidence |
|---|---|---|
| SwiftUI `MenuBarExtra(.window)` | Supports a richer, popover-like window. The inspected SDK exposes insertion state but no public presentation-state binding or access to the status item/window. Composer focus and menu-bar auto-hide have reported issues, untested here. | [Apple API](https://developer.apple.com/documentation/swiftui/menubarextra), [window style](https://developer.apple.com/documentation/swiftui/windowmenubarextrastyle); local SwiftUI interface; third-party [focus report](https://developer.apple.com/forums/thread/729920), [auto-hide report](https://developer.apple.com/forums/thread/761204) |
| AppKit `NSStatusItem` / `NSPopover` | Exposes status-button and popover control; can host SwiftUI content. The extra lifecycle control requires AppKit integration. | [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem); integration cost is an inference |
| Agent-app lifecycle | `LSUIElement` corresponds to accessory activation policy. Apple's menu-bar documentation says a menu-bar-only app terminates when its extra is removed. Whether hiding it through System Settings has the same effect was not observed. | [Accessory policy](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory), [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra), [Menu Bar settings](https://support.apple.com/en-gb/guide/mac-help/mchlad96d366/26/mac/27) |
| Launch at login | `SMAppService.mainApp` registers the app for later logins. The inspected header requires a properly signed bundle and exposes `requiresApproval`. | [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), local `SMAppService.h` |
| Notifications | `UNUserNotificationCenter` is an app/app-extension API. A developer-forum report describes failure from an unbundled CLI; no notification prototype was run. | [Apple API](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter), [third-party report](https://developer.apple.com/forums/thread/724249) |

## Repository and launch-environment observations

Local source inspection found UI-independent snapshots, grouping and action services. Terminal layout produces padded strings; it does not supply native controls. Some interaction APIs are keyboard-shaped, and details content is assembled inside `LiveReportLayout`. These are integration boundaries, not a finding that GUI reuse needs no changes. Current ownership is defined in [architecture](../architecture.md).

Provider transports invoke `/usr/bin/env claude` and `/usr/bin/env codex`. On the inspected machine the CLIs were under `~/.local/bin` and `/opt/homebrew/bin`, while `launchctl getenv PATH` was empty and the SDK's standard path was `/usr/bin:/bin:/usr/sbin:/sbin`. **Inference:** a Finder/login-launched app may not locate the same executables. Its actual environment was not sampled from a running app.

The generated SwiftPM `Bundle.module` accessor searched `Bundle.main.resourceURL` before its framework and CLI fallbacks. **Inference:** an app's resource directory can carry the schema bundle. No assembled app was tested. SwiftPM does not itself provide an app-bundle product; scripted assembly and an Xcode app target are distinct build paths ([Swift Forums](https://forums.swift.org/t/building-an-app-from-a-swift-package-manager-executable-for-macos/64409)).

The collector divides CPU-time deltas by measured elapsed time, so delayed sampling widens the averaging window rather than changing the percentage's unit. The current [LiveInterval](../../Sources/AgentMonitorCore/MonitoringSession.swift) wakes on changes; the quarter-second polling recorded during the initial investigation was removed in 0.2.1. Historical [headless and TUI measurements](README.md#retained-measurements) do not establish closed-popover energy use. Apple describes event-driven work and timer tolerance as energy-saving mechanisms, and warns that App Nap is not a substitute for idling ([timers](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html), [App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html)).

## Process access and Automation

- **Documented:** Apple DTS states that App Sandbox blocks the relevant libproc calls and supplies no entitlement exemption. App Store rules require sandboxing. **Inference:** this collector's current process-inspection model is incompatible with that distribution model. [DTS 776473](https://developer.apple.com/forums/thread/776473), [DTS 691857](https://developer.apple.com/forums/thread/691857), [review rules](https://developer.apple.com/app-store/review/guidelines/#2.4.5).
- **Local:** the collector does not use `task_for_pid`. Hardened Runtime's task-port restrictions therefore do not directly describe its libproc access. Same-user behavior in a hardened app was not tested. [Hardened Runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime).
- **Documented:** TCC assigns Apple Events to responsible code; Apple DTS says that attribution is undocumented and has changed. **Inference:** an app launching `osascript` would normally be the controller named in consent, rather than the hosting terminal. This has not been observed for Agent Monitor. [DTS explanation](https://developer.apple.com/forums/thread/756510).
- **Documented:** apps sending Apple Events require `NSAppleEventsUsageDescription`; Hardened Runtime provides the Automation entitlement. Whether a self-signed app without Hardened Runtime needs that entitlement for an `osascript` child remains unresolved. [Usage string](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription), [entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events).
- **Documented:** activation is a cooperative request. An active app can yield activation to another app; whether an accessory app can reliably focus the target across Spaces/full screen remains untested. [Activation API](https://developer.apple.com/documentation/appkit/nsapplication/yieldactivation(to:)), [terminal findings](terminal-focus.md#3-macos-permission-and-activation-model).

## Signing and Homebrew findings

The local identity inventory contained Apple Development but no Developer ID Application identity. The inspected notarization documentation required Developer ID, Hardened Runtime, a secure timestamp and no `get-task-allow`. This describes the checked environment and documentation, not a current account assessment. [Notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

| Observation | Meaning and limits |
|---|---|
| Local Homebrew source applied quarantine in cask paths, not formula installation paths. The installed ad-hoc CLI ran despite `spctl --assess` rejecting it. | This is evidence about the CLI and inspected Homebrew version, not proof that a formula-installed GUI app will launch without a prompt. Apple DTS says Gatekeeper can run outside quarantine under undocumented, changing conditions. [DTS 706442](https://developer.apple.com/forums/thread/706442). |
| Homebrew-core excludes formulae primarily producing `.app` bundles; third-party formulae such as emacs-plus install apps into their prefix. Homebrew skips `.app` directories when linking. | A formula does not place the bundle in `/Applications`. [Formula policy](https://docs.brew.sh/Acceptable-Formulae), [emacs-plus example](https://github.com/d12frosted/homebrew-emacs-plus/blob/master/Formula/emacs-plus@30.rb). |
| Casks provide app placement, optional binary links and uninstall metadata. Official cask policy requires Gatekeeper compatibility. | Formula and cask installation have different mechanics. The review did not establish identical policy enforcement for third-party taps. [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook), [Acceptable Casks](https://docs.brew.sh/Acceptable-Casks), [Homebrew 5 changes](https://brew.sh/2025/11/12/homebrew-5.0.0/). |
| The inspected Homebrew sandbox denied login-keychain reads during builds/post-install; patched Mach-O files could be re-signed ad hoc. | Install-time signing with a user's keychain identity and preservation of a pre-signed app cannot be assumed. [Homebrew 7 changes](https://brew.sh/2026/09/13/homebrew-7.0.0/); local `sandbox.rb`, `formula_installer.rb`, `extend/os/mac/keg.rb`. |
| Ad-hoc code has a designated requirement tied to its particular build; a stable signing identity can preserve identity across releases. | Privacy-grant continuity depends on code identity, not just the bundle name. [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), [Apple DTS](https://developer.apple.com/forums/thread/795739). |
| Apple's archived guide describes self-signed designated requirements without requiring users to trust the certificate, but advises against shipping self-signed apps. | Identity continuity is distinct from Gatekeeper approval and notarization. [Signing guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html). |

**Third-party evidence:** an ad-hoc app without quarantine launched without warnings on macOS 26.6.1 in an [Eclectic Light test](https://eclecticlight.co/2026/08/11/how-can-you-run-code-that-hasnt-been-notarised/). [skhd.zig](https://github.com/jackielii/skhd.zig/blob/main/docs/CODE_SIGNING.md) and [shannoncoat](https://git.bdeshi.space/bdeshi/shannoncoat/src/branch/main/.env.example) report Accessibility-grant persistence with a stable self-signed certificate. These observations do not establish Automation-grant persistence or first launch for Agent Monitor on macOS 27.

**Inference:** a stable self-signed identity could preserve an Automation grant across upgrades, and formula installation could avoid a quarantine-triggered assessment. Neither claim was tested with this app; certificate replacement, Homebrew re-signing or changed Gatekeeper behavior could invalidate it.

Login-item reports conflict: [Tuck](https://github.com/lordkerwin/tuck) exposes `SMAppService` with ad-hoc signing, while a [Shuttle fork](https://github.com/morri5/shuttle) reports needing a Team ID. [skhd.zig issue 53](https://github.com/jackielii/skhd.zig/issues/53) reports self-signed registration trouble on macOS 27, but concerns an agent service rather than `mainApp`. A changing Cellar path adds an untested registration/upgrade interaction.

## Unresolved empirical questions

- Does the chosen UI API reliably expose open/closed state, support composer focus and release every source of work while closed?
- Which controller appears in Automation consent, and does focus succeed across Spaces and full screen?
- What PATH does a Finder/login launch receive, and how do provider updates affect executable discovery?
- Does an installed app retain its signature, launch successfully and keep Automation grants across upgrades under each signing/distribution route?
- Does `SMAppService.mainApp` accept the chosen signature and survive path changes? How does App Management affect removal of a previously launched keg?

No GUI install, upgrade, permission, login-item or energy test was performed. Source findings cannot settle these questions.

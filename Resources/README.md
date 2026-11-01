# Application icon source

`AgentMonitor.icon` is the editable Icon Composer document for the Mac application icon. Its JSON definition and SVG layers are the source of truth; open the directory with Icon Composer to edit appearances. The user approved this design on 2026-11-01 after reviewing native default, dark, clear and tinted renders.

[Bundle assembly](../scripts/macos_bundle.py) compiles it with Xcode's `actool`, places `Assets.car` and `AgentMonitor.icns` in the app's resources and uses the compiler's icon metadata. Generated binaries belong only in ignored build output and release archives. Do not commit exported PNGs, ICNS files or asset catalogs compiled from this document.

Keep design studies and preview sheets under ignored `.build/design-studies/`. Follow the [icon review gate](../docs/macos-release.md#required-app-icon-review) for changes. The [panel logo](../Sources/AgentMonitorMenuBar/Resources/agent-monitor.webp) and the live monochrome status icon are separate resources with different roles.

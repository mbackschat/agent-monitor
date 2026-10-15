import AgentMonitorCore
import AppKit
import SwiftUI

@main
enum MenuBarApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = MenuBarDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class MenuBarDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private let model = MenuBarModel { thresholds, interval, receive in
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                thresholds: await thresholds(), intervalSeconds: interval.seconds, samples: 0,
                collectAgentLoad: true),
            reader: try NativeProcessReader(), excluding: [ProcessInfo.processInfo.processIdentifier])
        try await session.run(thresholds: thresholds, interval: interval, receive)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.item = item
        model.onIndicatorChange = { [weak self] in self?.updateIndicator() }
        updateIndicator()
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let host = NSHostingController(
            rootView: MenuBarView(model: model) { [weak popover] size in
                guard let popover, popover.contentSize != size else { return }
                popover.contentSize = size
            })
        host.sizingOptions = [.intrinsicContentSize]
        host.view.setFrameSize(host.view.fittingSize)
        popover.contentViewController = host
        model.start()
    }

    private func updateIndicator() {
        guard let button = item?.button else { return }
        let tooltip: String
        if model.liveIcon {
            if let level = model.indicator.level {
                button.image = MenuBarStatusImage.make(level: level, highlighted: model.indicator.highlighted)
            } else {
                let symbol: String
                switch model.indicator.availability {
                case .waiting: symbol = "ellipsis"
                case .current, .unavailable: symbol = "questionmark.square"
                }
                button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            button.contentTintColor = model.indicator.highlighted ? .controlAccentColor : nil
            tooltip = model.indicator.tooltip
        } else {
            button.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
            button.contentTintColor = nil
            tooltip = "Agent Monitor — static icon; updates only while open"
        }
        button.image?.isTemplate = true
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = item?.button {
            if let host = popover.contentViewController as? NSHostingController<MenuBarView> {
                host.rootView.maximumHeight = max(
                    100, (button.window?.screen?.visibleFrame.height ?? 600) - 40)
            }
            NSApplication.shared.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidShow(_ notification: Notification) { model.open() }
    func popoverWillClose(_ notification: Notification) { model.close() }
    func popoverShouldDetach(_ popover: NSPopover) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

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
    private let model = MenuBarModel { receive in
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(samples: 0),
            reader: try NativeProcessReader(), excluding: [ProcessInfo.processInfo.processIdentifier])
        try await session.run(receive)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.item = item
        item.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Agent Monitor")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "Agent Monitor"
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MenuBarView(model: model))
        popover.contentSize = NSSize(width: 420, height: 560)
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = item?.button {
            NSApplication.shared.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidShow(_ notification: Notification) { model.open() }
    func popoverWillClose(_ notification: Notification) { model.close() }
    func popoverShouldDetach(_ popover: NSPopover) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.close()
        Task {
            await model.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

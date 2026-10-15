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
    private lazy var statusMenu = MenuBarStatusMenu(model: model)
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
        item.button?.action = #selector(activateStatusItem)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        let description: String
        if model.liveIcon {
            button.image = MenuBarStatusImage.make(
                level: model.indicator.level, heavyCount: model.indicator.heavyCount)
            button.contentTintColor = nil
            description = model.indicator.statusDescription
        } else {
            button.image = MenuBarStatusImage.make(level: nil, heavyCount: nil)
            button.contentTintColor = nil
            description = "Agent Monitor — static icon; updates only while open"
        }
        button.image?.isTemplate = true
        button.setAccessibilityLabel(description)
    }

    @objc private func activateStatusItem() {
        let event = NSApplication.shared.currentEvent
        switch MenuBarActivation(eventType: event?.type, modifiers: event?.modifierFlags ?? []) {
        case .panel: toggle()
        case .contextMenu: showStatusMenu()
        }
    }

    private func showStatusMenu() {
        guard let button = item?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        let menu = statusMenu.makeMenu()
        button.highlight(true)
        let origin = NSPoint(
            x: button.bounds.minX, y: button.isFlipped ? button.bounds.maxY : button.bounds.minY)
        menu.popUp(positioning: nil, at: origin, in: button)
        button.highlight(false)
        switch statusMenu.selectedAction {
        case .open: toggle()
        case .quit: NSApplication.shared.terminate(nil)
        case nil: break
        }
    }

    private func toggle() {
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
    func popoverShouldDetach(_ popover: NSPopover) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

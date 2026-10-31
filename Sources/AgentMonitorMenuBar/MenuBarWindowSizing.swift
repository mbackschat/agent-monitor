import AppKit
import SwiftUI

@MainActor final class MenuBarWindowSizing: NSObject {
    private let model: MenuBarModel
    private weak var host: NSHostingController<MenuBarView>?
    private weak var window: NSWindow?
    private var applyingPreset = false
    private var showingSummary = false

    init(model: MenuBarModel, host: NSHostingController<MenuBarView>, window: NSWindow) {
        self.model = model
        self.host = host
        self.window = window
        super.init()
        let size = host.view.bounds.size
        // NSPopover.h recommends retaining its implicit detached window for identical content.
        // Flexible SwiftUI bounds let AppKit own drag sizing without recreating the table.
        host.rootView.detached = true
        // Automatic hosting constraints move the detached frame before our top-edge restoration
        // (MenuBarWindowSizingTests); this controller owns its size and bounds instead.
        host.sizingOptions = []
        window.styleMask.insert(.resizable)
        showingSummary = model.isSummaryOnly
        window.contentMinSize = NSSize(
            width: MenuBarLayout.width,
            height: showingSummary ? size.height : min(420, host.rootView.maximumHeight))
        window.contentMaxSize = NSSize(
            width: MenuBarLayout.width,
            height: showingSummary ? size.height : host.rootView.maximumHeight)
        window.setContentSize(size)
        NotificationCenter.default.addObserver(
            self, selector: #selector(resized), name: NSWindow.didResizeNotification, object: window)
        model.onPanelSizeChange = { [weak self] in self?.applyPreset() }
    }

    @objc private func resized(_ notification: Notification) {
        guard !applyingPreset, !showingSummary, !model.isSummaryOnly, let host else { return }
        model.rememberPanelHeight(host.view.bounds.height)
    }

    private func applyPreset() {
        guard !applyingPreset, let window, let host else { return }
        applyingPreset = true
        let top = window.frame.maxY
        let summary = model.isSummaryOnly
        host.view.layoutSubtreeIfNeeded()
        let height = min(
            summary
                ? host.sizeThatFits(in: NSSize(width: MenuBarLayout.width, height: model.panelHeight)).height
                : model.panelHeight, host.rootView.maximumHeight)
        let animate = summary != showingSummary && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        showingSummary = summary
        var frame = window.frameRect(
            forContentRect: NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: height))
        frame.origin = NSPoint(x: window.frame.minX, y: top - frame.height)
        func setBounds() {
            window.contentMinSize = NSSize(
                width: MenuBarLayout.width, height: summary ? height : min(420, host.rootView.maximumHeight))
            window.contentMaxSize = NSSize(
                width: MenuBarLayout.width, height: summary ? height : host.rootView.maximumHeight)
        }
        guard frame != window.frame else {
            setBounds()
            applyingPreset = false
            return
        }
        if animate {
            // Permit intermediate sizes; lock summary bounds only after the native animation.
            // The resize observer must not persist an intermediate height as the user's preference.
            window.contentMinSize = NSSize(
                width: MenuBarLayout.width, height: min(height, window.contentLayoutRect.height))
            window.contentMaxSize = NSSize(width: MenuBarLayout.width, height: host.rootView.maximumHeight)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = MenuBarPopoverSizing.duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.window != nil else { return }
                    self.applyingPreset = false
                    // Reconcile a quick second toggle or notice change received during motion.
                    self.applyPreset()
                }
            }
        } else {
            setBounds()
            window.setFrame(frame, display: true)
            applyingPreset = false
        }
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        model.onPanelSizeChange = nil
        host?.rootView.detached = false
        host?.sizingOptions = [.intrinsicContentSize]
        host = nil
        window = nil
    }
}

@MainActor struct MenuBarPopoverSizing {
    static let duration: TimeInterval = 0.18
    private var showingSummary = false

    mutating func update(
        _ popover: NSPopover, size: NSSize, summary: Bool,
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    ) {
        guard !popover.isDetached else { return }
        let animate = summary != showingSummary && !reduceMotion
        showingSummary = summary
        guard popover.contentSize != size else { return }
        // NSPopover.h documents animates for content-size changes; AppKit owns anchoring.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            popover.animates = animate
            popover.contentSize = size
        } completionHandler: {
        }
    }
}

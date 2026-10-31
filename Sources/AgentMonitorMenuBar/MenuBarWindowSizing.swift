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
        window.contentMinSize = NSSize(
            width: MenuBarLayout.width, height: summary ? height : min(420, host.rootView.maximumHeight))
        window.contentMaxSize = NSSize(
            width: MenuBarLayout.width, height: summary ? height : host.rootView.maximumHeight)
        window.setContentSize(NSSize(width: MenuBarLayout.width, height: height))
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
        showingSummary = summary
        applyingPreset = false
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        model.onPanelSizeChange = nil
        host?.rootView.detached = false
        host?.sizingOptions = [.intrinsicContentSize]
    }
}

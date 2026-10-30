import AppKit
import SwiftUI

struct MenuBarResizeGrip: NSViewRepresentable {
    let model: MenuBarModel
    let maximumHeight: CGFloat

    func makeNSView(context: Context) -> Grip { Grip() }

    func updateNSView(_ view: Grip, context: Context) {
        view.height = { min(model.panelHeight, maximumHeight) }
        view.resize = { proposed in
            guard proposed.isFinite else { return }
            model.rememberPanelHeight(
                max(min(MenuBarPanelSize.compact.height, maximumHeight), min(proposed, maximumHeight)))
            model.onPanelSizeChange?()
        }
        view.setAccessibilityValue("\(Int(min(model.panelHeight, maximumHeight))) points")
    }

    final class Grip: NSView {
        var height: () -> CGFloat = { 0 }
        var resize: (CGFloat) -> Void = { _ in }
        private var drag: (height: CGFloat, screenY: CGFloat)?

        override init(frame: NSRect) {
            super.init(frame: frame)
            toolTip =
                "Drag up to make the panel shorter or down to make it taller. Works attached to the menu bar or detached."
            setAccessibilityElement(true)
            setAccessibilityRole(.splitter)
            setAccessibilityLabel("Panel height")
            setAccessibilityHelp(toolTip)
            setAccessibilityIdentifier("panel-height-resize")
        }

        required init?(coder: NSCoder) { nil }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .frameResize(position: .bottom, directions: .all))
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.secondaryLabelColor.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: bounds.midX - 20, y: bounds.midY - 2, width: 40, height: 4),
                xRadius: 2, yRadius: 2
            ).fill()
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            drag = (height(), window.convertPoint(toScreen: event.locationInWindow).y)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let drag, let window else { return }
            // Screen coordinates stay stable when popover geometry moves during the drag.
            resize(drag.height + drag.screenY - window.convertPoint(toScreen: event.locationInWindow).y)
        }

        override func mouseUp(with event: NSEvent) { drag = nil }

        override func accessibilityPerformIncrement() -> Bool {
            resize(height() + 40)
            return true
        }

        override func accessibilityPerformDecrement() -> Bool {
            resize(height() - 40)
            return true
        }
    }
}

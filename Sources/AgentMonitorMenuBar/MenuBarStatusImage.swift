import AppKit

enum MenuBarStatusImage {
    @MainActor static func make(level: Int, highlighted: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSColor.black.set()
            if highlighted {
                NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 18, height: 18), xRadius: 3, yRadius: 3)
                    .fill()
                // A template mask lets AppKit choose contrast for the actual menu bar appearance.
                NSGraphicsContext.current?.compositingOperation = .destinationOut
            }
            for index in 0..<3 {
                let base = NSRect(x: 1 + index * 6, y: 3, width: 4, height: 4 + index * 5)
                let rect = highlighted ? base.insetBy(dx: 0.5, dy: 1) : base
                let bar = NSBezierPath(roundedRect: rect, xRadius: 0.8, yRadius: 0.8)
                if index < level {
                    bar.fill()
                } else {
                    bar.lineWidth = 1
                    bar.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

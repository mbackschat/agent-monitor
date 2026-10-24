import AppKit

enum MenuBarStatusImage {
    @MainActor static func make(level: Int?) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSColor.black.set()
            for index in 0..<3 {
                let rect = NSRect(x: CGFloat(1 + index * 6), y: 0.5, width: 4, height: CGFloat(6 + index * 5))
                let bar = NSBezierPath(roundedRect: rect, xRadius: 0.8, yRadius: 0.8)
                if index < (level ?? 0) {
                    bar.fill()
                } else {
                    bar.lineWidth = 0.5
                    bar.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

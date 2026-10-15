import AppKit

enum MenuBarStatusImage {
    @MainActor static func make(level: Int, highlighted: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            for index in 0..<3 {
                let rect = NSRect(x: 1 + index * 6, y: 3, width: 4, height: 4 + index * 5)
                let bar = NSBezierPath(roundedRect: rect, xRadius: 0.8, yRadius: 0.8)
                if index < level {
                    bar.fill()
                } else {
                    bar.lineWidth = 1
                    bar.stroke()
                }
            }
            if highlighted { NSRect(x: 1, y: 0, width: 16, height: 2).fill() }
            return true
        }
        image.isTemplate = true
        return image
    }
}

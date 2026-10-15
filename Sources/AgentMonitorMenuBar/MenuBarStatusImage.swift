import AppKit

enum MenuBarStatusImage {
    @MainActor static func make(level: Int?, heavyCount: Int?) -> NSImage {
        let text = heavyCount.map {
            NSAttributedString(
                string: $0 > 99 ? "99+" : String($0),
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .bold),
                    .foregroundColor: NSColor.black,
                ])
        }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSColor.black.set()
            for index in 0..<3 {
                let rect = NSRect(x: 1 + index * 6, y: 3, width: 4, height: 4 + index * 5)
                let bar = NSBezierPath(roundedRect: rect, xRadius: 0.8, yRadius: 0.8)
                if index < (level ?? 0) {
                    bar.fill()
                } else {
                    bar.lineWidth = 1
                    bar.stroke()
                }
            }
            if let text {
                let size = text.size()
                let width = min(18, max(10, ceil(size.width) + 2))
                let rect = NSRect(x: 18 - width, y: 8, width: width, height: 10)
                // A clear halo separates the overlay from the bars without fixing a light/dark background.
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: 4, yRadius: 4).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

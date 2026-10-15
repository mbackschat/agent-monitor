import AppKit

enum MenuBarStatusImage {
    @MainActor static func make(symbol: MenuBarStatusSymbol, heavyCount: Int?) -> NSImage {
        let text = heavyCount.map {
            NSAttributedString(
                string: String($0),
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: NSColor.black,
                ])
        }
        let badgeWidth = text.map { max(18, ceil($0.size().width) + 8) } ?? 0
        let width = text == nil ? 18 : 22 + badgeWidth
        let image = NSImage(size: NSSize(width: width, height: 18), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSColor.black.set()
            switch symbol {
            case .bars(let level):
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
            case .terminal, .unavailable:
                let name = symbol == .terminal ? "terminal" : "questionmark.square"
                NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            }
            if let text {
                NSBezierPath(
                    roundedRect: NSRect(x: 22, y: 1, width: badgeWidth, height: 16),
                    xRadius: 4, yRadius: 4
                ).fill()
                // Knockout digits let AppKit choose badge contrast for the actual menu bar appearance.
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                let size = text.size()
                text.draw(at: NSPoint(x: 22 + (badgeWidth - size.width) / 2, y: (18 - size.height) / 2))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

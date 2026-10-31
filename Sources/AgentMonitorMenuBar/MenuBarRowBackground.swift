import AppKit
import SwiftUI

/// Decorates full native rows so subtree fills and guides include the cell's outer padding.
struct MenuBarRowBackground: NSViewRepresentable {
    var tint: Color = .clear
    var depth = 0
    var last = true
    var continuations: [Int] = []

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        view.style = self
        view.decorateRow()
    }

    static func dismantleNSView(_ view: Anchor, coordinator: ()) {
        view.observation?.invalidate()
        view.guides.removeFromSuperlayer()
        view.fill.removeFromSuperlayer()
    }

    final class Anchor: NSView {
        var style = MenuBarRowBackground()
        var observation: NSKeyValueObservation?
        let guides = CAShapeLayer()
        let fill = CALayer()
        private weak var styledRow: NSTableRowView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            decorateRow()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            decorateRow()
        }

        override func layout() {
            super.layout()
            decorateRow()
        }

        private func applyBackground() {
            guard let row = styledRow else { return }
            if row.backgroundColor != .clear { row.backgroundColor = .clear }
        }

        func decorateRow() {
            var ancestor = superview
            while let view = ancestor {
                if let row = view as? NSTableRowView {
                    // NSTableRowView.h allows background customization. Clear SwiftUI's rounded
                    // per-row fill so one rectangular subtree band spans native padding (2026-10-31 review).
                    if styledRow !== row {
                        observation?.invalidate()
                        styledRow = row
                        observation = row.observe(\.backgroundColor, options: [.new]) { [weak self] _, _ in
                            MainActor.assumeIsolated { self?.applyBackground() }
                        }
                    }
                    applyBackground()
                    if let layer = row.layer {
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        fill.frame = row.convertToLayer(row.bounds.insetBy(dx: 8, dy: 0))
                        fill.zPosition = -1
                        row.effectiveAppearance.performAsCurrentDrawingAppearance {
                            fill.backgroundColor = NSColor(style.tint).cgColor
                        }
                        if fill.superlayer !== layer { layer.addSublayer(fill) }
                        CATransaction.commit()
                    }
                    drawGuides(in: row)
                    return
                }
                ancestor = view.superview
            }
        }

        private func drawGuides(in row: NSTableRowView) {
            guard style.depth > 0, let layer = row.layer else {
                guides.removeFromSuperlayer()
                return
            }
            var ancestor = row.superview
            while ancestor != nil && !(ancestor is NSOutlineView) { ancestor = ancestor?.superview }
            guard let table = ancestor as? NSOutlineView else { return }
            let cell = row.convert(bounds, from: self)
            let x = cell.minX + CGFloat(style.depth) * 18 - 11
            let elbow = cell.minY + 20
            let path = CGMutablePath()
            func line(_ start: NSPoint, _ end: NSPoint) {
                path.move(to: row.convertToLayer(start))
                path.addLine(to: row.convertToLayer(end))
            }
            line(NSPoint(x: x, y: row.bounds.minY), NSPoint(x: x, y: style.last ? elbow : row.bounds.maxY))
            line(NSPoint(x: x, y: elbow), NSPoint(x: x + 13, y: elbow))
            for depth in style.continuations {
                let trunk = x - CGFloat(style.depth - depth) * (18 + table.indentationPerLevel)
                line(NSPoint(x: trunk, y: row.bounds.minY), NSPoint(x: trunk, y: row.bounds.maxY))
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            guides.path = path
            guides.fillColor = nil
            guides.lineWidth = 1.5
            row.effectiveAppearance.performAsCurrentDrawingAppearance {
                guides.strokeColor =
                    (row.isSelected ? NSColor.white : NSColor.secondaryLabelColor)
                    .withAlphaComponent(0.6).cgColor
            }
            if guides.superlayer !== layer { layer.addSublayer(guides) }
            CATransaction.commit()
        }
    }
}

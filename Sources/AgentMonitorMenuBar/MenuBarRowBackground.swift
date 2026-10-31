import AppKit
import SwiftUI

/// Decorates full native rows so subtree fills and guides include the cell's outer padding.
struct MenuBarRowBackground: NSViewRepresentable {
    var tint: Color = .clear
    var headlineOffset: CGFloat?
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
        view.disclosureObservation?.invalidate()
        view.guides.removeFromSuperlayer()
        view.fill.removeFromSuperlayer()
    }

    final class Anchor: NSView {
        var style = MenuBarRowBackground()
        var observation: NSKeyValueObservation?
        var disclosureObservation: NSKeyValueObservation?
        private weak var disclosure: NSButton?
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
                    alignDisclosure(in: row)
                    drawGuides(in: row)
                    return
                }
                ancestor = view.superview
            }
        }

        private func alignDisclosure(in row: NSTableRowView) {
            guard style.headlineOffset != nil else {
                disclosureObservation?.invalidate()
                disclosureObservation = nil
                disclosure = nil
                return
            }
            // SDK NSOutlineView.h identifies the native disclosure button publicly. Preserve its
            // target/action and hit area; only align its center with the row's headline and guide.
            let button = row.subviews.compactMap { $0 as? NSButton }.first {
                $0.identifier == NSOutlineView.disclosureButtonIdentifier
            }
            if disclosure !== button {
                disclosureObservation?.invalidate()
                disclosure = button
                disclosureObservation = button?.observe(\.frame, options: [.new]) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.positionDisclosure() }
                }
            }
            positionDisclosure()
        }

        private func positionDisclosure() {
            guard let offset = style.headlineOffset, let row = styledRow,
                let button = disclosure, let parent = button.superview
            else { return }
            let titleY = row.convert(bounds, from: self).minY + offset
            let center = parent.convert(NSPoint(x: 0, y: titleY), from: row).y
            let y = center - button.frame.height / 2
            if abs(button.frame.minY - y) > 0.25 {
                button.setFrameOrigin(NSPoint(x: button.frame.minX, y: y))
            }
        }

        private func drawGuides(in row: NSTableRowView) {
            guard style.depth > 0, let offset = style.headlineOffset, let layer = row.layer else {
                guides.removeFromSuperlayer()
                return
            }
            var ancestor = row.superview
            while ancestor != nil && !(ancestor is NSOutlineView) { ancestor = ancestor?.superview }
            guard let table = ancestor as? NSOutlineView else { return }
            let cell = row.convert(bounds, from: self)
            let x = cell.minX + CGFloat(style.depth) * 18 - 11
            let elbow = cell.minY + offset
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

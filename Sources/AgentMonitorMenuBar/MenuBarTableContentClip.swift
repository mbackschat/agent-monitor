import AppKit

@MainActor final class MenuBarTableContentClip {
    private weak var table: NSOutlineView?
    private let mask = CAShapeLayer()
    private let surface = CAShapeLayer()
    private let border = CAShapeLayer()
    private let highlight = CAShapeLayer()
    private var frameObservation: NSKeyValueObservation?
    private var boundsObservation: NSKeyValueObservation?

    func update(_ table: NSOutlineView) {
        if self.table !== table {
            detach()
            self.table = table
            mask.fillColor = NSColor.black.cgColor
            surface.zPosition = -1
            border.zPosition = 1_000
            highlight.zPosition = 1_000
            border.fillColor = nil
            highlight.fillColor = nil
            border.lineWidth = 1
            highlight.lineWidth = 1
            frameObservation = table.observe(\.frame, options: [.new]) { [weak self] table, _ in
                MainActor.assumeIsolated { self?.refresh(table) }
            }
            boundsObservation = table.observe(\.bounds, options: [.new]) { [weak self] table, _ in
                MainActor.assumeIsolated { self?.refresh(table) }
            }
        }
        refresh(table)
    }

    func refresh() {
        if let table { refresh(table) }
    }

    private func refresh(_ table: NSOutlineView) {
        guard let layer = table.layer else { return }
        // SwiftUI's SDK 27 TableRowContent has no section-spanning background modifier.
        // Use the existing drawing bridge and native group-row geometry, retaining Table ownership.
        let headings = (0..<table.numberOfChildren(ofItem: nil)).compactMap { index -> Int? in
            guard let item = table.child(index, ofItem: nil),
                table.delegate?.outlineView?(table, isGroupItem: item) == true
            else { return nil }
            let row = table.row(forItem: item)
            return row >= 0 ? row : nil
        }
        let panels = headings.enumerated().map { index, row in
            let start = table.rect(ofRow: row).minY
            let last = index + 1 < headings.count ? headings[index + 1] - 1 : table.numberOfRows - 1
            let end = table.rect(ofRow: last).maxY
            return NSRect(
                x: table.bounds.minX + 2, y: start, width: table.bounds.width - 4, height: end - start)
        }
        func path(inset: CGFloat) -> CGPath {
            let path = CGMutablePath()
            for rect in panels where rect.height > inset * 2 {
                path.addRoundedRect(
                    in: table.convertToLayer(rect.insetBy(dx: inset, dy: inset)),
                    cornerWidth: max(0, 8 - inset), cornerHeight: max(0, 8 - inset))
            }
            return path
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.path = path(inset: 0)
        surface.path = mask.path
        border.path = path(inset: 0.5)
        highlight.path = path(inset: 1.5)
        table.effectiveAppearance.performAsCurrentDrawingAppearance {
            let dark = table.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            surface.fillColor = NSColor(white: dark ? 0.16 : 0.90, alpha: 1).cgColor
            border.strokeColor = NSColor.labelColor.withAlphaComponent(0.25).cgColor
            highlight.strokeColor = NSColor.white.withAlphaComponent(0.22).cgColor
        }
        for decoration in [surface, border, highlight] where decoration.superlayer !== layer {
            layer.addSublayer(decoration)
        }
        // Also excludes NSTableView's filler stripes below the final real row and between panels.
        layer.mask = mask
        CATransaction.commit()
    }

    func detach() {
        frameObservation?.invalidate()
        boundsObservation?.invalidate()
        frameObservation = nil
        boundsObservation = nil
        if table?.layer?.mask === mask { table?.layer?.mask = nil }
        surface.removeFromSuperlayer()
        border.removeFromSuperlayer()
        highlight.removeFromSuperlayer()
        table = nil
    }
}

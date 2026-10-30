import AppKit

@MainActor final class MenuBarTableContentClip {
    private weak var table: NSOutlineView?
    private let mask = CALayer()
    private var frameObservation: NSKeyValueObservation?
    private var boundsObservation: NSKeyValueObservation?

    func update(_ table: NSOutlineView) {
        if self.table !== table {
            detach()
            self.table = table
            mask.backgroundColor = NSColor.black.cgColor
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
        // NSTableView.h documents alternating stripes beyond the last row. Keep the separator-free
        // SwiftUI style, but clip drawing to actual rows (native-menu-design.md, 2026-10-30).
        let bottom = table.numberOfRows == 0 ? 0 : table.rect(ofRow: table.numberOfRows - 1).maxY
        let content = NSRect(x: table.bounds.minX, y: 0, width: table.bounds.width, height: bottom)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = table.convertToLayer(content)
        layer.mask = mask
        CATransaction.commit()
    }

    func detach() {
        frameObservation?.invalidate()
        boundsObservation?.invalidate()
        frameObservation = nil
        boundsObservation = nil
        if table?.layer?.mask === mask { table?.layer?.mask = nil }
        table = nil
    }
}

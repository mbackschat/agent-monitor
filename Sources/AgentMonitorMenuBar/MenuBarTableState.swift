import AgentMonitorPresentation
import AppKit
import SwiftUI

struct MenuBarTableState: NSViewRepresentable {
    let rows: [ContributorID]
    let selection: ContributorID?
    let active: Bool
    let inspecting: Bool
    let isCurrent: @MainActor () -> Bool

    func makeNSView(context: Context) -> Anchor { Anchor(contentClip: context.coordinator.contentClip) }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateNSView(_ view: Anchor, context: Context) {
        view.needsLayout = true
        context.coordinator.update(self, view: view)
    }

    static func dismantleNSView(_ view: Anchor, coordinator: Coordinator) {
        coordinator.pending?.cancel()
        coordinator.contentClip.detach()
    }

    final class Anchor: NSView {
        let contentClip: MenuBarTableContentClip

        init(contentClip: MenuBarTableContentClip) {
            self.contentClip = contentClip
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            contentClip.refresh()
        }
    }

    @MainActor final class Coordinator {
        var pending: Task<Void, Never>?
        let contentClip = MenuBarTableContentClip()
        private var rows: [ContributorID] = []
        private var selection: ContributorID?
        private var active = false
        private var inspecting = false

        func update(_ value: MenuBarTableState, view: NSView) {
            guard
                rows != value.rows || selection != value.selection || active != value.active
                    || inspecting != value.inspecting
            else { return }
            let revealSelection = value.inspecting && !inspecting
            inspecting = value.inspecting
            active = value.active
            rows = value.rows
            selection = value.selection
            pending?.cancel()
            // SwiftUI loses descendant selection on reparenting despite an unchanged binding.
            // MenuBarContributorRetentionTests covers pin/unpin and focus remaining in hidden content.
            // Run after reconciliation; never change SwiftUI rows, expansion, delegates or data sources.
            pending = Task { @MainActor [weak view] in
                // A native selection can arrive before SwiftUI cancels the previous reconciliation.
                // Never restore that stale selection over a newer choice (contributor retention tests).
                guard !Task.isCancelled, value.isCurrent(), let view else { return }
                var ancestor = view.superview
                while let parent = ancestor {
                    if let table = Self.outline(in: parent) {
                        parent.layoutSubtreeIfNeeded()
                        self.contentClip.update(table)
                        if !value.active, table.window?.firstResponder === table {
                            table.window?.makeFirstResponder(nil)
                        }
                        guard table.numberOfRows == value.rows.count,
                            let selected = value.selection,
                            let row = value.rows.firstIndex(of: selected)
                        else { return }
                        if table.selectedRow != row {
                            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                        }
                        if revealSelection {
                            table.scrollRowToVisible(row)
                            if table.rect(ofRow: row).height > table.visibleRect.height {
                                table.scroll(
                                    NSPoint(x: table.visibleRect.minX, y: table.rect(ofRow: row).minY))
                            }
                        }
                        return
                    }
                    ancestor = parent.superview
                }
            }
        }

        private static func outline(in view: NSView) -> NSOutlineView? {
            if let table = view as? NSOutlineView { return table }
            return view.subviews.lazy.compactMap { outline(in: $0) }.first
        }
    }
}

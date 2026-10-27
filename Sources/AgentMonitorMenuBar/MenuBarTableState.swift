import AgentMonitorPresentation
import AppKit
import SwiftUI

struct MenuBarTableState: NSViewRepresentable {
    let rows: [ContributorID]
    let selection: ContributorID?
    let active: Bool

    func makeNSView(context: Context) -> NSView { NSView() }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.update(self, view: view)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.pending?.cancel()
    }

    @MainActor final class Coordinator {
        var pending: Task<Void, Never>?
        private var rows: [ContributorID] = []
        private var selection: ContributorID?
        private var active = false

        func update(_ value: MenuBarTableState, view: NSView) {
            guard rows != value.rows || selection != value.selection || active != value.active else { return }
            active = value.active
            rows = value.rows
            selection = value.selection
            pending?.cancel()
            // SwiftUI loses descendant selection on reparenting despite an unchanged binding.
            // MenuBarContributorRetentionTests covers pin/unpin and focus remaining in hidden content.
            // Run after reconciliation; never change SwiftUI rows, expansion, delegates or data sources.
            pending = Task { @MainActor [weak view] in
                guard !Task.isCancelled, let view else { return }
                var ancestor = view.superview
                while let parent = ancestor {
                    if let table = Self.outline(in: parent) {
                        parent.layoutSubtreeIfNeeded()
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

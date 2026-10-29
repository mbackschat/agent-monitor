import AppKit
import SwiftUI

/// Keeps native selection/disclosure while the SwiftUI cell supplies the session surface.
struct MenuBarRowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) { view.clearRowBackground() }

    static func dismantleNSView(_ view: Anchor, coordinator: ()) {
        view.observation?.invalidate()
    }

    final class Anchor: NSView {
        var observation: NSKeyValueObservation?
        private weak var styledRow: NSTableRowView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            clearRowBackground()
        }

        override func layout() {
            super.layout()
            clearRowBackground()
        }

        func clearRowBackground() {
            var ancestor = superview
            while let view = ancestor {
                if let row = view as? NSTableRowView {
                    // NSTableRowView.h permits a custom background. SwiftUI reapplies it after
                    // cell attachment; see the SDK 27 trace in native-menu-design.md (2026-10-29).
                    if styledRow !== row {
                        observation?.invalidate()
                        styledRow = row
                        observation = row.observe(\.backgroundColor, options: [.new]) { row, change in
                            guard change.newValue?.alphaComponent != 0 else { return }
                            MainActor.assumeIsolated { row.backgroundColor = .clear }
                        }
                    }
                    if row.backgroundColor != .clear { row.backgroundColor = .clear }
                    return
                }
                ancestor = view.superview
            }
        }
    }
}

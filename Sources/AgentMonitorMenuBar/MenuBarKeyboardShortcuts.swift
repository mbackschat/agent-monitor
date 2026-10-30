import SwiftUI

struct MenuBarKeyboardShortcuts: View {
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
            shortcut("Tab / ⇧Tab", "Next / previous control")
            shortcut("↑ / ↓", "Previous / next row")
            shortcut("← / →", "Collapse / expand row")
            shortcut("⇧← / ⇧→", "Collapse / expand session groups")
            shortcut(". / u", "Pin or unpin / unpin all views")
            shortcut("i", "Contributor information")
            shortcut("v / a", "Overview / processes; show all contributors")
            shortcut("p", "Pause / resume")
            shortcut("c / m / n / o", "Sort CPU / memory / PID / stable")
            shortcut("r", "Reverse process numeric sort")
            shortcut("g", "Toggle session grouping")
            shortcut("h / t", "History metric / time range")
            shortcut("1 / 2", "CPU threshold −/+")
            shortcut("3 / 4", "Memory threshold −/+")
            shortcut("< / >", "Slower / faster acquisition maximum")
            shortcut("y", "Copy PID")
            shortcut("k", "Review termination of selected current process(es)")
            shortcut("s", "Messaging unavailable in local-only mode")
            shortcut("f", "Focus terminal (one current target)")
            shortcut("q / ⌘Q", "Quit")
        }.font(.caption)
    }

    private func shortcut(_ key: String, _ description: String) -> some View {
        GridRow {
            Text(key).fontDesign(.monospaced).fixedSize()
            Text(description).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

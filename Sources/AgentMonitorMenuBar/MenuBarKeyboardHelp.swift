import SwiftUI

struct MenuBarKeyboardHelp: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Keyboard shortcuts").font(.subheadline.bold())
                Spacer()
                Button("Hide", action: dismiss).controlSize(.small)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
                shortcut("Tab / ⇧Tab", "Next / previous control")
                shortcut("↑ / ↓", "Previous / next row")
                shortcut("← / →", "Collapse / expand row")
                shortcut(".", "Pin / unpin row")
                shortcut("p", "Pause / resume")
                shortcut("c / m / n / o", "Sort CPU / memory / PID / stable")
                shortcut("r", "Reverse sort")
                shortcut("g", "Toggle session grouping")
                shortcut("h", "History: CPU / memory / heavy count")
                shortcut("t", "History range: 10 minutes / 1 hour")
                shortcut("1 / 2", "CPU threshold −/+")
                shortcut("3 / 4", "Memory threshold −/+")
                shortcut("< / >", "Slower / faster updates")
                shortcut("y", "Copy PID")
                shortcut("k", "Review termination")
                shortcut("s", "Compose message")
                shortcut("f", "Focus terminal")
                shortcut("q / ⌘Q", "Quit")
            }.font(.caption)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func shortcut(_ key: String, _ description: String) -> some View {
        GridRow {
            Text(key).fontDesign(.monospaced).fixedSize()
            Text(description).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

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
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                shortcut("Tab / ⇧Tab", "Move between controls")
                shortcut("↑ / ↓", "Move between rows when a row is focused")
                shortcut("Return", "Expand / collapse the focused row")
                shortcut("Space", "Activate the focused button, including Pin")
                shortcut("⇧⌘P", "Pause / resume the table")
                shortcut("⌘Q", "Quit Agent Monitor")
            }.font(.caption)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .padding(12)
    }

    private func shortcut(_ key: String, _ description: String) -> some View {
        GridRow {
            Text(key).fontDesign(.monospaced).fixedSize()
            Text(description).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

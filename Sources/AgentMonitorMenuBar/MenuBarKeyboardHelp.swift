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
                shortcut("Tab / ⇧Tab · ↑/↓", "Controls · rows")
                shortcut("Return", "Expand / collapse row")
                shortcut("Space / p", "Pin row / pause")
                shortcut("c / m / n / o", "Sort CPU / memory / PID / stable")
                shortcut("r / g", "Reverse sort / grouping")
                shortcut("h / t", "History metric / range")
                shortcut("1/2 · 3/4", "CPU · memory threshold −/+")
                shortcut("< / > · y", "Slower / faster · copy PID")
                shortcut("k / s / f", "Terminate / message / terminal")
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

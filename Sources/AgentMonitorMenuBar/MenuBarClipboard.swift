import AppKit
import SwiftUI

@MainActor enum MenuBarClipboard {
    static func copy(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }
}

struct MenuBarCopyDetailsButton: View {
    let text: () -> String
    @State private var copyFailed = false

    var body: some View {
        Button("Copy all", systemImage: copyFailed ? "exclamationmark.circle" : "doc.on.doc") {
            copyFailed = !copy()
        }
        .controlSize(.small).fixedSize()
        .accessibilityLabel("Copy all details")
        .help(copyFailed ? "Copy failed; try again" : "Copy all details, including collapsed sections")
    }

    func copy(using write: @MainActor (String) -> Bool = MenuBarClipboard.copy) -> Bool {
        write(text())
    }
}

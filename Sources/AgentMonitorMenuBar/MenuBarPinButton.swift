import SwiftUI

struct MenuBarPinButton: View {
    let pinned: Bool
    let action: () -> Bool

    var body: some View {
        Button {
            _ = action()
        } label: {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .font(.system(size: 16))
                .frame(width: 32, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(pinned ? Color.accentColor : .secondary)
        .accessibilityLabel(pinned ? "Unpin" : "Pin")
        .help(
            pinned
                ? "Unpin this row (⌘P when focused)"
                : "Pin this row at the top; values stay live (⌘P when focused)")
    }
}

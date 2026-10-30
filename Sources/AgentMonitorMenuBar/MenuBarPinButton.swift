import SwiftUI

struct MenuBarPinButton: View {
    let pinned: Bool
    var shortcutAvailable = false
    let action: () -> Bool

    var body: some View {
        Button {
            _ = action()
        } label: {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .font(.system(size: 12))
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(pinned ? Color.accentColor : .secondary)
        .accessibilityLabel(pinned ? "Unpin" : "Pin")
        .help(
            (pinned ? "Unpin this row" : "Pin this row at the top; values stay live")
                + (shortcutAvailable ? " (.)" : ""))
    }
}

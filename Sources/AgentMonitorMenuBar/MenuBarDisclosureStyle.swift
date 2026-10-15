import AgentMonitorPresentation
import SwiftUI

struct MenuBarDisclosureStyle: DisclosureGroupStyle {
    let id: LiveReportRowID
    let pinned: Bool
    let focus: FocusState<LiveReportRowID?>.Binding
    let onPin: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuBarRowHeader(
                id: id, pinned: pinned, expanded: configuration.isExpanded, focus: focus,
                onToggle: { configuration.isExpanded.toggle() }, onPin: onPin,
                label: configuration.label)
            if configuration.isExpanded {
                configuration.content.padding(.leading, 16)
            }
        }
        .background(pinned ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct MenuBarRowHeader<Label: View>: View {
    let id: LiveReportRowID
    let pinned: Bool
    let expanded: Bool
    let focus: FocusState<LiveReportRowID?>.Binding
    let onToggle: () -> Void
    let onPin: () -> Void
    let label: Label
    @State private var hovered = false
    @FocusState private var pinFocused: Bool

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onToggle) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 10).accessibilityHidden(true)
                    label
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4).contentShape(Rectangle())
            }
            .buttonStyle(.plain).focused(focus, equals: id)
            .onKeyPress(.return) {
                onToggle()
                return .handled
            }
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            Button(action: onPin) {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(pinned ? Color.accentColor : .secondary)
            .opacity(pinned || hovered || pinFocused || focus.wrappedValue == id ? 1 : 0)
            .focused($pinFocused)
            .accessibilityLabel(pinned ? "Unpin" : "Pin")
            .help(pinned ? "Unpin this row" : "Pin this row at the top; values stay live")
        }
        .onHover { hovered = $0 }
    }
}

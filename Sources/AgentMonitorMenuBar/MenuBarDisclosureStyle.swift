import AgentMonitorPresentation
import SwiftUI

struct MenuBarDisclosureStyle: DisclosureGroupStyle {
    let id: LiveReportRowID
    let pinned: Bool
    let arrived: Bool
    let focus: FocusState<LiveReportRowID?>.Binding
    let onPin: () -> Bool
    let onPinShortcut: () -> Bool

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuBarRowHeader(
                id: id, pinned: pinned, expanded: configuration.isExpanded, focus: focus,
                onToggle: { configuration.isExpanded.toggle() }, onPin: onPin, onPinShortcut: onPinShortcut,
                label: configuration.label
            )
            .background(MenuBarArrivalBackground(highlighted: arrived))
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
    let onPin: () -> Bool
    let onPinShortcut: () -> Bool
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
            MenuBarPinButton(pinned: pinned, action: onPin)
                .opacity(pinned || hovered || pinFocused || focus.wrappedValue == id ? 1 : 0)
                .focused($pinFocused)
        }
        .onHover { hovered = $0 }
        .pinShortcut(onPinShortcut)
    }
}

extension View {
    func pinShortcut(_ action: @escaping () -> Bool) -> some View {
        onKeyPress(keys: ["p"], phases: .down) { key in
            guard key.modifiers == .command else { return .ignored }
            return action() ? .handled : .ignored
        }
    }
}

struct MenuBarArrivalBackground: View {
    let highlighted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.primary.opacity(highlighted ? 0.08 : 0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: highlighted)
            .accessibilityHidden(true)
    }
}

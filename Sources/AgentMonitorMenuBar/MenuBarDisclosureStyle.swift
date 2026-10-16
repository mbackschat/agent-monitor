import AgentMonitorPresentation
import SwiftUI

enum MenuBarRowDisclosure {
    case group(count: Int)
    case process

    func accessibilityValue(expanded: Bool) -> String {
        switch self {
        case .group: expanded ? "Processes shown" : "Processes hidden"
        case .process: expanded ? "Details shown" : "Details hidden"
        }
    }
}

struct MenuBarRowAccessory: View {
    let disclosure: MenuBarRowDisclosure

    var body: some View {
        Group {
            switch disclosure {
            case .group(let count):
                Text(count, format: .number.grouping(.never))
                    .font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
                    .padding(.horizontal, 4)
                    .frame(minWidth: 40, minHeight: 32)
                    .background(.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("\(count) heavy processes")
            case .process:
                Image(systemName: "info.circle")
                    .font(.system(size: 20))
                    .frame(width: 40, height: 32)
                    .accessibilityLabel("Process details")
            }
        }
        .foregroundStyle(.secondary)
    }
}

struct MenuBarDisclosureStyle: DisclosureGroupStyle {
    let id: LiveReportRowID
    let disclosure: MenuBarRowDisclosure
    let pinned: Bool
    let arrived: Bool
    let focus: FocusState<LiveReportRowID?>.Binding
    let onPin: () -> Bool
    let onPinShortcut: () -> Bool

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuBarRowHeader(
                id: id, disclosure: disclosure, pinned: pinned, expanded: configuration.isExpanded,
                focus: focus,
                onSetExpanded: { configuration.isExpanded = $0 }, onPin: onPin, onPinShortcut: onPinShortcut,
                label: configuration.label
            )
            .background(MenuBarArrivalBackground(highlighted: arrived))
            if configuration.isExpanded {
                configuration.content.padding(.leading, 24)
            }
        }
        .background(pinned ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct MenuBarRowHeader<Label: View>: View {
    let id: LiveReportRowID
    let disclosure: MenuBarRowDisclosure
    let pinned: Bool
    let expanded: Bool
    let focus: FocusState<LiveReportRowID?>.Binding
    let onSetExpanded: (Bool) -> Void
    let onPin: () -> Bool
    let onPinShortcut: () -> Bool
    let label: Label
    @State private var hovered = false
    @FocusState private var pinFocused: Bool

    var body: some View {
        HStack(spacing: 2) {
            Button(action: { onSetExpanded(!expanded) }) {
                HStack(spacing: 6) {
                    Group {
                        switch disclosure {
                        case .group:
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                        case .process:
                            Color.clear
                        }
                    }
                    .frame(width: 18, height: 32).accessibilityHidden(true)
                    label
                    MenuBarRowAccessory(disclosure: disclosure)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4).contentShape(Rectangle())
            }
            .buttonStyle(.plain).focused(focus, equals: id)
            .pinShortcut(onPinShortcut)
            .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { key in
                guard MenuBarKeyboard.accepts(key.characters, modifiers: key.modifiers) else {
                    return .ignored
                }
                onSetExpanded(key.key == .rightArrow)
                return .handled
            }
            .accessibilityValue(disclosure.accessibilityValue(expanded: expanded))
            MenuBarPinButton(pinned: pinned, action: onPin)
                .opacity(pinned || hovered || pinFocused || focus.wrappedValue == id ? 1 : 0)
                .focused($pinFocused)
                .pinShortcut(onPinShortcut)
        }
        .onHover { hovered = $0 }
    }
}

extension View {
    func pinShortcut(_ action: @escaping () -> Bool) -> some View {
        onKeyPress(keys: [KeyEquivalent(Character(ReportShortcut.pin.rawValue))], phases: .down) { key in
            guard MenuBarKeyboard.accepts(key.characters, modifiers: key.modifiers) else { return .ignored }
            return action() ? .handled : .ignored
        }
    }
}

struct MenuBarArrivalBackground: View {
    let highlighted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.primary.opacity(highlighted ? 0.16 : 0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: highlighted)
            .accessibilityHidden(true)
    }
}

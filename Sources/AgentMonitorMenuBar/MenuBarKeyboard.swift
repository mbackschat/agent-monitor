import AgentMonitorPresentation
import AppKit
import SwiftUI

enum MenuBarKeyboard {
    static let keys = Set(
        (ReportShortcut.allCases.map(\.rawValue) + ["k", "s", "f", "y", "q", "i", "?"])
            .map { KeyEquivalent(Character($0)) })

    static func isBulkDisclosure(modifiers: EventModifiers) -> Bool {
        modifiers.intersection([.command, .control, .option, .shift]) == .shift
    }

    static func accepts(_ key: String, modifiers: EventModifiers) -> Bool {
        // AppKit marks arrow keys as numericPad; Caps Lock also is not a shortcut chord.
        // https://developer.apple.com/documentation/appkit/nsevent/modifierflags-swift.struct/numericpad
        let chord = modifiers.intersection([.command, .control, .option, .shift])
        return chord.isEmpty || (chord == .shift && (key == "<" || key == ">" || key == "?"))
    }
}

extension MenuBarModel {
    func pidToCopy(for row: LiveReportRowID) -> String? {
        guard isOpen, isReportUnobstructed, rowIndex.visible.contains(row),
            case .process(let identity) = row,
            rowIndex.processes[identity] != nil
        else { return nil }
        return String(identity.pid)
    }

    @discardableResult
    func copyPID(row: LiveReportRowID, using write: @MainActor (String) -> Bool = MenuBarClipboard.copy)
        -> Bool
    {
        guard let pid = pidToCopy(for: row) else { return false }
        return write(pid)
    }

    @discardableResult
    func handleShortcut(
        _ key: String, row: LiveReportRowID?,
        writeClipboard: @MainActor (String) -> Bool = MenuBarClipboard.copy
    ) -> Bool {
        guard isOpen, isReportUnobstructed else { return false }
        if key == "?" {
            referencePage = .keyboard
            return true
        }
        guard referencePage == nil else { return false }
        if key == "i", report.showsOverview, report.overview.selection != nil {
            report.overview.toggleDetails()
            return true
        }
        if let shortcut = ReportShortcut(rawValue: key) {
            switch shortcut {
            case .pause:
                guard report.snapshot != nil else { return false }
                toggleFreeze()
            case .pin:
                if report.showsOverview {
                    return report.overview.togglePin()
                }
                guard let row else { return false }
                return togglePin(row)
            default:
                let previousInterval = report.interval
                report.apply(shortcut)
                if report.interval != previousInterval { setInterval(report.interval) }
            }
            return true
        }
        if report.showsOverview {
            guard let contributor = report.overview.selection else { return false }
            if report.overview.detailsVisible, report.overview.inspectedProcess != nil {
                guard let process = report.contributorProcessTarget else { return false }
                let kind: ProcessActionKind
                switch key {
                case "k": kind = .terminate
                case "f": kind = .focus
                default: return false
                }
                guard canBegin(kind, contributor: contributor, process: process.process) else { return false }
                begin(kind, contributor: contributor, process: process.process)
                return true
            }
            if key == "k", canBeginContributorTermination(contributor) {
                beginContributorTermination(contributor)
                return true
            }
            let targets = report.contributorProcesses(for: contributor)
            guard key == "f", targets.count == 1, let process = targets.first,
                canBegin(.focus, contributor: contributor, process: process.process)
            else { return false }
            begin(.focus, contributor: contributor, process: process.process)
            return true
        }
        guard let row else { return false }
        let kind: ProcessActionKind
        switch key {
        case "y": return copyPID(row: row, using: writeClipboard)
        case "k": kind = .terminate
        case "s": kind = .message
        case "f": kind = .focus
        default: return false
        }
        guard canBegin(kind, row: row) else { return false }
        begin(kind, row: row)
        return true
    }
}

// SwiftUI onKeyPress depends on focus; unmodified keyboardShortcut intercepts editor input.
// The native focus/editor regression in MenuBarKeyboardTests verifies this window-local route.
struct MenuBarKeyboardCommands: NSViewRepresentable {
    let perform: (String) -> Bool

    func makeNSView(context: Context) -> CommandView {
        let view = CommandView()
        view.perform = perform
        return view
    }

    func updateNSView(_ view: CommandView, context: Context) {
        view.perform = perform
    }

    final class CommandView: NSView {
        var perform: (String) -> Bool = { _ in false }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard event.type == .keyDown, let window, event.window === window,
                window.attachedSheet == nil,
                let key = event.characters, key.count == 1,
                MenuBarKeyboard.keys.contains(KeyEquivalent(Character(key)))
            else { return false }
            if let editor = window.firstResponder as? NSTextView, editor.isEditable { return false }
            if let field = window.firstResponder as? NSTextField, field.isEditable { return false }
            var modifiers: EventModifiers = []
            if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
            if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
            if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
            if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
            guard MenuBarKeyboard.accepts(key, modifiers: modifiers) else { return false }
            return perform(key)
        }
    }
}

import AgentMonitorPresentation
import SwiftUI

enum MenuBarKeyboard {
    static let keys = Set(
        (ReportShortcut.allCases.map(\.rawValue) + ["k", "s", "f", "y", "q"])
            .map { KeyEquivalent(Character($0)) })

    static func accepts(_ key: String, modifiers: EventModifiers) -> Bool {
        // AppKit marks arrow keys as numericPad; Caps Lock also is not a shortcut chord.
        // https://developer.apple.com/documentation/appkit/nsevent/modifierflags-swift.struct/numericpad
        let chord = modifiers.intersection([.command, .control, .option, .shift])
        return chord.isEmpty || (chord == .shift && (key == "<" || key == ">"))
    }
}

extension MenuBarModel {
    func pidToCopy(for row: LiveReportRowID) -> String? {
        guard isOpen, report.actionPanel == nil, visibleRowIDs.contains(row),
            case .process(let identity) = row,
            report.rows.contains(where: { $0.process == identity })
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
        guard isOpen, report.actionPanel == nil else { return false }
        if let shortcut = ReportShortcut(rawValue: key) {
            switch shortcut {
            case .pause:
                guard report.snapshot != nil else { return false }
                toggleFreeze()
            case .pin:
                guard let row else { return false }
                return togglePin(row)
            default:
                let previousInterval = report.interval
                report.apply(shortcut)
                if report.interval != previousInterval { setInterval(report.interval) }
            }
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

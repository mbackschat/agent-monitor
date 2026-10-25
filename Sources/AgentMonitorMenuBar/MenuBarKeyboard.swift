import AgentMonitorPresentation
import SwiftUI

enum MenuBarKeyboard {
    static let keys = Set(
        (ReportShortcut.allCases.map(\.rawValue) + ["k", "s", "f", "y", "q", "i"])
            .map { KeyEquivalent(Character($0)) })

    static func isBulkDisclosure(modifiers: EventModifiers) -> Bool {
        modifiers.intersection([.command, .control, .option, .shift]) == .shift
    }

    static func accepts(_ key: String, modifiers: EventModifiers) -> Bool {
        // AppKit marks arrow keys as numericPad; Caps Lock also is not a shortcut chord.
        // https://developer.apple.com/documentation/appkit/nsevent/modifierflags-swift.struct/numericpad
        let chord = modifiers.intersection([.command, .control, .option, .shift])
        return chord.isEmpty || (chord == .shift && (key == "<" || key == ">"))
    }
}

extension MenuBarModel {
    @discardableResult
    func handleOverviewArrow(_ key: KeyEquivalent, focus: MenuBarFocus?, modifiers: EventModifiers = [])
        -> Bool
    {
        guard isOpen, report.showsOverview, !report.overview.detailsVisible, !diagnosis.state.isVisible,
            report.actionPanel == nil, focus != nil,
            MenuBarKeyboard.accepts(String(key.character), modifiers: modifiers)
        else { return false }
        if case .contributor(let id) = focus { report.overview.select(id) }
        switch key {
        case .upArrow: report.overview.move(by: -1)
        case .downArrow: report.overview.move(by: 1)
        case .leftArrow: report.overview.disclose(false)
        case .rightArrow: report.overview.disclose(true)
        default: return false
        }
        return true
    }

    func pidToCopy(for row: LiveReportRowID) -> String? {
        guard isOpen, !diagnosis.state.isVisible, report.actionPanel == nil, rowIndex.visible.contains(row),
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
        _ key: String, row: LiveReportRowID?, focus: MenuBarFocus? = nil,
        writeClipboard: @MainActor (String) -> Bool = MenuBarClipboard.copy
    ) -> Bool {
        guard isOpen, !diagnosis.state.isVisible, report.actionPanel == nil else { return false }
        if report.showsOverview, key == "i" || key == ReportShortcut.pin.rawValue,
            case .contributor(let id) = focus
        {
            guard report.overview.visibleRows.contains(where: { $0.id == id }) else { return false }
            report.overview.select(id)
        }
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
                    report.overview.togglePin()
                    return true
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
        guard !report.showsOverview, let row else { return false }
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

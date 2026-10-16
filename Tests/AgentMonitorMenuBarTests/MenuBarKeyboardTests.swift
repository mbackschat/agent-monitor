import AgentMonitorCore
import AgentMonitorPresentation
import SwiftUI
import Testing

@testable import AgentMonitorMenuBar

@Test @MainActor func copyPIDUsesOnlyTheExactVisibleProcessAndPlainDigits() async throws {
    let snapshot = try menuBarFixture(pids: [42001, 42002])
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let group = try #require(model.report.groups.first)
    let child = LiveReportRowID.process(group.processes[0].process)
    #expect(model.pidToCopy(for: .group(group.id)) == nil)
    #expect(model.pidToCopy(for: child) == nil)
    model.report.toggleDisclosure()
    var copied = ""
    let copiedPID = model.copyPID(
        row: child,
        using: {
            copied = $0
            return true
        })
    #expect(copiedPID)
    #expect(copied == "42001")
    #expect(model.pidToCopy(for: .process(ProcessIdentity(pid: 42001, startMicroseconds: 2))) == nil)
    model.begin(.terminate, row: child)
    #expect(model.pidToCopy(for: child) == nil)
    model.input(.escape)
    model.togglePin(child)
    model.report.receive(try menuBarFixture(pids: []))
    #expect(model.pidToCopy(for: child) == nil)
    model.close()
    #expect(model.pidToCopy(for: child) == nil)
    await model.stop()
}

@Test @MainActor func nativeSingleKeysMatchTUIAndDoNotActInsideActionPanels() async throws {
    let snapshot = try menuBarFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let row = try #require(model.visibleRowIDs.first)
    #expect(model.handleShortcut("p", row: row))
    #expect(model.report.frozen)
    #expect(model.handleShortcut("p", row: row))
    #expect(!model.report.frozen)
    #expect(!model.handleShortcut(" ", row: row))
    #expect(!model.handleShortcut("\r", row: row))
    #expect(model.handleShortcut(".", row: row))
    #expect(model.report.isPinned(row))
    #expect(model.handleShortcut(".", row: row))
    #expect(!model.report.isPinned(row))
    for (key, sort) in [("c", ReportSort.cpu), ("m", .memory), ("n", .pid), ("o", .stable)] {
        #expect(model.handleShortcut(key, row: row))
        #expect(model.report.sortKey == sort)
    }
    #expect(model.handleShortcut("h", row: row))
    #expect(model.report.historyMetric == .memory)
    #expect(model.handleShortcut("t", row: row))
    #expect(model.report.historyWindow == .oneHour)
    #expect(model.handleShortcut("<", row: row))
    #expect(model.report.interval == 10)
    #expect(model.handleShortcut(">", row: row))
    #expect(model.report.interval == 5)
    var clipboard = ""
    let copied = model.handleShortcut(
        "y", row: row,
        writeClipboard: {
            clipboard = $0
            return true
        })
    #expect(copied)
    #expect(clipboard == "42001")
    #expect(model.handleShortcut("k", row: row))
    let held = model.report
    for key in [
        "p", ".", "c", "m", "n", "o", "r", "g", "h", "t", "1", "2", "3", "4", "<", ">", "y", "k", "s", "f",
    ] {
        #expect(!model.handleShortcut(key, row: row))
        #expect(model.report == held)
    }
    model.input(.escape)
    model.close()
    #expect(!model.handleShortcut("p", row: row))
    await model.stop()
}

@Test(arguments: [EventModifiers.command, .control, .option, [.command, .shift]])
func nativeBrowsingKeysRejectModifiedText(modifiers: EventModifiers) {
    #expect(!MenuBarKeyboard.accepts("p", modifiers: modifiers))
    #expect(!MenuBarKeyboard.accepts(".", modifiers: modifiers))
}

@Test func nativeBrowsingKeysAllowOnlyUnmodifiedKeysAndShiftedAngleBrackets() {
    #expect(MenuBarKeyboard.keys.contains("."))
    #expect(!MenuBarKeyboard.keys.contains(.space))
    #expect(!MenuBarKeyboard.keys.contains(.return))
    #expect(MenuBarKeyboard.accepts("p", modifiers: []))
    #expect(MenuBarKeyboard.accepts(".", modifiers: []))
    #expect(MenuBarKeyboard.accepts("<", modifiers: .shift))
    #expect(!MenuBarKeyboard.accepts("P", modifiers: .shift))
}

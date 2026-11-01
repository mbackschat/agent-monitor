import AgentMonitorCore
import AgentMonitorPresentation
import AppKit
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
    #expect(model.report.interval == 0.25)
    #expect(model.handleShortcut(">", row: row))
    #expect(model.report.interval == 0.1)
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

@Test func nativeBrowsingKeysAllowUnmodifiedKeysAndShiftedPunctuation() {
    #expect(MenuBarKeyboard.keys.contains("."))
    #expect(!MenuBarKeyboard.keys.contains(.space))
    #expect(!MenuBarKeyboard.keys.contains(.return))
    #expect(MenuBarKeyboard.accepts("p", modifiers: []))
    #expect(MenuBarKeyboard.accepts(".", modifiers: []))
    #expect(MenuBarKeyboard.accepts("<", modifiers: .shift))
    #expect(MenuBarKeyboard.keys.contains("?"))
    #expect(MenuBarKeyboard.accepts("?", modifiers: .shift))
    #expect(!MenuBarKeyboard.accepts("P", modifiers: .shift))
}

@Test(arguments: [EventModifiers(), .numericPad, .capsLock, [.numericPad, .capsLock]])
func nativeRowArrowsAcceptNonShortcutFlags(modifiers: EventModifiers) {
    for key in ["\u{F702}", "\u{F703}"] {
        #expect(MenuBarKeyboard.accepts(key, modifiers: modifiers))
        for chord in [EventModifiers.command, .control, .option, .shift] {
            #expect(!MenuBarKeyboard.accepts(key, modifiers: modifiers.union(chord)))
        }
    }
}

@Test func nativePinShortcutIgnoresCapsLockState() {
    #expect(MenuBarKeyboard.accepts(".", modifiers: .capsLock))
    #expect(!MenuBarKeyboard.accepts(".", modifiers: [.capsLock, .command]))
}

@Test func initialNativeFocusWaitsForRowsOnlyWhileTheTableRetainsFocus() {
    let row = LiveReportRowID.process(ProcessIdentity(pid: 42, startMicroseconds: 1))
    var focus = MenuBarInitialFocus()
    let loading = focus.open(rows: [])
    #expect(loading == .table)
    let empty = focus.rowsChanged([], focus: .table)
    #expect(empty == nil)
    let arrived = focus.rowsChanged([row], focus: .table)
    #expect(arrived == row)
    let refresh = focus.rowsChanged([row], focus: nil)
    #expect(refresh == nil)
    let reopened = focus.open(rows: [])
    #expect(reopened == .table)
    let departed = focus.rowsChanged([row], focus: nil)
    #expect(departed == nil)
    let laterRefresh = focus.rowsChanged([row], focus: .table)
    #expect(laterRefresh == nil)
    let populated = focus.open(rows: [row])
    #expect(populated == .row(row))
    let alreadyFocused = focus.rowsChanged([row], focus: .table)
    #expect(alreadyFocused == nil)
}

@Test func nativeBulkDisclosureAcceptsOnlyShiftArrowsAndKeyStateFlags() {
    #expect(MenuBarKeyboard.isBulkDisclosure(modifiers: .shift))
    #expect(MenuBarKeyboard.isBulkDisclosure(modifiers: [.shift, .numericPad, .capsLock]))
    for modifiers in [
        EventModifiers(), .numericPad, [.shift, .command], [.shift, .option], [.shift, .control],
    ] {
        #expect(!MenuBarKeyboard.isBulkDisclosure(modifiers: modifiers))
    }
}

@Test func returningNativeTableRestoresExactSelectionOrFallsBackToVisibleContent() {
    let first = LiveReportRowID.process(ProcessIdentity(pid: 41, startMicroseconds: 1))
    let selected = LiveReportRowID.process(ProcessIdentity(pid: 42, startMicroseconds: 1))
    let reused = LiveReportRowID.process(ProcessIdentity(pid: 42, startMicroseconds: 2))
    var focus = MenuBarInitialFocus()
    #expect(focus.open(rows: [first, selected], preferred: selected) == .row(selected))
    #expect(focus.open(rows: [first, reused], preferred: selected) == .row(first))
    #expect(focus.open(rows: [], preferred: selected) == .table)
    #expect(focus.rowsChanged([first], focus: .table) == first)
    #expect(focus.open(rows: [first], preferred: nil) == .row(first))
}

@Test @MainActor func questionMarkOpensShortcutsWithoutChangingSelectedContributor() async throws {
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let selected = try #require(model.report.overview.visibleRows.first?.id)
    model.report.overview.select(selected)
    #expect(model.availableKeyboardShortcuts.contains { $0.key == "i" })
    #expect(!model.availableKeyboardShortcuts.contains { $0.key == "n" || $0.key == "s" || $0.key == "y" })
    let before = model.report
    #expect(model.handleShortcut("?", row: nil))
    #expect(model.referencePage == .keyboard)
    #expect(model.report == before)
    #expect(!model.handleShortcut("p", row: nil))
    #expect(model.report == before)
    model.referencePage = nil
    #expect(model.report.overview.selection == selected)
    let past = try #require(model.report.overview.nodes.values.first { $0.stats.isNoLongerObserved })
    model.report.overview.select(past.id)
    #expect(!model.availableKeyboardShortcuts.contains { $0.key == "k" || $0.key == "f" })
    model.report.view = .processes
    let row = try #require(model.visibleRowIDs.first)
    model.selectRow(row)
    #expect(model.availableKeyboardShortcuts.contains { $0.key == "n" })
    #expect(model.handleShortcut("?", row: row))
    #expect(model.referencePage == .keyboard)
    await model.stop()
}

@Test @MainActor func reportShortcutsWorkAcrossFocusedControlsAndRespectEditors() async throws {
    try #require(
        NSApplication.shared.isFullKeyboardAccessEnabled,
        "Enable Keyboard navigation in System Settings > Keyboard")
    let snapshot = try nativeOverviewFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let host = NSHostingView(rootView: MenuBarView(model: model))
    host.frame = NSRect(x: 0, y: 0, width: 620, height: 560)
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    func settle() async {
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }
    }
    func send(_ text: String, modifiers: NSEvent.ModifierFlags = []) throws -> Bool {
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: text,
                charactersIgnoringModifiers: text, isARepeat: false, keyCode: 0))
        return window.performKeyEquivalent(with: event)
    }
    model.report.overview.toggleTable()
    await settle()
    #expect(window.firstResponder !== contributorOutline(in: host))
    try #require(try send("8"))
    #expect(!model.report.overview.tableCollapsed)
    await settle()
    let options = try #require(shortcutOptions(in: host))
    #expect(window.makeFirstResponder(options))
    #expect(try send("p"))
    #expect(model.report.frozen)
    #expect(try send("6"))
    #expect(model.report.overview.collapsedSections.contains(.sessions))
    #expect(try send("6"))
    #expect(!model.report.overview.collapsedSections.contains(.sessions))
    let contributor = try #require(model.report.overview.visibleRows.first?.id)
    model.report.overview.select(contributor)
    try #require(try send("i"))
    await settle()
    #expect(window.makeFirstResponder(options))
    #expect(try send("\u{1b}"))
    #expect(!model.report.overview.detailsVisible)
    let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 80, height: 20))
    editor.isEditable = true
    host.addSubview(editor)
    #expect(window.makeFirstResponder(editor))
    let beforeEditing = model.report
    for key in ["8", "6", "p", "c", ".", "k", "q", "?"] {
        _ = try send(key)
    }
    #expect(model.report == beforeEditing)
    #expect(model.referencePage == nil)
    #expect(model.report.frozen)
    editor.removeFromSuperview()
    #expect(window.makeFirstResponder(options))
    for modifiers in [NSEvent.ModifierFlags.command, .control, .option, .shift] {
        #expect(!(try send("p", modifiers: modifiers)))
    }
    for key in [" ", "\r", "\u{F702}", "\u{F703}"] {
        #expect(!(try send(key)))
    }
    #expect(try send("?", modifiers: .shift))
    #expect(model.referencePage == .keyboard)
    await settle()
    #expect(!(try send("p")))
    #expect(model.report.frozen)
    model.referencePage = nil
    await settle()
    try #require(try send("v"))
    await settle()
    let row = try #require(model.report.selection)
    try #require(try send("."))
    #expect(model.report.isPinned(row))
    await settle()
    try #require(try send("."))
    #expect(!model.report.isPinned(row))
    await settle()
    try #require(try send("k"))
    #expect(model.report.actionPanel != nil)
    await settle()
    for key in ["p", "v", "8", ".", "k", "q", "?"] {
        #expect(!(try send(key)))
    }
    model.input(.escape)
    model.close()
    #expect(!(try send("8")))
    await model.stop()
}

@MainActor private func shortcutOptions(in view: NSView) -> NSPopUpButton? {
    if let button = view as? NSPopUpButton, button.menu?.title == "View options" { return button }
    return view.subviews.lazy.compactMap { shortcutOptions(in: $0) }.first
}

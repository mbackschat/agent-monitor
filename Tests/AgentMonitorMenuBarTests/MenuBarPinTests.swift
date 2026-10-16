import AgentMonitorCore
import AgentMonitorPresentation
import Testing

@testable import AgentMonitorMenuBar

@Test @MainActor func nativePinCommandRequiresTheExactVisibleRowAndAllowsMissingPinRemoval() async throws {
    let snapshot = try menuBarFixture(pids: [42001, 42002])
    let model = MenuBarModel { _, _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let group = try #require(model.report.groups.first)
    let child = LiveReportRowID.process(group.processes[0].process)
    #expect(!model.togglePin(child))
    #expect(model.togglePin(.group(group.id)))
    #expect(model.report.isPinned(.group(group.id)))
    #expect(model.togglePin(.group(group.id)))
    #expect(!model.report.isPinned(.group(group.id)))
    model.report.toggleDisclosure()
    #expect(model.togglePin(child))
    model.begin(.terminate, row: child)
    #expect(model.report.actionPanel != nil)
    #expect(!model.togglePin(child))
    model.input(.escape)
    model.report.receive(try menuBarFixture(pids: []))
    #expect(model.togglePin(child))
    #expect(!model.report.isPinned(child))
    #expect(!model.togglePin(child))
    model.close()
    #expect(!model.togglePin(.group(group.id)))
    await model.stop()
}

@Test func pinnedGroupsAndChildrenNeverDuplicateRowsOrInflateTotals() throws {
    let snapshot = try menuBarFixture(pids: [42001, 42002])
    var state = LiveReportState(grouping: .session)
    state.receive(snapshot)
    let group = try #require(state.groups.first)
    let process = try #require(group.processes.first)
    state.toggleDisclosure()
    state.togglePin(.group(group.id))
    state.togglePin(.process(process.process))
    #expect(state.visibleRows.count == 3)
    #expect(Set(state.visibleRows.map(\.id)).count == 3)
    #expect(state.groups.first?.cpuTotal == 369.2)
    state.toggleGrouping()
    #expect(state.pinnedRows.map(\.id) == [.group(group.id), .process(process.process)])
    #expect(Set(state.visibleRows.map(\.id)).count == state.visibleRows.count)
    #expect(state.unpinnedRows.isEmpty)
    state.togglePin(.group(group.id))
    #expect(state.unpinnedRows.count == 1)
}

@Test @MainActor func reopeningPreservesPinsAndOptionsButClearsDisplayedSamples() async throws {
    let snapshot = try menuBarFixture()
    let model = MenuBarModel { _, _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let row = try #require(snapshot.findings.first)
    model.report.togglePin(.process(row.process))
    model.report.adjustThreshold(.cpuUp)
    model.report.sort(by: .memory)
    model.report.reverseSort()
    model.report.toggleGrouping()
    model.toggleFreeze()
    model.close()
    #expect(model.report.snapshot == nil)
    #expect(model.report.pins.count == 1)
    model.open()
    #expect(!model.report.frozen)
    #expect(model.report.thresholds.cpuPercent == 35)
    #expect(model.report.sortKey == .memory)
    #expect(model.report.ascending)
    #expect(model.report.grouping == .none)
    await model.waitForCollection()
    #expect(model.report.pinnedRows == [.process(row)])
    await model.stop()
}

@Test @MainActor func nativeFocusTracksFlattenedRowsPinsAndDetails() async throws {
    let snapshot = try menuBarFixture(pids: [42001, 42002])
    let model = MenuBarModel { _, _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let group = try #require(model.report.groups.first)
    let first = group.processes[0].process
    let second = group.processes[1].process
    #expect(model.visibleRowIDs == [.group(group.id)])
    model.report.toggleDisclosure()
    #expect(model.moveFocus(from: .group(group.id), by: 1) == .process(first))
    model.setDetails(for: first, expanded: true)
    #expect(model.report.expanded == first)
    model.setDetails(for: first, expanded: true)
    #expect(model.report.detailsMode == .split)
    model.setDetails(for: first, expanded: false)
    model.setDetails(for: first, expanded: false)
    #expect(model.report.detailsMode == .minimized)
    model.report.togglePin(.process(second))
    #expect(model.visibleRowIDs == [.process(second), .group(group.id), .process(first)])
    model.setDetails(for: second, expanded: true)
    #expect(model.report.expanded == second)
    #expect(model.report.detailsMode == .split)
    model.report.toggleGrouping()
    #expect(model.visibleRowIDs == [.process(second), .process(first)])
    model.setDetails(for: first, expanded: true)
    #expect(model.report.expanded == first)
    await model.stop()
}

@Test func pinnedSessionKeepsItsIdentityThroughSingletonAndMissingSamples() throws {
    var state = LiveReportState(grouping: .session)
    state.receive(try menuBarFixture(pids: [42001, 42002]))
    let group = try #require(state.groups.first)
    state.togglePin(.group(group.id))
    state.toggleDisclosure()
    state.receive(try menuBarFixture(pids: [42002], cpu: 42))
    guard case .group(let singleton) = state.pinnedRows.first else {
        Issue.record("Lost session pin")
        return
    }
    #expect(singleton.id == group.id)
    #expect(singleton.processes.count == 1)
    #expect(singleton.cpuTotal == 42)
    state.receive(try menuBarFixture(pids: []))
    guard case .unavailable = state.pinnedRows.first else {
        Issue.record("Lost placeholder")
        return
    }
    #expect(state.beginAction(.focus) == nil)
    #expect(state.actionPanel == nil)
    state.receive(try menuBarFixture(pids: [42003, 42004]))
    #expect(state.pinnedRows.first?.id == .group(group.id))
    #expect(state.visibleRows.count == 3)
}

@Test @MainActor func nativeGroupAndProcessDisclosureReturnAfterFiltering() async throws {
    let snapshot = try menuBarFixture(pids: [42001, 42002])
    let model = MenuBarModel { _, _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let group = try #require(model.report.groups.first)
    let process = try #require(group.processes.first).process
    model.report.setDisclosure(expanded: true)
    model.setDetails(for: process, expanded: true)
    model.report.receive(try menuBarFixture(pids: []))
    #expect(model.visibleRowIDs.isEmpty)
    #expect(model.report.expanded == nil)
    model.report.receive(snapshot)
    #expect(model.report.openGroups.contains(group.id))
    #expect(model.visibleRowIDs.contains(.process(process)))
    #expect(model.report.expanded == process)
    #expect(model.report.detailsMode == .split)
    await model.stop()
}

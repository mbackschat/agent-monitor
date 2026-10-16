import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore

@Test(arguments: [ReportGrouping.none, .session])
func directionalDisclosureIsIdempotent(grouping: ReportGrouping) throws {
    var state = LiveReportState(grouping: grouping)
    state.receive(liveSnapshot([liveRow(20)]))
    let selection = try #require(state.selection)
    state.setDisclosure(expanded: true)
    switch selection {
    case .group(let group): #expect(state.openGroups.contains(group))
    case .process(let process):
        #expect(state.expanded == process)
        #expect(state.detailsMode == .split)
        state.maximizeDetails()
    }
    let opened = state
    state.setDisclosure(expanded: true)
    #expect(state == opened)
    state.setDisclosure(expanded: false)
    switch selection {
    case .group(let group): #expect(!state.openGroups.contains(group))
    case .process: #expect(state.detailsMode == .minimized)
    }
    let closed = state
    state.setDisclosure(expanded: false)
    #expect(state == closed)
}

@Test func sortingKeepsSelectionAndDisclosureOnTheSameProcessLifetime() {
    var state = LiveReportState()
    let first = liveRow(20, cpu: 90, memory: 1)
    let second = liveRow(10, cpu: 30, memory: 2)
    state.receive(liveSnapshot([second, first]))
    #expect(state.rows.map(\.process.pid) == [20, 10])
    state.toggleDisclosure()
    state.sort(by: .pid)
    #expect(state.rows.map(\.process.pid) == [10, 20])
    #expect(state.selected == first.process)
    #expect(state.expanded == first.process)
    state.receive(liveSnapshot([liveRow(20, cpu: 1, memory: 1), second]))
    #expect(state.expanded == first.process)
    state.sort(by: .memory)
    #expect(state.rows.map(\.process.pid) == [10, 20])
    state.reverseSort()
    #expect(state.rows.map(\.process.pid) == [20, 10])
}

@Test func pidReuseClearsDisclosureAndReportsDisappearance() {
    var state = LiveReportState()
    state.receive(liveSnapshot([liveRow(20)]))
    state.toggleDisclosure()
    state.receive(liveSnapshot([liveRow(20, start: 2)]))
    #expect(state.expanded == nil)
    #expect(state.selected?.startMicroseconds == 2)
    #expect(state.notice?.contains("left") == true)
}

@Test func equalResourcesUseLifetimeOrderAndUnavailableValuesStayLast() {
    var state = LiveReportState()
    state.receive(liveSnapshot([liveRow(30, cpu: nil), liveRow(20), liveRow(10)]))
    #expect(state.rows.map(\.process.pid) == [10, 20, 30])
    state.reverseSort()
    #expect(state.rows.map(\.process.pid) == [10, 20, 30])
    state.moveSelection(by: 2)
    #expect(state.selected?.pid == 30)
    state.moveSelection(by: 200)
    #expect(state.selected?.pid == 30)
}

@Test func compactLayoutKeepsSelectionVisibleAndDisclosesUncertaintyWithoutEscapes() {
    var state = LiveReportState()
    state.receive(liveSnapshot((1...20).map { liveRow(Int32($0)) }))
    state.moveSelection(by: 19)
    var lines = LiveReportLayout.lines(state: state, width: 60, height: 12)
    #expect(lines.count <= 12)
    #expect(lines.contains { $0.text.contains(">") && $0.text.contains("20") })
    state.toggleDisclosure()
    lines = LiveReportLayout.lines(state: state, width: 60, height: 24)
    #expect(lines.contains { $0.text.contains("unresolved") })
    #expect(lines.contains { $0.text.contains("unknown") })
    #expect(lines.allSatisfy { !$0.text.contains("\u{1b}") })
    #expect(LiveReportLayout.lines(state: state, width: 15, height: 3).count <= 3)
}

private func liveRow(
    _ pid: Int32, start: UInt64 = 1, cpu: Double? = 50, memory: UInt64 = 1, name: String = "worker"
) -> HeavyProcess {
    let identity = ProcessIdentity(pid: pid, startMicroseconds: start)
    return HeavyProcess(
        process: identity, executable: "/bin/worker", name: name, cpuPercent: cpu,
        footprintBytes: memory, cwd: "/project", command: nil, metadataStatus: .notObserved,
        attribution: Attribution(
            provider: .codex, evidence: .unknown, context: .unverified,
            threadID: nil, rootSessionID: nil, runtime: nil, terminal: nil, runtimeDirectory: nil,
            candidateThreadIDs: [], ancestry: [identity]))
}

private func liveSnapshot(_ rows: [HeavyProcess]) -> MonitoringSnapshot {
    MonitoringSnapshot(
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1,
        cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
        sampledProcessCount: rows.count, unreadableProcessCount: 0, findings: rows)
}

@Test func compactLayoutMarksExceededMetricsAndFitsTheSmallestSupportedViewport() {
    var state = LiveReportState()
    state.receive(liveSnapshot([liveRow(42, cpu: 50, memory: 1_200_000_000)]))
    var lines = LiveReportLayout.lines(state: state, width: 60, height: 12)
    #expect(lines.contains { $0.text.contains("50.00*") && $0.text.contains("1.20*") })
    state.toggleDisclosure()
    lines = LiveReportLayout.lines(state: state, width: 40, height: 8)
    #expect(lines.count <= 8)
    #expect(lines.allSatisfy { $0.text.count <= 40 })
    #expect(lines.last?.text.contains("q/Ctrl-C") == true)
}

@Test func disclosureScrollClampsAtTheEndAndRecoversAfterResize() {
    var state = LiveReportState()
    state.receive(liveSnapshot([liveRow(42)]))
    state.toggleDisclosure()
    state.scrollDetails(by: 100, maximum: 4)
    #expect(state.detailOffset == 4)
    state.scrollDetails(by: -1, maximum: 4)
    #expect(state.detailOffset == 3)
    state.scrollDetails(by: -1, maximum: 2)
    #expect(state.detailOffset == 1)
    state.scrollDetails(by: -100, maximum: 2)
    #expect(state.detailOffset == 0)
}

@Test(arguments: [60, 85, 100, 120, 160, 200])
func tableColumnsAlignWithHeadersAndReserveThresholdMarkers(width: Int) throws {
    var state = LiveReportState()
    state.receive(
        liveSnapshot([
            liveRow(38794, cpu: 189.90, memory: 1_020_000_000),
            liveRow(7, cpu: 2.5, memory: 900_000_000),
            liveRow(123456, cpu: nil, memory: 12_340_000_000),
        ]))
    let lines = LiveReportLayout.lines(state: state, width: width, height: 24)
    let header = try #require(lines.first { $0.text.contains("PROCESS") }).text
    let processColumn = try #require(header.range(of: "PROCESS")).lowerBound.utf16Offset(in: header)
    let rows = lines.filter { $0.style == .selected || $0.style == .heavy }.map(\.text)
    for row in rows {
        #expect(row.range(of: "worker")?.lowerBound.utf16Offset(in: row) == processColumn)
        if width >= 85 {
            let agentColumn = try #require(header.range(of: "AGENT")).lowerBound.utf16Offset(in: header)
            let terminalColumn = try #require(header.range(of: "TTY")).lowerBound.utf16Offset(in: header)
            #expect(row.range(of: "codex/")?.lowerBound.utf16Offset(in: row) == agentColumn)
            #expect(row.range(of: "no tty")?.lowerBound.utf16Offset(in: row) == terminalColumn)
        }
    }
    let high = try #require(rows.first { $0.contains("189.90*") })
    let low = try #require(rows.first { $0.contains("2.50") })
    #expect(
        high.range(of: "189.90")?.upperBound.utf16Offset(in: high)
            == low.range(of: "2.50")?.upperBound.utf16Offset(in: low))
    #expect(
        high.range(of: "1.02")?.upperBound.utf16Offset(in: high)
            == low.range(of: "0.90")?.upperBound.utf16Offset(in: low))
}

@Test(arguments: [60, 100, 120, 160, 200])
func detailsSplitStaysFixedAcrossRefreshSelectionAndDisappearance(width: Int) throws {
    var state = LiveReportState()
    state.receive(liveSnapshot([liveRow(1)]))
    state.toggleDisclosure()
    let first = LiveReportLayout.lines(state: state, width: width, height: 24)
    let divider = try #require(first.firstIndex { $0.style == .separator })
    #expect(first.count == 24)
    #expect(first[divider].text.count == width)
    state.receive(liveSnapshot((1...20).map { liveRow(Int32($0)) }))
    state.moveSelection(by: 19)
    #expect(state.expanded?.pid == 20)
    let many = LiveReportLayout.lines(state: state, width: width, height: 24)
    #expect(many.firstIndex { $0.style == .separator } == divider)
    #expect(many.contains { $0.text.contains(">") && $0.text.contains("20") })
    state.receive(liveSnapshot([]))
    let empty = LiveReportLayout.lines(state: state, width: width, height: 24)
    #expect(empty.firstIndex { $0.style == .separator } == divider)
    #expect(empty.contains { $0.text.contains("No process selected") })
    #expect(state.detailsMode == .split)
}

@Test func detailsMinimizeMaximizeAndRestoreRememberTheChosenRatio() {
    var state = LiveReportState()
    state.receive(liveSnapshot([liveRow(42)]))
    state.restoreDetails()
    #expect(state.detailsPercent == 50)
    state.adjustDetails(by: 5)
    #expect(state.detailsPercent == 55)
    state.maximizeDetails()
    #expect(state.detailsMode == .maximized)
    let maximized = LiveReportLayout.lines(state: state, width: 100, height: 24)
    #expect(maximized.firstIndex { $0.style == .separator } == 3)
    #expect(maximized.contains { $0.text.contains("PID 42 |") })
    state.minimizeDetails()
    let minimized = LiveReportLayout.lines(state: state, width: 100, height: 24)
    #expect(minimized.firstIndex { $0.style == .separator } == 20)
    #expect(!minimized.contains { $0.text.contains("PID 42 |") })
    state.restoreDetails()
    #expect(state.detailsPercent == 55)
    #expect(state.detailsMode == .split)
    #expect(state.expanded?.pid == 42)
    state.adjustDetails(by: 1000)
    #expect(state.detailsPercent == 90)
    state.adjustDetails(by: -1000)
    #expect(state.detailsPercent == 10)
}

@Test func detailsRatioSurvivesTerminalResizeAndDisclosureToggle() {
    var state = LiveReportState()
    state.receive(liveSnapshot([liveRow(42)]))
    state.adjustDetails(by: 10)
    let tall = LiveReportLayout.lines(state: state, width: 100, height: 24)
    let short = LiveReportLayout.lines(state: state, width: 40, height: 8)
    #expect(tall.firstIndex { $0.style == .separator } == 10)
    #expect(short.count == 8)
    #expect(short.allSatisfy { $0.text.count <= 40 })
    #expect(short.last?.text.contains("q/Ctrl-C") == true)
    state.toggleDisclosure()
    #expect(state.detailsMode == .minimized)
    state.toggleDisclosure()
    #expect(state.detailsMode == .split)
    #expect(state.detailsPercent == 60)
    #expect(LiveReportLayout.lines(state: state, width: 100, height: 24) == tall)
}

@Test(arguments: [40, 60, 80, 100, 120, 160, 200])
func keyboardHelpSeparatesControlsWithoutClipping(width: Int) {
    let lines = LiveReportLayout.lines(state: LiveReportState(), width: width, height: 24)
    let text = lines.map(\.text).joined(separator: "\n")
    for control in [
        "↑/↓ select", "←/→ fold", "g group", "c/m/n/o sort", "r reverse", "[/] scroll",
        "-/+ size", "0 min",
        "9 max", "= restore", "q/Ctrl-C quit",
    ] {
        #expect(text.contains(control))
    }
    #expect(text.contains("   "))
    #expect(lines.count == 24)
    #expect(lines.allSatisfy { $0.text.count <= width })
}

@Test func filterSettingsRemainVisibleWithGroupingAndDisappearanceNotices() {
    var state = LiveReportState(grouping: .session)
    state.receive(liveSnapshot([liveRow(42)]))
    var lines = LiveReportLayout.lines(state: state, width: 100, height: 24)
    #expect(lines.contains { $0.text.contains("CPU > 25.00% OR GB > 1.00") })
    state.toggleGrouping()
    state.receive(liveSnapshot([]))
    lines = LiveReportLayout.lines(state: state, width: 100, height: 24)
    #expect(lines.contains { $0.text.contains("left the heavy findings") })
    #expect(lines.contains { $0.text.contains("CPU > 25.00% OR GB > 1.00") })
}

@Test func filterKeysUseTenCPUPointsAndOneDecimalGBAndClampAtZero() {
    var state = LiveReportState(thresholds: Thresholds(cpuPercent: 25, memoryBytes: 1_500_000_000))
    state.adjustThreshold(.cpuUp)
    state.adjustThreshold(.memoryUp)
    #expect(state.thresholds.cpuPercent == 35)
    #expect(state.thresholds.memoryBytes == 2_500_000_000)
    state.adjustThreshold(.cpuDown)
    state.adjustThreshold(.memoryDown)
    #expect(state.thresholds.cpuPercent == 25)
    #expect(state.thresholds.memoryBytes == 1_500_000_000)
    for _ in 0..<4 {
        state.adjustThreshold(.cpuDown)
        state.adjustThreshold(.memoryDown)
    }
    #expect(state.thresholds.cpuPercent == 0)
    #expect(state.thresholds.memoryBytes == 0)
    state.receive(liveSnapshot([]))
    #expect(state.thresholds.cpuPercent == 0)
    #expect(state.thresholds.memoryBytes == 0)
    let text = LiveReportLayout.lines(state: state, width: 100, height: 24).map(\.text).joined(
        separator: "\n")
    #expect(text.contains("1/2 CPU -/+10%"))
    #expect(text.contains("3/4 GB -/+1"))
    #expect(text.contains("pending"))
}

@Test func memoryFilterIncreaseSaturatesInsteadOfOverflowing() {
    var state = LiveReportState(thresholds: Thresholds(memoryBytes: UInt64.max - 1))
    state.adjustThreshold(.memoryUp)
    #expect(state.thresholds.memoryBytes == UInt64.max)
}

@Test func filterDisplayDistinguishesPendingChangesFromAppliedSnapshots() {
    var state = LiveReportState(thresholds: Thresholds(cpuPercent: 15, memoryBytes: 0))
    state.receive(liveSnapshot([liveRow(42)]))
    let pending = LiveReportLayout.lines(state: state, width: 100, height: 24)
    #expect(pending.contains { $0.text.contains("CPU > 15.00% OR GB > 0.00 (pending)") })
    state.adjustThreshold(.cpuUp)
    state.adjustThreshold(.memoryUp)
    let applied = LiveReportLayout.lines(state: state, width: 100, height: 24)
    #expect(applied.contains { $0.text == "CPU > 25.00% OR GB > 1.00" })
    #expect(!applied.contains { $0.text.contains("pending") })
}

@Test(arguments: [(100, 3, 3), (120, 2, 2), (160, 2, 2), (200, 2, 2)])
func responsiveChromeReturnsSpareRowsToProcesses(size: (width: Int, header: Int, footer: Int)) throws {
    var state = LiveReportState()
    state.receive(liveSnapshot((1...40).map { liveRow(Int32($0)) }))
    let lines = LiveReportLayout.lines(state: state, width: size.width, height: 24)
    let table = try #require(lines.firstIndex { $0.text.contains("PROCESS") })
    let help = try #require(lines.firstIndex { $0.text.contains("↑/↓ select") })
    #expect(table == size.header)
    #expect(24 - help == size.footer)
    #expect(
        lines.filter { $0.style == .selected || $0.style == .heavy }.count == 24 - size.header - size.footer
            - 2)
    #expect(lines.allSatisfy { $0.text.count <= size.width })
    let header = lines.prefix(table).map(\.text).joined(separator: "\n")
    #expect(header.contains("40 heavy / 40 sampled"))
    #expect(header.contains("CPU > 25.00% OR GB > 1.00"))
}

@Test(arguments: [60, 160])
func responsiveTablePreservesAgentIdentityBesideLongProcessNames(width: Int) throws {
    let original = liveRow(42)
    let session = "12345678-1234-1234-1234-123456789abc"
    let row = HeavyProcess(
        process: original.process, executable: original.executable,
        name: "long-running-agent-worker-process", cpuPercent: original.cpuPercent,
        footprintBytes: original.footprintBytes, cwd: "/projects/long-project-directory-name",
        command: nil, metadataStatus: original.metadataStatus,
        attribution: Attribution(
            provider: .codex, evidence: .marker, context: .terminal, threadID: session,
            rootSessionID: nil, runtime: nil, terminal: "ttys001", runtimeDirectory: nil,
            candidateThreadIDs: [], ancestry: []))
    var state = LiveReportState()
    state.receive(liveSnapshot([row]))
    let lines = LiveReportLayout.lines(state: state, width: width, height: 24)
    let text = try #require(lines.first { $0.style == .selected }).text
    if width >= 160 {
        #expect(text.contains(row.name))
        #expect(text.contains("codex/" + session))
        #expect(text.contains("ttys001 / long-project-directory-name"))
    } else {
        #expect(text.contains("long-running"))
        #expect(text.contains("codex/12345678"))
        #expect(text.count <= width)
    }
}

@Test(arguments: [1, 20, 39, 40, 60, 84, 85, 100, 119, 120, 160, 200], [3, 8, 16, 24])
func responsiveLayoutStaysWithinBothViewportDimensions(width: Int, height: Int) {
    var state = LiveReportState()
    state.receive(liveSnapshot([liveRow(42)]))
    for mode in [DetailsPaneMode.minimized, .split, .maximized] {
        switch mode {
        case .minimized: state.minimizeDetails()
        case .split: state.restoreDetails()
        case .maximized: state.maximizeDetails()
        }
        let lines = LiveReportLayout.lines(state: state, width: width, height: height)
        #expect(lines.count <= height)
        #expect(lines.allSatisfy { $0.text.count <= width })
        if width >= 40 && height >= 8 {
            #expect(lines.count == height)
            #expect(lines.contains { $0.text.contains("q/Ctrl-C quit") })
        }
    }
}

@Test(arguments: [60, 85, 120, 160, 200])
func processColumnFitsNamesInsteadOfAbsorbingSpareTerminalWidth(width: Int) throws {
    var state = LiveReportState()
    for names in [["codex", "java"], ["worker", "background-task"]] {
        state.receive(
            liveSnapshot(names.enumerated().map { liveRow(Int32($0.offset + 1), name: $0.element) }))
        let lines = LiveReportLayout.lines(state: state, width: width, height: 24)
        let header = try #require(lines.first { $0.text.contains("PROCESS") }).text
        let process = try #require(header.range(of: "PROCESS")).lowerBound.utf16Offset(in: header)
        let agent = try #require(header.range(of: "AGENT")).lowerBound.utf16Offset(in: header)
        #expect(agent - process == max("PROCESS".count, names.map(\.count).max() ?? 0) + 1)
        for row in lines where row.style == .selected || row.style == .heavy {
            #expect(row.text.range(of: "codex/")?.lowerBound.utf16Offset(in: row.text) == agent)
        }
    }
}

@Test func shortProcessNamesLeaveRoomForFullSessionAndProjectAt120Columns() throws {
    let original = liveRow(42)
    let session = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    let row = HeavyProcess(
        process: original.process, executable: "/usr/bin/java", name: "java", cpuPercent: 0.07,
        footprintBytes: 1_600_000_000, cwd: "/projects/sample-agent-project", command: nil,
        metadataStatus: original.metadataStatus,
        attribution: Attribution(
            provider: .claude, evidence: .marker, context: .terminal,
            threadID: session, rootSessionID: nil, runtime: nil, terminal: nil,
            runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []))
    var state = LiveReportState()
    state.receive(liveSnapshot([row]))
    let text = try #require(
        LiveReportLayout.lines(state: state, width: 120, height: 24).first { $0.style == .selected }
    ).text
    #expect(text.contains("claude/" + session))
    #expect(text.contains("no tty / sample-agent-project"))
}

// Roles, not colors, are the contract; the TUI maps them to colors and NO_COLOR drops them.
@Test(arguments: [60, 100, 200])
func statusChromeAndKeysUseTheirOwnRoles(width: Int) {
    var state = LiveReportState()
    state.receive(liveSnapshot([liveRow(42)]))
    let lines = LiveReportLayout.lines(state: state, width: width, height: 24)
    let status = lines.prefix { !$0.text.contains("PROCESS") }
    #expect(status.first?.style == .title)
    #expect(status.contains { $0.text.contains("Updates:") && $0.style == .title })
    #expect(status.allSatisfy { $0.style == .title || $0.style == .muted })
    let keys = lines.drop { !$0.text.contains("↑/↓ select") }
    #expect(!keys.isEmpty && keys.allSatisfy { $0.style == .muted })
}

@Test func intervalStepsAlongTheLadderFromAnyStart() {
    var state = LiveReportState(interval: 1)
    state.adjustInterval(.faster)
    #expect(state.interval == 0.5)
    state.adjustInterval(.faster)
    #expect(state.interval == 0.5)
    for _ in 0..<10 { state.adjustInterval(.slower) }
    #expect(state.interval == 60)
    var between = LiveReportState(interval: 3)
    between.adjustInterval(.faster)
    #expect(between.interval == 2)
    between = LiveReportState(interval: 3)
    between.adjustInterval(.slower)
    #expect(between.interval == 5)
    // Below the ladder, faster keeps the explicit --interval rather than slowing it down.
    var fast = LiveReportState(interval: 0.2)
    fast.adjustInterval(.faster)
    #expect(fast.interval == 0.2)
    fast.adjustInterval(.slower)
    #expect(fast.interval == 0.5)
}

@Test func statusShowsTheRequestedInterval() {
    var state = LiveReportState(interval: 1)
    state.receive(liveSnapshot([liveRow(42)]))
    #expect(LiveReportLayout.lines(state: state, width: 120, height: 24)[0].text.contains("every 1 s"))
    state.adjustInterval(.faster)
    #expect(LiveReportLayout.lines(state: state, width: 120, height: 24)[0].text.contains("every 0.5 s"))
}

@Test func freezeHoldsTheViewAndShowsTheLatestSnapshotOnRelease() {
    var state = LiveReportState()
    state.receive(liveSnapshot([liveRow(42)]))
    state.toggleFreeze()
    state.receive(liveSnapshot([liveRow(84)]))
    state.receive(liveSnapshot([liveRow(99)]))
    #expect(state.rows.map(\.process.pid) == [42])
    #expect(state.updates == 1)
    #expect(LiveReportLayout.lines(state: state, width: 120, height: 24)[0].text.contains("PAUSED"))
    state.toggleFreeze()
    #expect(state.rows.map(\.process.pid) == [99])
    #expect(state.updates == 2)
    #expect(!LiveReportLayout.lines(state: state, width: 120, height: 24)[0].text.contains("PAUSED"))
}

@Test(arguments: [40, 80, 100, 120])
func pausedStatusAndResumeKeyRemainVisible(width: Int) {
    var state = LiveReportState()
    state.receive(liveSnapshot([liveRow(42)]))
    let live = LiveReportLayout.lines(state: state, width: width, height: 8)
    #expect(live.contains { $0.text.contains("p pause") })
    state.toggleFreeze()
    let paused = LiveReportLayout.lines(state: state, width: width, height: 8)
    #expect(paused[0].text.hasPrefix("PAUSED at "))
    #expect(paused[0].text.contains("p resume"))
    #expect(paused.contains { $0.text.contains("CPU > 25.00% OR GB > 1.00") })
}

@Test func pausedInspectionKeepsSelectionDetailsAndOrderWhileCPUChanges() {
    var state = LiveReportState()
    state.sort(by: .cpu)
    state.receive(liveSnapshot([liveRow(42, cpu: 90), liveRow(84, cpu: 50)]))
    state.toggleDisclosure()
    let selected = state.selected
    let expanded = state.expanded
    state.toggleFreeze()
    state.receive(liveSnapshot([liveRow(42, cpu: 30), liveRow(84, cpu: 99)]))
    #expect(state.rows.map(\.process.pid) == [42, 84])
    #expect(state.selected == selected)
    #expect(state.expanded == expanded)
    state.toggleFreeze()
    #expect(state.rows.map(\.process.pid) == [84, 42])
    #expect(state.selected == selected)
    #expect(state.expanded == expanded)
}

@Test func pinsKeepInsertionOrderAndLiveValuesAcrossSortAndRefresh() throws {
    var state = LiveReportState()
    let first = liveRow(42, cpu: 90)
    let second = liveRow(84, cpu: 50)
    state.receive(liveSnapshot([first, second]))
    state.togglePin(.process(second.process))
    state.togglePin(.process(first.process))
    state.receive(liveSnapshot([liveRow(42, cpu: 100), liveRow(84, cpu: 30), liveRow(99, cpu: 200)]))
    state.reverseSort()
    #expect(state.visibleRows.prefix(2).map(\.id) == [.process(second.process), .process(first.process)])
    guard case .process(let updated) = state.pinnedRows.first else {
        Issue.record("Missing live pin")
        return
    }
    #expect(updated.cpuPercent == 30)
    #expect(state.rows.count == 3)
    state.togglePin(.process(second.process))
    #expect(state.pins.map(\.id) == [.process(first.process)])
    #expect(Set(state.visibleRows.map(\.id)).count == 3)
}

@Test func missingPinsRemainExplicitPlaceholdersAndNeverRetargetReusedPIDs() {
    var state = LiveReportState()
    let original = liveRow(42)
    state.receive(liveSnapshot([original]))
    state.togglePin(.process(original.process))
    state.toggleDisclosure()
    state.receive(liveSnapshot([liveRow(42, start: 2)]))
    #expect(state.selection == .process(original.process))
    guard case .unavailable(let pin) = state.visibleRows.first else {
        Issue.record("Missing placeholder")
        return
    }
    #expect(pin.id == .process(original.process))
    #expect(state.beginAction(.terminate) == nil)
    #expect(state.actionPanel == nil)
    let rendered = LiveReportLayout.lines(state: state, width: 120, height: 24).map(\.text).joined(
        separator: "\n")
    #expect(rendered.contains("Not in current results"))
    state.receive(liveSnapshot([original]))
    #expect(state.pinnedRows == [.process(original)])
    state.togglePin(.process(original.process))
    #expect(state.pins.isEmpty)
}

@Test func stableOrderRetainsSurvivorsAppendsArrivalsAndTreatsPIDReuseAsNew() {
    var state = LiveReportState()
    #expect(state.sortKey == .stable)
    state.receive(liveSnapshot([liveRow(20, cpu: 80), liveRow(10, cpu: 30)]))
    state.receive(liveSnapshot([liveRow(5, cpu: 900), liveRow(10, cpu: 100), liveRow(20, cpu: 1)]))
    #expect(state.rows.map(\.process.pid) == [20, 10, 5])
    state.togglePin(.process(state.rows[1].process))
    #expect(
        state.unpinnedRows.map(\.id) == [.process(state.rows[0].process), .process(state.rows[2].process)])
    state.receive(liveSnapshot([liveRow(20, start: 2, cpu: 900), liveRow(5), liveRow(10)]))
    #expect(state.rows.map(\.process.pid) == [10, 5, 20])
    state.reverseSort()
    #expect(state.rows.map(\.process.pid) == [10, 5, 20])
    state.resetCollection()
    state.receive(liveSnapshot([liveRow(9, cpu: 999), liveRow(5, cpu: 1)]))
    #expect(state.rows.map(\.process.pid) == [5, 9])
}

@Test func selectingStableOrderKeepsCurrentOrderAndPauseDefersArrivals() {
    var state = LiveReportState()
    state.receive(liveSnapshot([liveRow(20), liveRow(10)]))
    state.sort(by: .pid)
    state.reverseSort()
    state.sort(by: .stable)
    #expect(state.rows.map(\.process.pid) == [20, 10])
    state.toggleFreeze()
    state.receive(liveSnapshot([liveRow(5, cpu: 1000), liveRow(10), liveRow(20)]))
    #expect(state.rows.map(\.process.pid) == [20, 10])
    state.toggleFreeze()
    #expect(state.rows.map(\.process.pid) == [20, 10, 5])
    state.sort(by: .cpu)
    #expect(state.rows.map(\.process.pid) == [5, 10, 20])
}

@Test(arguments: [ReportGrouping.none, .session])
func processDetailsReturnAfterFilteringWithoutShowingStaleData(grouping: ReportGrouping) throws {
    let row = liveRow(20)
    var state = LiveReportState(grouping: grouping)
    state.receive(liveSnapshot([row]))
    if grouping == .session { state.setDisclosure(expanded: true) }
    state.select(.process(row.process))
    state.setDisclosure(expanded: true)
    state.receive(liveSnapshot([liveRow(30)]))
    #expect(state.expanded == nil)
    #expect(
        !LiveReportLayout.lines(state: state, width: 100, height: 24).contains {
            $0.text.contains("PID 20 |")
        })
    state.receive(liveSnapshot([row, liveRow(30)]))
    #expect(state.expanded == row.process)
    #expect(state.selected == row.process)
    #expect(state.detailsMode == .split)
    #expect(
        LiveReportLayout.lines(state: state, width: 100, height: 24).contains { $0.text.contains("PID 20 |") }
    )
}

private enum InspectionChange: CaseIterable { case select, collapse, minimize, maximize, grouping, action }

@Test(arguments: InspectionChange.allCases)
private func explicitInspectionChangesCancelReturningDetails(change: InspectionChange) {
    let row = liveRow(20)
    let other = liveRow(30)
    var state = LiveReportState()
    state.receive(liveSnapshot([row, other]))
    state.setDisclosure(expanded: true)
    state.receive(liveSnapshot([other]))
    switch change {
    case .select: state.select(.process(other.process))
    case .collapse: state.setDisclosure(expanded: false)
    case .minimize: state.minimizeDetails()
    case .maximize: state.maximizeDetails()
    case .grouping: state.toggleGrouping()
    case .action: _ = state.beginAction(.terminate)
    }
    state.receive(liveSnapshot([row, other]))
    #expect(state.expanded != row.process)
    if change != .grouping { #expect(state.selected == other.process) }
}

@Test func reusedPIDCannotRestoreMissingProcessDetails() {
    var state = LiveReportState()
    state.receive(liveSnapshot([liveRow(20)]))
    state.setDisclosure(expanded: true)
    state.receive(liveSnapshot([]))
    state.receive(liveSnapshot([liveRow(20, start: 2)]))
    #expect(state.expanded == nil)
}

@Test func explicitlyCollapsedProcessStaysCollapsedAfterFiltering() {
    let row = liveRow(20)
    var state = LiveReportState()
    state.receive(liveSnapshot([row]))
    state.setDisclosure(expanded: true)
    state.setDisclosure(expanded: false)
    state.receive(liveSnapshot([]))
    state.receive(liveSnapshot([row]))
    #expect(state.expanded == nil)
    #expect(state.detailsMode == .minimized)
}

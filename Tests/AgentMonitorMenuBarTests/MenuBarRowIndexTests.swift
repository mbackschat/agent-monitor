import AgentMonitorActions
import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore
@testable import AgentMonitorMenuBar

@Test @MainActor func rowLookupsReuseOneProjectionUntilDisplayedMembershipChanges() async throws {
    let first = try menuBarFixture(pids: [42001, 42002])
    let model = MenuBarModel { _, _, receive in try await receive(first) }
    model.open()
    await model.waitForCollection()
    let initial = model.rowIndex
    let group = try #require(model.report.groups.first)
    let child = LiveReportRowID.process(first.findings[0].process)
    #expect(!model.canBegin(.terminate, row: child))
    for _ in 0..<10 {
        _ = model.visibleRowIDs
        _ = model.canBegin(.focus, row: .group(group.id))
        _ = model.pidToCopy(for: child)
    }
    model.report.setInterval(1)
    model.report.recordHistory(first)
    #expect(model.rowIndex === initial)
    model.report.select(.group(group.id))
    model.report.setDisclosure(expanded: true)
    #expect(model.rowIndex !== initial)
    #expect(model.canBegin(.terminate, row: child))
    let expanded = model.rowIndex
    model.report.select(child)
    #expect(model.rowIndex === expanded)
    #expect(model.pidToCopy(for: child) == "42001")
    model.report.togglePin(child)
    #expect(model.rowIndex !== expanded)
    #expect(model.visibleRowIDs.filter { $0 == child }.count == 1)
    model.report.receive(try menuBarFixture(pids: []))
    #expect(model.visibleRowIDs.contains(child))
    #expect(!model.canBegin(.terminate, row: child))
    #expect(model.pidToCopy(for: child) == nil)
    await model.stop()
}

@Test @MainActor func frozenRowsKeepTheirLookupUntilResumeAndSortingRefreshesIt() async throws {
    let first = try menuBarFixture(pids: [42001])
    let second = try menuBarFixture(pids: [42002])
    let model = MenuBarModel { _, _, receive in try await receive(first) }
    model.open()
    await model.waitForCollection()
    let firstRow = LiveReportRowID.process(first.findings[0].process)
    let secondRow = LiveReportRowID.process(second.findings[0].process)
    model.toggleFreeze()
    let frozen = model.rowIndex
    model.report.receive(second)
    #expect(model.rowIndex === frozen)
    #expect(model.canBegin(.terminate, row: firstRow))
    #expect(!model.canBegin(.terminate, row: secondRow))
    model.toggleFreeze()
    #expect(model.rowIndex !== frozen)
    #expect(!model.canBegin(.terminate, row: firstRow))
    #expect(model.canBegin(.terminate, row: secondRow))
    let resumed = model.rowIndex
    model.report.sort(by: .pid)
    #expect(model.rowIndex !== resumed)
    await model.stop()
    #expect(model.visibleRowIDs.isEmpty)
}

@Test @MainActor func regroupingAndIdentityReplacementInvalidateActionLookups() async throws {
    let first = try menuBarFixture(pids: [42001, 42002])
    let model = MenuBarModel { _, _, receive in try await receive(first) }
    model.open()
    await model.waitForCollection()
    let grouped = model.rowIndex
    model.report.toggleGrouping()
    #expect(model.rowIndex !== grouped)
    #expect(model.visibleRowIDs.count == 2)
    let original = first.findings[0]
    let replacement = HeavyProcess(
        process: ProcessIdentity(
            pid: original.process.pid, startMicroseconds: original.process.startMicroseconds + 1),
        executable: original.executable, name: original.name,
        cpuPercent: original.cpuPercent, footprintBytes: original.footprintBytes,
        cwd: original.cwd, command: original.command, metadataStatus: original.metadataStatus,
        attribution: original.attribution)
    model.report.receive(
        MonitoringSnapshot(
            cpuAccounting: first.cpuAccounting, timestamp: first.timestamp,
            intervalSeconds: first.intervalSeconds,
            cpuThresholdPercent: 0, memoryThresholdBytes: 0, sampledProcessCount: 1,
            unreadableProcessCount: 0,
            findings: [replacement]))
    #expect(!model.canBegin(.terminate, row: .process(original.process)))
    #expect(model.canBegin(.terminate, row: .process(replacement.process)))
    #expect(model.rowIndex.processes.count == 1)
    await model.stop()
}

@Test(arguments: [10, 150]) @MainActor
func filteredLookupKeepsFullTotalsWithoutEnablingHiddenProcessActions(sessionCount: Int) async throws {
    let observed = try (0..<150).flatMap { index in
        try menuBarFixture(
            pids: [Int32(42001 + index)], cpu: index < 10 ? 50 : 0, memoryBytes: 1_000_000,
            sessionID: String(format: "11111111-1111-4111-8111-%012d", index % sessionCount)
        ).findings
    }
    let base = try menuBarFixture()
    let snapshot = MonitoringSnapshot(
        cpuAccounting: base.cpuAccounting, timestamp: base.timestamp, intervalSeconds: 0.1,
        cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
        sampledProcessCount: 150, unreadableProcessCount: 0,
        findings: Array(observed.prefix(10)), observedFindings: observed)
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    #expect(model.visibleRowIDs.count == 10)
    #expect(model.rowIndex.projection.groups.flatMap(\.processes).count == 150)
    #expect(model.rowIndex.projection.groups.compactMap(\.cpuTotal).reduce(0, +) == 500)
    #expect(
        model.rowIndex.projection.groups.flatMap(\.processes).compactMap(\.footprintBytes).reduce(0, +)
            == 150_000_000)
    model.report.toggleGrouping()
    #expect(model.visibleRowIDs.count == 10)
    for process in observed.prefix(10) {
        #expect(model.canBegin(.terminate, row: .process(process.process)))
    }
    for process in observed.dropFirst(10) {
        #expect(!model.canBegin(.terminate, row: .process(process.process)))
        #expect(model.pidToCopy(for: .process(process.process)) == nil)
    }
    await model.stop()
}

@Test @MainActor func historicalRowsCannotActOrInflateCurrentMemory() async throws {
    let snapshot = try accountingMenuBarFixture()
    let model = MenuBarModel { _, _, receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    let id = LiveReportRowID.process(try #require(snapshot.findings.first).process)
    #expect(model.visibleRowIDs.contains(id))
    let historical = try #require(snapshot.findings.first)
    #expect(!SessionActions.canFocusTerminal(historical))
    #expect(!model.canBegin(.terminate, row: id))
    #expect(!model.canBegin(.message, row: id))
    #expect(!model.canBegin(.focus, row: id))
    #expect(model.report.groups.first?.memoryGBTotal == 0)
    #expect(model.indicator.statusDescription.contains("Footprint 0"))
    #expect(model.indicator.level == 1)
    await model.stop()
}

func accountingMenuBarFixture() throws -> MonitoringSnapshot {
    let fixture = try menuBarFixture()
    let original = try #require(fixture.findings.first)
    let historical = HeavyProcess(
        process: original.process, executable: original.executable,
        name: original.name, cpuPercent: 8, footprintBytes: nil, cwd: original.cwd, command: original.command,
        metadataStatus: original.metadataStatus, attribution: original.attribution,
        accounting: ProcessWindowAccounting(
            cpuSeconds: 0.08, recoveredCPUSeconds: 0,
            pointCandidateCPUSeconds: 0.08, uncertainCPUSeconds: 0, isHistorical: true,
            lastObservedAt: 0.3, lastObservedFootprintBytes: original.footprintBytes))
    let run = UUID()
    let opening = CounterObservationID(
        scan: AcquisitionScanID(runID: run, sequence: 0), process: original.process)
    let closing = CounterObservationID(
        scan: AcquisitionScanID(runID: run, sequence: 1), process: original.process)
    let contribution = FrozenCPUContribution(
        CPUContribution(
            id: .init(opening: .observation(opening), closing: closing),
            cpuSeconds: 0.08, startedAt: 0, endedAt: 0.3), attribution: original.attribution, observedAt: 0.2)
    let window = ReportWindowSummary(
        runID: run, baselineScan: 0, finalScan: 10, startedAt: 0, endedAt: 1,
        contributions: [contribution], excludedObservationCount: 0, evictedBaselineCount: 0,
        unmeasuredLifetimeCount: 0)
    return MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 8, unmeasuredLifetimeCount: 0,
            previousScanSeconds: 0.01), timestamp: fixture.timestamp,
        intervalSeconds: 0.1, cpuThresholdPercent: 0, memoryThresholdBytes: 0,
        sampledProcessCount: 0, unreadableProcessCount: 0, findings: [historical],
        agentLoad: AgentLoadSummary(processes: [historical], window: window), window: window)
}

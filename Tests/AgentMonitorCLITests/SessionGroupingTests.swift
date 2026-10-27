import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitor
@testable import AgentMonitorCore

@Test(arguments: [true, false])
func sessionTotalsIncludeProcessesHiddenByDisplayFilters(showBusy: Bool) throws {
    let busy = groupedRow(1, thread: "a", cpu: 50, memory: 100_000_000, peak: 4_000_000_000)
    let quiet = groupedRow(2, thread: "a", cpu: 10, memory: 200_000_000)
    let fixture = groupedSnapshot([busy])
    let snapshot = MonitoringSnapshot(
        cpuAccounting: fixture.cpuAccounting, timestamp: fixture.timestamp,
        intervalSeconds: fixture.intervalSeconds, cpuThresholdPercent: 25,
        memoryThresholdBytes: 1_000_000_000, sampledProcessCount: 2,
        unreadableProcessCount: 0, findings: showBusy ? [busy] : [], observedFindings: [busy, quiet])
    var state = LiveReportState(grouping: .session)
    state.receive(snapshot)
    let group = try #require(state.groups.first)
    #expect(group.cpuTotal == 60)
    #expect(abs(try #require(group.memoryGBTotal) - 0.3) < 1e-12)
    #expect(state.rows.map(\.process) == (showBusy ? [busy.process] : []))
    #expect(state.children(of: group).map(\.process) == (showBusy ? [busy.process] : []))
    let text = TextReport.render(snapshot, grouping: .session)
    #expect(state.projection.unpinnedRows.count == (showBusy ? 1 : 0))
    #expect(text.contains("60.00%") == showBusy)
    #expect(text.contains("0.30 GB") == showBusy)
    #expect(text.contains("Kernel footprint peak: 4.00 GB") == showBusy)
}

@Test func filteredSessionsRemainVisibleOnlyWhenExplicitlyPinned() throws {
    let busy = groupedRow(1, thread: "busy", cpu: 50)
    let quiet = groupedRow(2, thread: "quiet", cpu: 0)
    let fixture = groupedSnapshot([busy, quiet])
    var state = LiveReportState(grouping: .session)
    state.receive(fixture)
    let quietGroup = try #require(state.groups.first { $0.sessionID == "quiet" })
    state.togglePin(.group(quietGroup.id))
    let filtered = MonitoringSnapshot(
        cpuAccounting: fixture.cpuAccounting, timestamp: fixture.timestamp,
        intervalSeconds: fixture.intervalSeconds, cpuThresholdPercent: 25,
        memoryThresholdBytes: 0, sampledProcessCount: 2, unreadableProcessCount: 0,
        findings: [busy], observedFindings: [busy, quiet])
    state.receive(filtered)
    #expect(state.projection.pinnedRows.map(\.id) == [.group(quietGroup.id)])
    #expect(state.projection.unpinnedRows.count == 1)
    #expect(state.children(of: quietGroup).isEmpty)
    state.togglePin(.group(quietGroup.id))
    #expect(state.visibleRows.count == 1)
    #expect(!TextReport.render(filtered, grouping: .session).contains("Session: quiet"))
    state.togglePin(.process(busy.process))
    #expect(state.projection.unpinnedRows.isEmpty)
    #expect(state.projection.pinnedRows.map(\.id) == [.process(busy.process)])
}

@Test func groupingUsesCorroboratedRootsAndNeverSharedDirectories() throws {
    let root = groupedRow(1, thread: "root", root: "root")
    let child = groupedRow(2, thread: "child", root: "root")
    let other = groupedRow(3, thread: "other")
    let unknown = groupedRow(4, thread: nil)
    let anotherUnknown = groupedRow(5, thread: nil)
    let groups = SessionGrouping.groups([root, child, other, unknown, anotherUnknown, child])
    #expect(groups.count == 4)
    let rootGroup = try #require(groups.first { $0.sessionID == "root" })
    #expect(rootGroup.isRoot)
    #expect(rootGroup.processes.map(\.process.pid) == [1, 2])
    #expect(rootGroup.cpuTotal == 100)
    #expect(rootGroup.memoryGBTotal == 2.4)
    #expect(SessionGrouping.groups([child]).first?.sessionID == "child")
    #expect(SessionGrouping.groups([child]).first?.isRoot == false)
}

@Test func groupingKeepsProvidersAndUncertainEvidenceSeparateAndLabelsPartialTotals() throws {
    let rows = [
        groupedRow(1, thread: "same"), groupedRow(2, thread: "same", provider: .claude),
        groupedRow(3, thread: "same", evidence: .ambiguous),
        groupedRow(4, thread: "same", cpu: nil, memory: nil),
    ]
    let groups = SessionGrouping.groups(rows)
    #expect(groups.count == 3)
    let codex = try #require(groups.first { $0.provider == .codex && $0.sessionID == "same" })
    #expect(codex.cpuTotal == 50)
    #expect(codex.cpuPartial && codex.memoryPartial)
    #expect(codex.processes.count == 2)
    var state = LiveReportState(grouping: .session)
    state.receive(groupedSnapshot(rows))
    #expect(
        LiveReportLayout.lines(state: state, width: 60, height: 24).contains {
            $0.text.contains("50.00~") && $0.text.contains("1.20~")
        })
}

@Test func sessionExpansionSelectionAndSortSurviveRefresh() throws {
    var state = LiveReportState(grouping: .session)
    let a = groupedRow(10, thread: "a")
    let b = groupedRow(20, thread: "b", cpu: 80)
    state.receive(groupedSnapshot([a, b]))
    #expect(state.visibleRows.count == 2)
    let group = try #require(state.selectedGroup)
    state.toggleDisclosure()
    #expect(state.visibleRows.count == 3)
    state.moveSelection(by: 1)
    #expect(state.selected == b.process)
    state.toggleDisclosure()
    #expect(state.expanded == b.process)
    state.sort(by: .pid)
    state.receive(groupedSnapshot([b, a]))
    #expect(state.selected == b.process)
    #expect(state.openGroups.contains(group))
    state.moveSelection(by: -1)
    #expect(state.selectedGroup == group)
    state.toggleDisclosure()
    #expect(state.visibleRows.count == 2)
    #expect(state.expanded == nil)
    state.toggleGrouping()
    #expect(state.grouping == .none)
    #expect(state.selected == b.process)
    state.toggleGrouping()
    state.receive(groupedSnapshot([a]))
    #expect(state.selectedGroup != group)
    #expect(!state.openGroups.contains(group))
}

@Test func groupedOptionsAndTextKeepMachineContractExplicit() throws {
    #expect(try Options.parse(["--tui", "--group", "session"]).group == .session)
    #expect(try Options.parse(["--group", "session"]).group == .session)
    #expect(throws: (any Error).self) { try Options.parse(["--json", "--group", "session"]) }
    #expect(throws: (any Error).self) { try Options.parse(["--json-schema", "--group", "session"]) }
    #expect(throws: (any Error).self) { try Options.parse(["--group", "project"]) }
    let text = TextReport.render(
        groupedSnapshot([groupedRow(1, thread: "a"), groupedRow(2, thread: "a")]), grouping: .session)
    #expect(text.contains("totals include all observed members"))
    #expect(text.contains("100.00%"))
    #expect(text.contains("PID 1") && text.contains("PID 2"))
}

@Test func groupSortingUsesHeavyTotalsAndDoesNotChangeTheSelectedGroup() throws {
    var state = LiveReportState(grouping: .session)
    state.sort(by: .cpu)
    state.receive(
        groupedSnapshot([
            groupedRow(10, thread: "a", cpu: 40), groupedRow(11, thread: "a", cpu: 40),
            groupedRow(20, thread: "b", cpu: 60), groupedRow(30, thread: "c", cpu: nil, memory: nil),
        ]))
    #expect(state.groups.map(\.sessionID) == ["a", "b", "c"])
    let selected = state.selectedGroup
    state.reverseSort()
    #expect(state.groups.map(\.sessionID) == ["b", "a", "c"])
    #expect(state.selectedGroup == selected)
    state.sort(by: .memory)
    #expect(state.groups.map(\.sessionID) == ["a", "b", "c"])
    #expect(state.selectedGroup == selected)
    let lines = LiveReportLayout.lines(state: state, width: 120, height: 24)
    #expect(lines.contains { $0.text.contains("all observed totals") })
    #expect(lines.contains { $0.text.contains("80.00") && $0.text.contains("2 processes") })
}

@Test func reusedPIDDoesNotInheritAnUnresolvedGroupsExpansion() throws {
    var state = LiveReportState(grouping: .session)
    state.receive(groupedSnapshot([groupedRow(1, thread: nil)]))
    let oldGroup = try #require(state.selectedGroup)
    state.toggleDisclosure()
    let old = groupedRow(1, thread: nil)
    let replacement = HeavyProcess(
        process: ProcessIdentity(pid: 1, startMicroseconds: 2),
        executable: old.executable, name: old.name, cpuPercent: old.cpuPercent,
        footprintBytes: old.footprintBytes, cwd: old.cwd, command: nil,
        metadataStatus: old.metadataStatus, attribution: old.attribution)
    state.receive(groupedSnapshot([replacement]))
    #expect(state.selectedGroup != oldGroup)
    #expect(state.openGroups.isEmpty)
    #expect(state.visibleRows.count == 1)
}

private func groupedRow(
    _ pid: Int32, thread: String?, root: String? = nil, provider: AgentProvider = .codex,
    evidence: AttributionEvidence = .marker, cpu: Double? = 50, memory: UInt64? = 1_200_000_000,
    cwd: String? = "/same/project", runtimeDirectory: String? = "/same/project", peak: UInt64? = nil,
    sessionName: String? = nil
) -> HeavyProcess {
    let identity = ProcessIdentity(pid: pid, startMicroseconds: 1)
    return HeavyProcess(
        process: identity, executable: "/bin/worker", name: "worker", cpuPercent: cpu,
        footprintBytes: memory, kernelPeakFootprintBytes: peak, cwd: cwd, command: nil,
        metadataStatus: .markerRead,
        attribution: Attribution(
            provider: provider, evidence: evidence, context: .terminal,
            threadID: thread, rootSessionID: root, runtime: ProcessIdentity(pid: 999, startMicroseconds: 1),
            terminal: "ttys001", runtimeDirectory: runtimeDirectory, candidateThreadIDs: [],
            ancestry: [identity]), sessionName: sessionName)
}

private func groupedSnapshot(_ rows: [HeavyProcess]) -> MonitoringSnapshot {
    MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
            unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1,
        cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
        sampledProcessCount: rows.count, unreadableProcessCount: 0, findings: rows)
}

@Test func stableSessionsAndPinnedChildrenKeepOrderAcrossResourceChanges() throws {
    var state = LiveReportState(grouping: .session)
    state.receive(
        groupedSnapshot([
            groupedRow(10, thread: "a", cpu: 90), groupedRow(20, thread: "a", cpu: 50),
            groupedRow(30, thread: "b", cpu: 10),
        ]))
    let group = try #require(state.groups.first)
    state.togglePin(.group(group.id))
    state.receive(
        groupedSnapshot([
            groupedRow(5, thread: "a", cpu: 1000), groupedRow(10, thread: "a", cpu: 1),
            groupedRow(20, thread: "a", cpu: 200), groupedRow(30, thread: "b", cpu: 9000),
            groupedRow(40, thread: "c", cpu: 10000),
        ]))
    #expect(state.groups.map(\.sessionID) == ["a", "b", "c"])
    #expect(state.children(of: try #require(state.groups.first)).map(\.process.pid) == [10, 20, 5])
    state.toggleGrouping()
    #expect(state.rows.map(\.process.pid) == [10, 20, 30, 40, 5])
}

@Test func groupProjectUsesWorkloadDirectoriesWithoutChangingSessionIdentity() throws {
    let first = groupedRow(
        1, thread: "same", cwd: "/work/actual-project", runtimeDirectory: "/launch/old-project")
    let second = groupedRow(
        2, thread: "same", cwd: "/work/actual-project", runtimeDirectory: "/launch/old-project")
    let group = try #require(SessionGrouping.groups([first, second]).first)
    #expect(group.project == "/work/actual-project")
    #expect(group.id == .session(provider: "codex", id: "same"))
    #expect(
        SessionGrouping.groups([first, groupedRow(3, thread: "same", cwd: "/work/another-project")]).first?
            .project == "2 dirs")
    #expect(
        SessionGrouping.groups([groupedRow(4, thread: "same", cwd: nil)]).first?.project == "CWD unavailable")
    var state = LiveReportState()
    state.receive(groupedSnapshot([first]))
    let text = LiveReportLayout.lines(state: state, width: 140, height: 24).map(\.text).joined(
        separator: "\n")
    #expect(text.contains("actual-project"))
    #expect(!text.contains("old-project"))
}

@Test(
    arguments: [AgentProvider.claude, .codex],
    ["/work/repo/packages/app", "/work/repo/.claude/worktrees/task", "/work/repo-2"])
func directoryLabelsDoNotClaimProjectsOrChangeSessionMembership(
    provider: AgentProvider, otherDirectory: String
) throws {
    let rows = [
        groupedRow(101, thread: "first", provider: provider, cwd: "/work/repo"),
        groupedRow(102, thread: "first", provider: provider, cwd: otherDirectory),
        groupedRow(103, thread: "second", provider: provider, cwd: "/work/repo"),
    ]
    let groups = SessionGrouping.groups(rows)
    #expect(groups.count == 2)
    let first = try #require(groups.first { $0.sessionID == "first" })
    #expect(first.id == .session(provider: provider.rawValue, id: "first"))
    #expect(first.processes.map(\.process.pid) == [101, 102])
    #expect(first.project == "2 dirs")
    #expect(first.heading == "\(provider.rawValue) · first · 2 dirs")
    #expect(first.headingHelp.contains("/work/repo"))
    #expect(first.headingHelp.contains(otherDirectory))
    #expect(first.label.contains("2 dirs"))
    let second = try #require(groups.first { $0.sessionID == "second" })
    #expect(second.processes.map(\.process.pid) == [103])
    #expect(second.project == "/work/repo")
}

@Test func listedRuntimeJoinsTheSessionItHostsWithoutClaimingLaunchOrigin() throws {
    let runtime = groupedRow(1, thread: "same", provider: .claude, evidence: .sessionRegistry)
    let worker = groupedRow(2, thread: "same", provider: .claude)
    let groups = SessionGrouping.groups([runtime, worker])
    #expect(groups.map(\.processes.count) == [2])
    let text = TextReport.lines(groupedSnapshot([runtime])).map(\.text).joined(separator: "\n")
    #expect(text.contains("current session: same [sessionRegistry"))
    #expect(!text.contains("launch session: same"))
}

@Test func rootExpansionReturnsAfterFilteringAndExplicitCollapseWins() throws {
    let root = groupedRow(10, thread: "root", root: "root")
    let child = groupedRow(20, thread: "child", root: "root")
    var state = LiveReportState(grouping: .session)
    state.receive(groupedSnapshot([root, child]))
    let id = try #require(state.selectedGroup)
    state.setDisclosure(expanded: true)
    state.receive(groupedSnapshot([child]))
    #expect(!state.openGroups.contains(id))
    #expect(state.visibleRows.count == 1)
    state.receive(groupedSnapshot([root, child]))
    #expect(state.openGroups.contains(id))
    #expect(state.visibleRows.count == 3)
    state.select(.group(id))
    state.setDisclosure(expanded: false)
    state.receive(groupedSnapshot([]))
    state.receive(groupedSnapshot([root, child]))
    #expect(!state.openGroups.contains(id))
}

@Test func missingGroupExpansionMemoryIsBoundedWithoutCollapsingPresentGroups() throws {
    var state = LiveReportState(grouping: .session)
    let rows = (1...258).map { groupedRow(Int32($0), thread: "session-\($0)") }
    state.receive(groupedSnapshot(rows))
    let groups = state.groups
    for group in groups {
        state.select(.group(group.id))
        state.setDisclosure(expanded: true)
    }
    state.receive(groupedSnapshot(rows))
    #expect(state.openGroups.count == 258)
    state.receive(groupedSnapshot([]))
    #expect(state.openGroups.isEmpty)
    state.receive(groupedSnapshot(rows))
    #expect(state.openGroups.count == 256)
    #expect(!state.openGroups.contains(try #require(groups.first).id))
    #expect(state.openGroups.contains(try #require(groups.last).id))
}

@Test func bulkSessionDisclosureUsesTheSelectedLevelAndKeepsExplicitState() throws {
    let findings = [groupedRow(1, thread: "a"), groupedRow(2, thread: "a"), groupedRow(3, thread: "b")]
    var state = LiveReportState(grouping: .session)
    state.receive(groupedSnapshot(findings))
    let first = try #require(state.groups.first)
    let second = try #require(state.groups.last)
    let selection = state.selection
    let expandedAll = state.setSessionDisclosure(expanded: true, from: selection)
    #expect(expandedAll)
    #expect(state.openGroups == [first.id, second.id])
    #expect(state.selection == selection)
    #expect(state.expanded == nil)
    let opened = state
    let repeatedExpansion = state.setSessionDisclosure(expanded: true, from: selection)
    #expect(repeatedExpansion)
    #expect(state == opened)
    state.select(.process(findings[0].process))
    state.setDisclosure(expanded: true)
    let collapsedParent = state.setSessionDisclosure(expanded: false, from: state.selection)
    #expect(collapsedParent)
    #expect(state.openGroups == [second.id])
    #expect(state.selection == .group(first.id))
    #expect(state.expanded == nil)
    state.receive(groupedSnapshot(findings))
    #expect(!state.openGroups.contains(first.id))
    let collapsedAll = state.setSessionDisclosure(expanded: false, from: nil)
    #expect(collapsedAll)
    #expect(state.openGroups.isEmpty)
    state.receive(groupedSnapshot([]))
    state.receive(groupedSnapshot(findings))
    #expect(state.openGroups.isEmpty)
}

@Test func bulkSessionDisclosureDistinguishesNativeSingletonsAndPinnedChildren() throws {
    let findings = [groupedRow(1, thread: "a"), groupedRow(2, thread: "b"), groupedRow(3, thread: "b")]
    var state = LiveReportState(grouping: .session)
    state.receive(groupedSnapshot(findings))
    let singleton = try #require(state.groups.first { $0.sessionID == "a" })
    let multi = try #require(state.groups.first { $0.sessionID == "b" })
    let expandedFromSingleton = state.setSessionDisclosure(
        expanded: true, from: .process(findings[0].process), flattenSingletons: true)
    #expect(expandedFromSingleton)
    #expect(state.openGroups == [multi.id])
    state.togglePin(.process(findings[1].process))
    let collapsedFromPin = state.setSessionDisclosure(
        expanded: false, from: .process(findings[1].process), flattenSingletons: true)
    #expect(collapsedFromPin)
    #expect(state.openGroups.isEmpty)
    state.togglePin(.group(singleton.id))
    let expandedPinnedGroups = state.setSessionDisclosure(expanded: true, from: nil, flattenSingletons: true)
    #expect(expandedPinnedGroups)
    #expect(state.openGroups == [singleton.id, multi.id])
}

@Test func bulkDisclosureRejectsHiddenTargetsAndActionPanels() throws {
    let findings = [groupedRow(1, thread: "a"), groupedRow(2, thread: "a")]
    var state = LiveReportState(grouping: .session)
    state.receive(groupedSnapshot(findings))
    let hiddenChild = state.setSessionDisclosure(expanded: true, from: .process(findings[0].process))
    #expect(!hiddenChild)
    let reusedPID = state.setSessionDisclosure(
        expanded: true, from: .process(ProcessIdentity(pid: 1, startMicroseconds: 99)))
    #expect(!reusedPID)
    state.setDisclosure(expanded: true)
    state.select(.process(findings[0].process))
    _ = state.beginAction(.terminate)
    let held = state
    let blockedByAction = state.setSessionDisclosure(expanded: false, from: state.selection)
    #expect(!blockedByAction)
    #expect(state == held)
}

@Test func bulkCollapseReconcilesASelectionThatDiffersFromNativeFocus() throws {
    let findings = [groupedRow(1, thread: "a"), groupedRow(2, thread: "b")]
    var state = LiveReportState(grouping: .session)
    state.receive(groupedSnapshot(findings))
    let other = try #require(state.groups.last)
    state.setSessionDisclosure(expanded: true, from: nil)
    state.select(.process(findings[0].process))
    state.setSessionDisclosure(expanded: false, from: .group(other.id))
    #expect(state.selectedGroup == other.id)
    state.receive(groupedSnapshot(findings))
    #expect(state.openGroups.isEmpty)
}

@Test func bulkSessionDisclosureLeavesFlatProcessInspectionUnchanged() {
    var state = LiveReportState()
    state.receive(groupedSnapshot([groupedRow(1, thread: "a")]))
    state.setDisclosure(expanded: true)
    let held = state
    let handled = state.setSessionDisclosure(expanded: false, from: state.selection)
    #expect(!handled)
    #expect(state == held)
}

@Test func groupNamesAreDisplayContextAndNeverOverrideIdentityOrConflicts() throws {
    let named = groupedRow(1, thread: "session-a", provider: .claude, sessionName: "Index work")
    let group = try #require(SessionGrouping.groups([named]).first)
    #expect(group.heading == "claude · session- · Index work · /same/project")
    #expect(group.label.contains("Index work"))
    let encoded = try #require(
        JSONSerialization.jsonObject(with: JSONReport.encodeLine(groupedSnapshot([named]))) as? [String: Any])
    #expect((encoded["findings"] as? [[String: Any]])?.first?["sessionName"] as? String == "Index work")
    let schema = try #require(JSONSerialization.jsonObject(with: JSONReport.schema()) as? [String: Any])
    let definitions = try #require(schema["$defs"] as? [String: [String: Any]])
    let properties = try #require(definitions["heavyProcess"]?["properties"] as? [String: [String: Any]])
    #expect(properties["sessionName"]?["maxLength"] as? Int == 160)

    let renamed = groupedRow(1, thread: "session-a", provider: .claude, sessionName: "Review index")
    let changed = try #require(SessionGrouping.groups([renamed]).first)
    #expect(changed.id == group.id)
    #expect(changed.cpuTotal == group.cpuTotal)
    let conflicting = groupedRow(2, thread: "session-a", provider: .claude, sessionName: "Other name")
    let uncertain = try #require(SessionGrouping.groups([named, conflicting]).first)
    #expect(!uncertain.heading.contains("Index work"))
    #expect(!uncertain.heading.contains("Other name"))
    #expect(uncertain.heading.contains("session-"))
}

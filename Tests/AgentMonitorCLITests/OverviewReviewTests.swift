import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct OverviewReviewTests {
    @Test func contributorInspectionAndActionsKeepTheOverviewAndRejectStaleTargets() throws {
        let snapshot = try reviewSnapshot(cpu: [90, 40], memory: [200, 400], sameSession: true)
        var report = LiveReportState()
        report.receive(snapshot)
        let owner = session(1)
        report.overview.select(owner)
        report.overview.setDisclosure(expanded: true, for: owner)
        let open = report.overview.open
        let target = try #require(report.contributorProcesses(for: owner).last)
        report.inspectContributorProcess(target.process, contributor: owner)
        #expect(report.showsOverview)
        #expect(report.overview.detailsVisible)
        #expect(report.contributorProcessTarget?.process == target.process)
        #expect(report.commandInspectionTarget?.process == target.process)
        #expect(report.overview.open == open)
        _ = report.beginContributorAction(.terminate, contributor: owner, process: target.process)
        #expect(report.actionPanel?.processes == [target])
        #expect(report.actionPanel?.phase == .confirmTermination)
        #expect(report.showsOverview)
        #expect(report.commandInspectionTarget == nil)
        _ = report.actionInput(.escape)
        let reused = ProcessIdentity(pid: target.process.pid, startMicroseconds: 99)
        _ = report.beginContributorAction(.terminate, contributor: owner, process: reused)
        #expect(report.actionPanel == nil)
        report.overview.toggleDetails()
        #expect(report.contributorProcessTarget == nil)
        #expect(report.overview.open == open)
    }

    @Test @MainActor func contributorInspectionUsesUnfilteredObservationsAndDiscardsArgumentsOnBack()
        async throws
    {
        let snapshot = try reviewSnapshot(
            cpu: [90, 40], memory: [200, 400], sameSession: true, hideFindings: true)
        var report = LiveReportState()
        report.receive(snapshot)
        let owner = session(1)
        let targets = report.contributorProcesses(for: owner)
        #expect(targets.count == 2)
        #expect(snapshot.findings.isEmpty)
        let target = try #require(targets.first)
        let gate = AsyncStream<Void>.makeStream()
        let commands = CommandInspectionController { _ in
            for await _ in gate.stream { break }
            return ["private argument"]
        }
        report.inspectContributorProcess(target.process, contributor: owner)
        #expect(commands.start(try #require(report.commandInspectionTarget)))
        report.overview.showContributorSummary()
        commands.reconcile(with: report)
        gate.continuation.finish()
        await commands.wait()
        #expect(commands.state == nil)
        #expect(report.overview.detailsVisible)
        #expect(report.overview.selection == owner)
        #expect(report.contributorProcessTarget == nil)
        report.inspectContributorProcess(target.process, contributor: owner)
        report.receive(
            try reviewSnapshot(cpu: [90, 40], memory: [200, 400], sameSession: true, collapse: true))
        #expect(report.contributorProcessTarget == nil)
        #expect(report.overview.inspectedProcess == nil)
        _ = report.beginContributorAction(.terminate, contributor: owner, process: target.process)
        #expect(report.actionPanel == nil)
    }

    @Test func explicitOverviewSortingOrdersBothDirectionsAndSurvivesRefresh() throws {
        let snapshot = try reviewSnapshot(
            cpu: [90, 40, 70], memory: [200_000_000, 400_000_000, 300_000_000])
        var overview = ContributorOverview()
        overview.receive(snapshot)
        overview.select(session(2))
        let total = overview.totals
        for (field, expected) in [
            (ContributorOrder.contributor, [1, 2, 3]), (.cpu, [2, 3, 1]), (.memory, [1, 3, 2]),
        ] {
            for ascending in [true, false] {
                overview.receive(snapshot)
                overview.select(session(2))
                overview.sort(by: field, ascending: ascending)
                let ids = (ascending ? expected : expected.reversed()).map(session)
                #expect(overview.main == ids)
                overview.receive(snapshot)
                #expect(overview.main == ids)
                #expect(overview.selection == session(2))
                #expect(overview.totals == total)
                overview.receive(
                    try reviewSnapshot(cpu: [90, 40, 70], memory: [200_000_000, 400_000_000, 300_000_000]))
                #expect(overview.order == field)
                #expect(overview.ascending == ascending)
                #expect(overview.main == ids)
            }
        }
    }

    @Test func pinningAnotherRowPreservesSelectionAndDisclosure() throws {
        var overview = ContributorOverview()
        overview.receive(try reviewSnapshot(cpu: [90, 40], memory: [200_000_000, 400_000_000]))
        overview.select(session(1))
        overview.setDisclosure(expanded: true, for: session(1))
        overview.toggleDetails()
        let admitted = overview.togglePin(for: session(2))
        #expect(admitted)
        #expect(overview.pinned == [session(2)])
        #expect(overview.selection == session(1))
        #expect(overview.isExpanded(session(1)))
        #expect(overview.detailsVisible)
        let removed = overview.togglePin(for: session(2))
        #expect(removed)
        #expect(overview.pinned.isEmpty)
    }

    @Test func overviewSortDirectionsReachNestedProcessSiblings() throws {
        var overview = ContributorOverview()
        overview.receive(
            try reviewSnapshot(
                cpu: [90, 40, 70], memory: [200_000_000, 400_000_000, 300_000_000], sameSession: true))
        let executable = try #require(overview.nodes[session(1)]?.children.first)
        for field in [ContributorOrder.cpu, .memory] {
            for ascending in [true, false] {
                overview.sort(by: field, ascending: ascending)
                let children = try #require(overview.nodes[executable]?.children)
                let values = children.compactMap { overview.nodes[$0] }.map {
                    field == .cpu ? $0.stats.currentCPU : Double($0.stats.memoryBytes)
                }
                #expect(values.count == 3)
                #expect(values == (ascending ? values.sorted() : values.sorted(by: >)))
            }
        }
    }

    @Test func disclosureActivationTogglesVisibleGroupsButLeavesLeafDisclosureEmpty() throws {
        var overview = ContributorOverview()
        overview.receive(try reviewSnapshot(cpu: [90], memory: [200_000_000]))
        let parent = session(1)
        overview.activateRow(parent)
        #expect(overview.isExpanded(parent))
        let executable = try #require(overview.nodes[parent]?.children.first)
        overview.activateRow(executable)
        let leaf = try #require(overview.nodes[executable]?.children.first)
        overview.activateRow(leaf)
        #expect(overview.selection == leaf)
        #expect(!overview.isExpanded(leaf))
        overview.activateRow(parent)
        #expect(!overview.isExpanded(parent))
        #expect(overview.selection == parent)
        overview.activateRow(leaf)
        #expect(overview.selection == parent)
        var quiet = ContributorOverview()
        quiet.receive(try reviewSnapshot(cpu: [1], memory: [1]))
        quiet.showAll = true
        quiet.activateRow(.section(.remainder))
        #expect(!quiet.isExpanded(.section(.remainder)))
        #expect(!quiet.showAll)
    }

    @Test func collapsedDetailReleaseIsVisibleWithoutInventingUnknownOwnership() throws {
        let snapshot = try reviewSnapshot(cpu: [90, 20], memory: [123, 456], collapse: true)
        var overview = ContributorOverview()
        overview.receive(snapshot)
        #expect(overview.totals.currentCPU == 1.1)
        #expect(overview.totals.workerCountText == "1–4")
        let collapsed = try #require(
            overview.visibleRows.first { $0.node.title == "Older work · detail released" })
        #expect(collapsed.node.stats.currentCPU == 1.1)
        #expect(overview.census.contains("1–2"))
        #expect(overview.nodes[.section(.uncertain)]?.stats.currentCPU == 0)
    }

    @Test func processViewDisclosesCollapsedWorkAndItsTimeRange() throws {
        let snapshot = try reviewSnapshot(cpu: [90, 20], memory: [123, 456], collapse: true)
        var state = LiveReportState()
        state.receive(snapshot)
        state.overview.enabled = false
        let lines = LiveReportLayout.lines(state: state, width: 160, height: 30)
        #expect(lines.contains { $0.text.contains("Collapsed") && $0.text.contains("1.00–2.00 s") })
    }

    @Test func releasedCategoriesRetainWorkerRoleAndSampledMaximum() throws {
        let snapshot = try reviewSnapshot(cpu: [90, 20], memory: [123, 456], collapse: true)
        let values = try #require(snapshot.window).collapsedContributions
        try #require(!values.isEmpty)
        #expect(values.allSatisfy { $0.category.isAgentRuntime == false })
        var overview = ContributorOverview()
        overview.receive(snapshot)
        #expect(overview.totals.maximumWorkerFootprint?.bytes == 456)
    }

    @Test func collapsedDisplayAndHistoryKeepTheirOwnRangesInDetails() throws {
        let fixture = try reviewSnapshot(cpu: [90], memory: [123])
        let row = try #require(fixture.findings.first)
        func samples(_ time: Double) -> [ProcessSample] {
            time == 12
                ? []
                : [
                    ProcessSample(
                        identity: row.process, parentPID: 0, executable: row.executable, name: row.name,
                        sampledAt: time, cpuSeconds: time, footprintBytes: 123)
                ]
        }
        var ledger = CounterLedger()
        var previous = ledger.ingest(samples(0), listedAt: 0)
        var history = AccountingWindow(baseline: previous)
        var display: AccountingWindow?
        for tick in 1...12 {
            let scan = ledger.ingest(samples(Double(tick)), listedAt: Double(tick))
            if tick == 11 { display = AccountingWindow(baseline: previous) }
            let rows = tick == 12 ? [] : [row]
            try history.append(scan, rows: rows)
            try display?.append(scan, rows: rows)
            previous = scan
        }
        history.compact(to: MonitoringPipelineLimits(pendingObservations: 1))
        display?.compact(to: MonitoringPipelineLimits(pendingObservations: 1))
        let store = RecentActivityStore()
        store.append(history.seal(scope: .agentsOnly))
        var overview = ContributorOverview()
        overview.receive(
            MonitoringSnapshot(
                cpuAccounting: fixture.cpuAccounting, timestamp: fixture.timestamp,
                intervalSeconds: 0.1, cpuThresholdPercent: 0, memoryThresholdBytes: 0,
                sampledProcessCount: 0, unreadableProcessCount: 0, findings: [],
                window: try #require(display).summary, recentActivity: store.snapshot()))
        let node = try #require(
            overview.nodes.values.first {
                if case .collapsed = $0.id { return true }
                return false
            })
        #expect(node.details.contains { $0.hasPrefix("Display window:") && $0.contains("10.00–11.00 s") })
        #expect(node.details.contains { $0.hasPrefix("Recent history:") && $0.contains("0.00–11.00 s") })
        #expect(node.stats.currentCPU == 1)
        #expect(node.stats.recentCPU == 11)
    }

    @Test func prominenceUsesStrictCombinedGroupCPUWithoutFilteringTotals() throws {
        var overview = ContributorOverview()
        overview.receive(try reviewSnapshot(cpu: [12.5, 12.5], memory: [1, 1], sameSession: true))
        #expect(overview.main.isEmpty)
        #expect(overview.totals.currentCPU == 0.25)
        overview.receive(try reviewSnapshot(cpu: [13, 13], memory: [1, 1], sameSession: true))
        #expect(overview.main == [session(1)])
        #expect(overview.totals.currentCPU == 0.26)
    }

    @Test func inspectPreservesGroupingAndIsInertOutsideOverview() throws {
        let snapshot = try reviewSnapshot(cpu: [20, 90], memory: [200_000_000, 300_000_000])
        var state = LiveReportState(grouping: .session)
        state.receive(snapshot)
        let leaf = try #require(state.overview.nodes.values.first { $0.process?.pid == 1 })
        state.overview.select(leaf.id)
        state.inspectOverviewProcess()
        #expect(state.grouping == .session)
        #expect(state.selected?.pid == 1)
        #expect(state.expanded?.pid == 1)
        state.select(.group(try #require(state.groups.last?.id)))
        let held = state
        state.inspectOverviewProcess()
        #expect(state == held)
    }

    @Test func initialRankingUsesContributionAndSortKeysStayInOverview() throws {
        var state = LiveReportState()
        state.receive(try reviewSnapshot(cpu: [2, 90, 30], memory: [800_000_000, 200_000_000, 400_000_000]))
        #expect(state.overview.main == [session(2), session(3), session(1)])
        state.apply(.memory)
        #expect(state.showsOverview)
        #expect(state.overview.main == [session(1), session(3), session(2)])
        state.apply(.cpu)
        #expect(state.showsOverview)
        #expect(state.overview.main == [session(2), session(3), session(1)])
        state.apply(.reverse)
        #expect(state.overview.main == [session(1), session(3), session(2)])
        let rows = state.overview.visibleRows
        state.apply(.stable)
        #expect(state.showsOverview)
        #expect(state.overview.order.rawValue == "stable")
        #expect(state.overview.visibleRows == rows)
        state.apply(.reverse)
        state.apply(.pid)
        #expect(state.showsOverview)
        #expect(state.overview.visibleRows == rows)
    }

    @Test func memoryOnlyArrivalsUseMemoryOrderAfterCPUContributors() throws {
        var overview = ContributorOverview()
        overview.receive(try reviewSnapshot(cpu: [0, 0, 90], memory: [200_000_000, 800_000_000, 1]))
        #expect(overview.main == [session(3), session(2), session(1)])
    }

    /// A gap appearing or clearing must not move the rows under the user's selection.
    @Test func overviewHeaderReservesOneCoverageRow() throws {
        func firstContributor(unreadable: Int) throws -> Int {
            var state = LiveReportState()
            state.receive(try reviewSnapshot(cpu: [20], memory: [200_000_000], unreadable: unreadable))
            let lines = ContributorLayout.lines(state: state, width: 120, height: 24)
            return try #require(lines.firstIndex { $0.style == .selected })
        }
        #expect(try firstContributor(unreadable: 0) == firstContributor(unreadable: 1))
    }

    @Test func multipleDirectoriesUseSharedProjectRuleEvenWithMatchingBasenames() throws {
        var overview = ContributorOverview()
        overview.receive(
            try reviewSnapshot(
                cpu: [20, 10], memory: [1, 1], sameSession: true,
                directories: ["/one/project", "/two/project"]))
        #expect(overview.nodes[session(1)]?.title == "codex · session- · 2 dirs")
        // Matching basenames stay distinguishable on the contributor rows.
        let titles = overview.nodes[session(1)]?.children.compactMap { overview.nodes[$0]?.title }
        #expect(titles == ["node · /one/project", "node · /two/project"])
    }

    @Test(arguments: [false, true])
    func resetCannotInventARecentMainListDeparture(alreadyQuiet: Bool) throws {
        var feed = OverviewFeed()
        var worker = OverviewFeed.Worker(
            session: "A", executable: "node", pid: 1, cpuPerSecond: 0.3, memory: 1)
        _ = try feed.advance([worker])
        var overview = ContributorOverview()
        let first = try feed.advance([worker])
        overview.receive(first)
        let id = ContributorID.session(provider: "claude", session: "A", root: nil)
        #expect(overview.main == [id])
        worker.cpuPerSecond = 0
        if alreadyQuiet {
            overview.receive(try feed.advance([worker]))
            #expect(overview.nodes[.section(.recent)]?.children.contains(id) == true)
        }
        overview.resetInspection()
        let reopened = try feed.advance([worker])
        #expect(reopened.recentActivity?.runID == first.recentActivity?.runID)
        overview.receive(reopened)
        #expect(overview.main.isEmpty)
        #expect(overview.nodes[.section(.recent)]?.children.contains(id) == false)
        #expect(overview.nodes[.section(.remainder)]?.children.contains(id) == true)
    }

}

private func session(_ id: Int) -> ContributorID {
    .session(provider: "codex", session: "session-\(id)", root: nil)
}

private func reviewSnapshot(
    cpu: [Double], memory: [UInt64], unreadable: Int = 0,
    sameSession: Bool = false, directories: [String]? = nil, collapse: Bool = false,
    hideFindings: Bool = false
) throws -> MonitoringSnapshot {
    var ledger = CounterLedger()
    func samples(_ time: Double) -> [ProcessSample] {
        cpu.indices.map { index in
            ProcessSample(
                identity: ProcessIdentity(pid: Int32(index + 1), startMicroseconds: 1),
                parentPID: 0, executable: "/bin/node", name: "node", sampledAt: time,
                cpuSeconds: time * cpu[index] / 100, footprintBytes: memory[index])
        }
    }
    let baseline = ledger.ingest(samples(0), listedAt: 0)
    let values = samples(1)
    let rows = values.enumerated().map { index, value in
        HeavyProcess(
            process: value.identity, executable: value.executable, name: value.name,
            cpuPercent: cpu[index], footprintBytes: value.footprintBytes,
            cwd: directories?[index] ?? "/project", command: nil, metadataStatus: .markerRead,
            attribution: Attribution(
                provider: .codex, evidence: .marker, context: .unverified,
                threadID: "session-\(sameSession ? 1 : index + 1)", rootSessionID: nil, runtime: nil,
                terminal: nil, runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []))
    }
    var activity = AccountingWindow(baseline: baseline)
    try activity.append(ledger.ingest(values, listedAt: 1), rows: rows)
    if collapse {
        try activity.append(ledger.ingest([], listedAt: 2), rows: [])
        activity.compact(to: MonitoringPipelineLimits(pendingObservations: 1))
    }
    let unit = activity.seal(scope: .agentsOnly)
    let store = RecentActivityStore()
    var coverage = ReadCoverage()
    coverage.append(
        ProcessSnapshot(
            samples: [], enumeratedCount: unreadable, unreadableCount: unreadable,
            listedAt: 1, scanSeconds: 0, hostCounters: nil, logicalCPUCount: 1,
            nativeOutcomes: (0..<unreadable).map {
                NativeCounterOutcome(
                    pid: Int32(900 + $0), identity: nil, operation: .bsdInfo,
                    status: .permissionDenied, failure: nil, observedAtTicks: 1)
            }))
    store.append(
        RecentActivityUnit(
            runID: unit.runID, baseline: unit.baselineScan, final: unit.finalScan,
            start: unit.startedAt, end: unit.endedAt, scope: unit.scope, records: unit.records,
            crossings: unit.crossings, excluded: 0, coverage: coverage, collapsed: unit.collapsedContributions
        ))
    return MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: nil, logicalCPUCount: 8,
            measuredUserPercent: cpu.reduce(0, +), unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
        timestamp: Date(), intervalSeconds: 0.1, cpuThresholdPercent: 0, memoryThresholdBytes: 0,
        sampledProcessCount: rows.count, unreadableProcessCount: unreadable,
        findings: collapse || hideFindings ? [] : rows, observedFindings: collapse ? [] : rows,
        window: collapse ? activity.summary : nil, recentActivity: store.snapshot())
}

import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct OverviewReviewTests {
    @Test func inspectPreservesGroupingAndIsInertOutsideOverview() throws {
        let snapshot = reviewSnapshot(cpu: [20, 90], memory: [200_000_000, 300_000_000])
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

    @Test func initialRankingUsesContributionAndSortKeysStayInOverview() {
        var state = LiveReportState()
        state.receive(reviewSnapshot(cpu: [2, 90, 30], memory: [800_000_000, 200_000_000, 400_000_000]))
        #expect(state.overview.main == [session(2), session(3), session(1)])
        state.apply(.memory)
        #expect(state.showsOverview)
        #expect(state.overview.main == [session(1), session(3), session(2)])
        state.apply(.cpu)
        #expect(state.showsOverview)
        #expect(state.overview.main == [session(2), session(3), session(1)])
    }

    @Test func memoryOnlyArrivalsUseMemoryOrderAfterCPUContributors() {
        var overview = ContributorOverview()
        overview.receive(reviewSnapshot(cpu: [0, 0, 90], memory: [200_000_000, 800_000_000, 1]))
        #expect(overview.main == [session(3), session(2), session(1)])
    }

    @Test func quietPopulationDoesNotFillCPUMeters() throws {
        var state = LiveReportState()
        state.overview = ContributorOverview(memoryCapacityBytes: 16_000_000_000)
        state.receive(reviewSnapshot(cpu: [0.2], memory: [200_000_000]))
        #expect(abs(state.overview.cpuMeterFraction(state.overview.totals) - 0.002) < 1e-9)
        #expect(state.overview.memoryMeterFraction(state.overview.totals) == 0.0125)
        let lines = ContributorLayout.lines(state: state, width: 120, height: 24)
        let row = try #require(lines.first { $0.text.contains("project · codex") })
        #expect(row.text.contains("0.2% ▱▱▱▱"))
    }

    @Test func foldingGroupsDoesNotDumpEvidenceAndCoverageIsVisible() throws {
        var state = LiveReportState()
        state.receive(reviewSnapshot(cpu: [20, 10], memory: [200_000_000, 200_000_000], unreadable: 3))
        state.overview.toggle(session(1))
        let lines = ContributorLayout.lines(state: state, width: 120, height: 24)
        #expect(!lines.contains { $0.text.contains("Exact session:") })
        state.overview.toggleDetails()
        #expect(
            ContributorLayout.lines(state: state, width: 120, height: 24).contains {
                $0.text.contains("Exact session:")
            })
        #expect(lines.prefix(6).contains { $0.text.contains("3 unreadable") })
    }

    @Test func multipleDirectoriesUseSharedProjectRuleEvenWithMatchingBasenames() throws {
        var overview = ContributorOverview()
        overview.receive(
            reviewSnapshot(
                cpu: [20, 10], memory: [1, 1], sameSession: true,
                directories: ["/one/project", "/two/project"]))
        #expect(overview.nodes[session(1)]?.title.hasPrefix("Multiple directories ·") == true)
    }

    @Test func resetCannotInventARecentMainListDeparture() {
        var state = LiveReportState()
        let first = reviewSnapshot(cpu: [2], memory: [1])
        state.receive(first)
        state.overview.resetInspection()
        #expect(state.overview.main.isEmpty)
    }
}

private func session(_ id: Int) -> ContributorID {
    .session(provider: "codex", session: "session-\(id)", root: nil)
}

private func reviewSnapshot(
    cpu: [Double], memory: [UInt64], unreadable: Int = 0,
    sameSession: Bool = false, directories: [String]? = nil
) -> MonitoringSnapshot {
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
    var activity = RecentActivityAccumulator(baseline: baseline)
    activity.append(ledger.ingest(values, listedAt: 1), rows: rows)
    let unit = activity.seal(scope: .agentsOnly)
    let store = RecentActivityStore()
    store.append(
        RecentActivityUnit(
            runID: unit.runID, baseline: unit.baselineScan, final: unit.finalScan,
            start: unit.startedAt, end: unit.endedAt, scope: unit.scope, records: unit.records,
            crossings: unit.crossings, excluded: 0, unreadable: unreadable))
    return MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: nil, logicalCPUCount: 8,
            measuredUserPercent: cpu.reduce(0, +), unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
        timestamp: Date(), intervalSeconds: 0.1, cpuThresholdPercent: 0, memoryThresholdBytes: 0,
        sampledProcessCount: rows.count, unreadableProcessCount: unreadable, findings: rows,
        recentActivity: store.snapshot())
}

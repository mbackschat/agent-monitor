import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct ContributorOverviewTests {
    @Test func quietMemoryAndBurstWorkersRemainDiscoverableWithoutIdleFlood() throws {
        let snapshot = try overviewFixture()
        var overview = ContributorOverview()
        overview.receive(snapshot)
        #expect(overview.main.count == 1)
        #expect(overview.nodes[overview.main[0]]?.stats.memoryBytes == 200_000_000)
        #expect(overview.nodes[.section(.remainder)]?.stats.processes.count == 20)
        #expect(overview.nodes[.section(.recent)]?.stats.recentCPU == 1)
        #expect(overview.nodes[.section(.recent)]?.stats.noLongerObserved.count == 1)
        #expect(overview.totals.recentCPU == 1)
        #expect(overview.totals.memoryBytes == 220_000_000)
    }

    @Test func disclosureAndThresholdsDoNotChangePopulationTotals() throws {
        let snapshot = try overviewFixture()
        var overview = ContributorOverview()
        overview.receive(snapshot)
        let totals = overview.totals
        overview.showAll = true
        #expect(overview.totals == totals)
        overview.toggle(.section(.remainder))
        #expect(overview.totals == totals)
        #expect(overview.visibleRows.count > overview.main.count)
    }
}

func overviewFixture(sessionNames: [String?] = []) throws -> MonitoringSnapshot {
    var ledger = CounterLedger()
    func samples(_ time: Double, includeBurst: Bool) -> [ProcessSample] {
        var values: [ProcessSample] = []
        for id in 1...22 where includeBurst || id != 22 {
            let identity = ProcessIdentity(pid: Int32(id), startMicroseconds: UInt64(id))
            let cpu: Double = id == 22 ? time : 0
            let footprint: UInt64 = id == 1 ? 200_000_000 : 1_000_000
            values.append(
                ProcessSample(
                    identity: identity, parentPID: 0, executable: "/bin/node",
                    name: "node \(id)", sampledAt: time, cpuSeconds: cpu, footprintBytes: footprint))
        }
        return values
    }
    func rows(_ samples: [ProcessSample]) -> [HeavyProcess] {
        samples.map { value in
            HeavyProcess(
                process: value.identity, executable: value.executable, name: value.name,
                cpuPercent: nil, footprintBytes: value.footprintBytes, cwd: "/fixture", command: nil,
                metadataStatus: .markerRead,
                attribution: Attribution(
                    provider: .codex, evidence: .marker,
                    context: .unverified, threadID: "session-\(value.identity.pid)", rootSessionID: nil,
                    runtime: nil, terminal: nil, runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []),
                sessionName: value.identity.pid == 1 && !sessionNames.isEmpty
                    ? sessionNames[min(sessionNames.count - 1, max(0, Int(value.sampledAt) - 1))] : nil)
        }
    }
    let baseline = ledger.ingest(samples(0, includeBurst: true), listedAt: 0)
    let store = RecentActivityStore()
    var previous = baseline
    for tick in 1...2 {
        let values = samples(Double(tick), includeBurst: tick == 1)
        let scan = ledger.ingest(values, listedAt: Double(tick))
        var accumulator = AccountingWindow(baseline: previous)
        let findings = rows(values)
        try accumulator.append(scan, rows: findings)
        store.append(
            accumulator.seal(scope: .agentsOnly), current: accumulator.current, present: accumulator.present)
        previous = scan
    }
    return MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: nil, logicalCPUCount: 8,
            measuredUserPercent: 0, unmeasuredLifetimeCount: 0, previousScanSeconds: nil), timestamp: Date(),
        intervalSeconds: 0.1, cpuThresholdPercent: 0, memoryThresholdBytes: 0,
        sampledProcessCount: 21, unreadableProcessCount: 0, findings: [], recentActivity: store.snapshot())
}

extension ContributorOverviewTests {
    @Test func pinsImmediatelyConserveSectionsAndPauseSurvivesResetButNotANewRun() throws {
        let snapshot = try overviewFixture()
        var state = LiveReportState()
        state.receive(snapshot)
        let recent = try #require(state.overview.nodes[.section(.recent)]?.children.first)
        state.overview.select(recent)
        state.overview.togglePin()
        let sections = state.overview.topLevel.compactMap { state.overview.nodes[$0]?.stats }
        #expect(sections.reduce(0) { $0 + $1.recentCPU } == state.overview.totals.recentCPU)
        #expect(state.overview.visibleRows.filter { $0.id == recent }.count == 1)
        state.toggleFreeze()
        let held = state.overview
        state.resetCollection()
        #expect(state.overview.runID == held.runID)
        #expect(state.overview.selection == nil)
        #expect(state.overview.open.isEmpty)
        #expect(state.overview.nodes.isEmpty)
        state.receive(snapshot)
        state.toggleFreeze()
        state.receive(try overviewFixture())
        #expect(!state.frozen)
        #expect(state.overview.runID != held.runID)
        #expect(state.overview.pinned == held.pinned)
    }

    @Test(arguments: [40, 80, 120])
    func terminalOverviewFitsAndKeepsCoverageVisible(width: Int) throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        let lines = LiveReportLayout.lines(state: state, width: width, height: 24)
        #expect(lines.count <= 24)
        #expect(lines.allSatisfy { TerminalCells.width($0.text) <= width })
        #expect(lines.contains { $0.text.contains("Recent 2.0 s") })
        #expect(lines.contains { $0.text.contains("Unresolved") })
    }
}

extension ContributorOverviewTests {
    @Test func frozenOwnersConserveCPUAndOnlyTheFinalOwnerGetsCurrentMemory() throws {
        var ledger = CounterLedger()
        let identity = ProcessIdentity(pid: 7, startMicroseconds: 70)
        func sample(_ tick: Int) -> ProcessSample {
            ProcessSample(
                identity: identity, parentPID: 0, executable: tick < 3 ? "/bin/java" : "/bin/node",
                name: "worker", sampledAt: Double(tick), cpuSeconds: Double(tick),
                footprintBytes: tick == 1 ? 100_000_000 : (tick == 2 ? 80_000_000 : 50_000_000))
        }
        var baseline = ledger.ingest([sample(0)], listedAt: 0)
        let store = RecentActivityStore()
        for unit in 0..<2 {
            var accumulator = AccountingWindow(baseline: baseline)
            for offset in 1...2 {
                let tick = unit * 2 + offset
                let value = sample(tick)
                let owner = tick == 1 ? nil : (tick == 2 ? "A" : "B")
                let row = HeavyProcess(
                    process: identity, executable: value.executable, name: value.name,
                    cpuPercent: nil, footprintBytes: value.footprintBytes, cwd: "/project", command: nil,
                    metadataStatus: .markerRead,
                    attribution: Attribution(
                        provider: .codex,
                        evidence: owner == nil ? .runtimeOnly : .marker, context: .unverified,
                        threadID: owner,
                        rootSessionID: nil, runtime: nil, terminal: nil, runtimeDirectory: nil,
                        candidateThreadIDs: [], ancestry: []))
                let scan = ledger.ingest([value], listedAt: Double(tick))
                try accumulator.append(scan, rows: [row], runtimes: tick >= 3 ? [identity] : [])
                baseline = scan
            }
            store.append(
                accumulator.seal(scope: .agentsOnly), current: accumulator.current,
                present: accumulator.present)
        }
        let base = try overviewFixture()
        let snapshot = MonitoringSnapshot(
            cpuAccounting: base.cpuAccounting, timestamp: base.timestamp,
            intervalSeconds: 0.1, cpuThresholdPercent: 0, memoryThresholdBytes: 0,
            sampledProcessCount: 1, unreadableProcessCount: 0, findings: [], recentActivity: store.snapshot())
        var overview = ContributorOverview()
        overview.receive(snapshot)
        let a = try #require(overview.nodes[.session(provider: "codex", session: "A", root: nil)])
        let b = try #require(overview.nodes[.session(provider: "codex", session: "B", root: nil)])
        #expect(a.stats.recentCPU == 1)
        #expect(a.stats.currentCPU == 0)
        #expect(a.stats.memoryBytes == 0)
        #expect(a.stats.noLongerObserved.isEmpty)
        #expect(a.stats.membershipChanged == [identity])
        #expect(b.stats.recentCPU == 2)
        #expect(b.stats.memoryBytes == 50_000_000)
        #expect(overview.nodes[.section(.uncertain)]?.stats.recentCPU == 1)
        #expect(overview.totals.processes.count == 1)
        #expect(
            overview.topLevel.compactMap { overview.nodes[$0] }.reduce(0) { $0 + $1.stats.recentCPU } == 4)
        #expect(
            overview.nodes.values.filter { $0.process == identity }.flatMap(\.details).contains {
                $0.contains("Executable changed across interval")
            })
        #expect(
            !overview.nodes.values.filter { $0.process == identity }.flatMap(\.details).contains {
                $0.contains("ambiguous")
            })
    }
}

extension ContributorOverviewTests {
    @Test func rankingKeepsIncumbentsUntilAChallengerExceedsTwentyPercent() throws {
        var ledger = CounterLedger()
        let store = RecentActivityStore()
        var overview = ContributorOverview()
        var counters = Array(repeating: 0.0, count: 6)
        func values(at time: Double) -> [ProcessSample] {
            (0..<6).map { index in
                ProcessSample(
                    identity: ProcessIdentity(pid: Int32(index + 1), startMicroseconds: 1),
                    parentPID: 0, executable: "/bin/node", name: "node", sampledAt: time,
                    cpuSeconds: counters[index], footprintBytes: 1_000_000)
            }
        }
        var baseline = ledger.ingest(values(at: 0), listedAt: 0)
        for (index, challenger) in [20.0, 35.0, 37.0].enumerated() {
            let rates = [100.0, 80, 60, 40, 30, challenger]
            for worker in 0..<6 { counters[worker] += rates[worker] / 100 }
            let samples = values(at: Double(index + 1))
            let scan = ledger.ingest(samples, listedAt: Double(index + 1))
            var accumulator = AccountingWindow(baseline: baseline)
            try accumulator.append(
                scan,
                rows: samples.map { value in
                    HeavyProcess(
                        process: value.identity, executable: value.executable, name: value.name,
                        cpuPercent: nil, footprintBytes: value.footprintBytes, cwd: nil, command: nil,
                        metadataStatus: .markerRead,
                        attribution: Attribution(
                            provider: .codex, evidence: .marker, context: .unverified,
                            threadID: "session-\(value.identity.pid)", rootSessionID: nil, runtime: nil,
                            terminal: nil, runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []))
                })
            store.append(accumulator.seal(scope: .agentsOnly))
            let base = try overviewFixture()
            overview.receive(
                MonitoringSnapshot(
                    cpuAccounting: base.cpuAccounting, timestamp: base.timestamp, intervalSeconds: 0.1,
                    cpuThresholdPercent: 0, memoryThresholdBytes: 0, sampledProcessCount: 6,
                    unreadableProcessCount: 0, findings: [], recentActivity: store.snapshot()))
            let expected = index == 2 ? [1, 2, 3, 4, 6] : [1, 2, 3, 4, 5]
            #expect(
                overview.main
                    == expected.map {
                        ContributorID.session(provider: "codex", session: "session-\($0)", root: nil)
                    })
            baseline = scan
        }
    }
}

extension ContributorOverviewTests {
    @Test func scopeReplacementEndsPausedInspectionWithinTheSameRun() throws {
        let original = try overviewFixture()
        let unit = try #require(original.recentActivity?.units.last)
        let store = RecentActivityStore()
        store.append(
            RecentActivityUnit(
                runID: unit.runID, baseline: unit.baselineScan, final: unit.finalScan,
                start: unit.startedAt, end: unit.endedAt, scope: .allProcesses,
                records: unit.records, crossings: unit.crossings,
                excluded: unit.excludedObservationCount, coverage: unit.readCoverage))
        let replacement = MonitoringSnapshot(
            cpuAccounting: original.cpuAccounting, timestamp: original.timestamp, intervalSeconds: 0.1,
            cpuThresholdPercent: 0, memoryThresholdBytes: 0, sampledProcessCount: 21,
            unreadableProcessCount: 0, findings: [], recentActivity: store.snapshot())
        var state = LiveReportState()
        state.receive(original)
        state.toggleFreeze()
        state.receive(replacement)
        #expect(!state.frozen)
        #expect(state.snapshot?.recentActivity?.scope == .allProcesses)
    }
}

@Test func overviewShowsLatestListedNameWithoutMovingFrozenCPUOrDirectory() throws {
    let plain = try overviewFixture()
    let named = try overviewFixture(sessionNames: ["Old title", "Index work"])
    var reference = ContributorOverview()
    var overview = ContributorOverview()
    reference.receive(plain)
    overview.receive(named)
    #expect(overview.main == reference.main)
    #expect(overview.totals == reference.totals)
    let id = try #require(overview.main.first)
    #expect(overview.nodes[id]?.title == "codex · Index work · session- · /fixture")
    #expect(overview.nodes[id]?.details.contains("Listed name: Index work") == true)
    #expect(overview.nodes[id]?.stats == reference.nodes[id]?.stats)
}

import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct ContributorActivityTests {
    @Test func overallLaneCountsEachContributionOnceRegardlessOfVisibility() throws {
        var overview = ContributorOverview()
        overview.receive(try overviewFixture(includeProcesses: true))
        let original = overview.activity.totalSamples
        #expect(original.count == overview.activity.spans.count)
        #expect(
            abs(original.compactMap { $0?.cpuSeconds }.reduce(0, +) - overview.totals.recentCPU) < 0.000001)
        let historical = ContributorID.session(provider: "codex", session: "session-22", root: nil)
        overview.togglePin(for: historical)
        overview.hideNoLongerObserved = true
        overview.toggleSection(.sessions)
        overview.toggleTable()
        let updated = overview.activity.totalSamples
        for (before, after) in zip(original, updated) {
            #expect(abs((before?.cpuSeconds ?? 0) - (after?.cpuSeconds ?? 0)) < 0.000001)
            #expect(before?.qualified == after?.qualified)
            #expect(before?.measuredIntervals == after?.measuredIntervals)
        }
        #expect(overview.activity.terminalLane(width: 12).count == 12)
        #expect(ContributorActivity().totalSamples.isEmpty)
        #expect(ContributorActivity().terminalLane(width: 4) == "····")
    }

    @Test(arguments: [false, true])
    func overallIntervalsEqualDisjointContributorsAndKnownWorkerCPU(pinned: Bool) throws {
        var feed = OverviewFeed()
        var workers = [
            OverviewFeed.Worker(session: "A", executable: "java", pid: 1, cpuPerSecond: 0.8),
            OverviewFeed.Worker(session: "B", executable: "node", pid: 2, cpuPerSecond: 0.4),
            OverviewFeed.Worker(session: "C", executable: "rustc", pid: 3, cpuPerSecond: 0.15),
            OverviewFeed.Worker(session: "D", executable: "python", pid: 4, cpuPerSecond: 0.05),
        ]
        _ = try feed.advance(workers)
        _ = try feed.advance(workers)
        for index in workers.indices { workers[index].cpuPerSecond *= 2 }
        var overview = ContributorOverview()
        overview.receive(try feed.advance(workers))
        overview.setChartRange(.percent(400))
        if pinned {
            overview.togglePin(for: .session(provider: "claude", session: "A", root: nil))
            overview.showAll = true
        }
        let activity = overview.activity
        #expect(activity.spans.count == 2)
        for (index, expected) in [140.0, 280.0].enumerated() {
            let span = activity.spans[index]
            let total = try #require(activity.totalSamples[index]?.percent(in: span))
            let roots = overview.topLevel.reduce(0.0) { sum, id in
                sum + (activity.samples[id]?[index]?.percent(in: span) ?? 0)
            }
            #expect(abs(total - expected) < 0.000001)
            #expect(abs(roots - expected) < 0.000001)
        }
    }

    @Test func hardwareRangeAndManualChoiceSurviveMonitoringTransitions() throws {
        let topology = ProcessorTopology(
            logicalCPUCount: 8,
            levels: [
                .init(name: "Performance", logicalCPUCount: 4), .init(name: "Efficiency", logicalCPUCount: 4),
            ])
        var state = LiveReportState(cpuTopology: topology)
        #expect(state.overview.activity.ceiling == 400)
        state.receive(try overviewFixture())
        #expect(state.overview.activity.ceiling == 400)
        let original = state.overview.activity
        let totals = state.overview.totals
        state.overview.setChartRange(.percent(800))
        #expect(state.overview.activity.ceiling == 800)
        #expect(state.overview.activity.samples == original.samples)
        #expect(state.overview.activity.spans == original.spans)
        #expect(state.overview.totals == totals)
        state.overview.setChartRange(.percent(.infinity))
        #expect(state.overview.activity.ceiling == 800)
        state.toggleFreeze()
        state.overview.sort(by: .memory, ascending: true)
        state.toggleFreeze()
        state.view = .processes
        state.apply(.chartRange)
        #expect(state.overview.chartRange?.selection == .percent(800))
        state.view = .allContributors
        state.resetCollection()
        #expect(state.overview.activity.ceiling == 800)
        state.receive(try overviewFixture())
        #expect(state.overview.activity.ceiling == 800)
        #expect(state.overview.ascending)
        state.apply(.chartRange)
        #expect(state.overview.chartRange?.selection == .hardware)
        #expect(state.overview.activity.ceiling == 400)
    }

    @Test func lanesDistinguishObservedZeroFromDepartedWorkersAndConserveTotals() throws {
        var overview = ContributorOverview()
        overview.receive(try overviewFixture())
        let activity = overview.activity
        #expect(activity.spans.count == 2)
        #expect(activity.ceiling == 800)
        let quiet = ContributorID.session(provider: "codex", session: "session-1", root: nil)
        let burst = ContributorID.session(provider: "codex", session: "session-22", root: nil)
        let quietValues = try #require(activity.samples[quiet])
        let burstValues = try #require(activity.samples[burst])
        #expect(quietValues.compactMap { $0?.cpuSeconds } == [0, 0])
        #expect(burstValues.first??.cpuSeconds == 1)
        #expect(burstValues.last! == nil)
        let total = overview.topLevel.reduce(0.0) { sum, id in
            sum + (activity.samples[id] ?? []).compactMap { $0?.cpuSeconds }.reduce(0, +)
        }
        #expect(total == overview.totals.recentCPU)
    }

    @Test func pausedPinningRebuildsSyntheticLanesWithoutDuplicatingCPU() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        state.toggleFreeze()
        let id = ContributorID.session(provider: "codex", session: "session-22", root: nil)
        state.overview.select(id)
        state.overview.togglePin()
        func sum(_ overview: ContributorOverview) -> Double {
            overview.topLevel.flatMap { overview.activity.samples[$0] ?? [] }.compactMap { $0?.cpuSeconds }
                .reduce(0, +)
        }
        #expect(sum(state.overview) == state.overview.totals.recentCPU)
        #expect(
            state.overview.activity.samples[.section(.recent)]?.compactMap { $0?.cpuSeconds }.reduce(0, +)
                == 0)
        state.overview.unpinAll()
        #expect(sum(state.overview) == state.overview.totals.recentCPU)
        #expect(
            state.overview.activity.samples[.section(.recent)]?.compactMap { $0?.cpuSeconds }.reduce(0, +)
                == 1)
    }

    @Test func unavailablePresenceDoesNotDeclareWorkersAbsent() throws {
        let original = try overviewFixture()
        let source = try #require(original.recentActivity)
        let recent = RecentActivitySnapshot(
            id: UUID(), runID: source.runID, scope: source.scope, units: source.units,
            current: [], present: [], finalScan: source.finalScan, endedAt: source.endedAt, limited: true,
            target: source.targetSeconds, currentContextAvailable: false, displayUnits: source.displayUnits,
            publish: { value, _ in value }, release: { _ in })
        let snapshot = MonitoringSnapshot(
            cpuAccounting: original.cpuAccounting, timestamp: original.timestamp,
            intervalSeconds: original.intervalSeconds, cpuThresholdPercent: 0, memoryThresholdBytes: 0,
            sampledProcessCount: 0, unreadableProcessCount: 0, findings: [], recentActivity: recent)
        var overview = ContributorOverview()
        overview.receive(snapshot)
        let id = ContributorID.session(provider: "codex", session: "session-1", root: nil)
        let context = overview.workloadContext(for: try #require(overview.nodes[id]))
        #expect(context.contains("presence unavailable"))
        #expect(!context.contains("No longer observed"))
        let rows = overview.visibleRows
        overview.hideNoLongerObserved = true
        #expect(overview.visibleRows == rows)
    }

    @Test(arguments: [2, 8])
    func crossingsMergeWholeSpansWithoutInventingFineTiming(cpuCount: Int) throws {
        let identity = ProcessIdentity(pid: 100, startMicroseconds: 1)
        var ledger = CounterLedger()
        func sample(_ time: Double) -> ProcessSample {
            ProcessSample(
                identity: identity, parentPID: 0, executable: "/bin/java", name: "java", sampledAt: time,
                cpuSeconds: time <= 1 ? time : 1 + (time - 1) * 3, footprintBytes: 1_000_000)
        }
        var baseline = ledger.ingest([sample(0)], listedAt: 0)
        let store = RecentActivityStore()
        for tick in 1...3 {
            let values = tick == 2 ? [] : [sample(Double(tick))]
            let scan = ledger.ingest(values, listedAt: Double(tick))
            var window = AccountingWindow(baseline: baseline)
            let rows = values.map { value in
                HeavyProcess(
                    process: identity, executable: value.executable, name: "java", cpuPercent: nil,
                    footprintBytes: value.footprintBytes, cwd: "/project", command: nil,
                    metadataStatus: .markerRead,
                    attribution: Attribution(
                        provider: .codex, evidence: .marker, context: .unverified, threadID: "crossing",
                        rootSessionID: nil, runtime: nil, terminal: nil, runtimeDirectory: nil,
                        candidateThreadIDs: [], ancestry: []))
            }
            try window.append(scan, rows: rows)
            store.append(window.seal(scope: .agentsOnly), current: window.current, present: window.present)
            baseline = scan
        }
        let recent = try #require(store.snapshot())
        let snapshot = MonitoringSnapshot(
            cpuAccounting: CPUAccounting(
                hostBusyPercent: nil, logicalCPUCount: cpuCount, measuredUserPercent: 0,
                unmeasuredLifetimeCount: 0,
                previousScanSeconds: nil), timestamp: Date(), intervalSeconds: 1, cpuThresholdPercent: 0,
            memoryThresholdBytes: 0, sampledProcessCount: 1, unreadableProcessCount: 0, findings: [],
            recentActivity: recent)
        var overview = ContributorOverview()
        overview.receive(snapshot)
        let id = ContributorID.session(provider: "codex", session: "crossing", root: nil)
        #expect(overview.activity.spans.map(\.duration) == [1, 2])
        let samples = try #require(overview.activity.samples[id])
        #expect(samples.compactMap { $0?.cpuSeconds } == [1, 6])
        #expect(overview.activity.ceiling == Double(cpuCount * 100))
        #expect(
            overview.activity.terminalLane(for: id, width: 12)
                == String(repeating: cpuCount == 8 ? "▁" : "▄", count: 6)
                + String(repeating: cpuCount == 8 ? "▃" : "↑", count: 6))
        for level in 0..<2 {
            let upper = overview.activity.terminalLane(for: id, width: 12, level: level, rows: 3)
            #expect(upper.allSatisfy { " █↑".contains($0) })
        }
        #expect(overview.activity.intervalLabel.contains("unequal durations"))
        #expect(samples[1]?.percent(in: overview.activity.spans[1]) == 300)
        overview.sort(by: .memory)
        #expect(overview.activity.ceiling == Double(cpuCount * 100))
    }
}

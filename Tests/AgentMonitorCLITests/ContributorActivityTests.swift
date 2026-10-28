import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct ContributorActivityTests {
    @Test func lanesDistinguishObservedZeroFromDepartedWorkersAndConserveTotals() throws {
        var overview = ContributorOverview()
        overview.receive(try overviewFixture())
        let activity = overview.activity
        #expect(activity.spans.count == 2)
        #expect(activity.ceiling == 200)
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
    }

    @Test func crossingsMergeWholeSpansWithoutInventingFineTiming() throws {
        let identity = ProcessIdentity(pid: 100, startMicroseconds: 1)
        var ledger = CounterLedger()
        func sample(_ time: Double) -> ProcessSample {
            ProcessSample(
                identity: identity, parentPID: 0, executable: "/bin/java", name: "java", sampledAt: time,
                cpuSeconds: time * 3, footprintBytes: 1_000_000)
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
                hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0, unmeasuredLifetimeCount: 0,
                previousScanSeconds: nil), timestamp: Date(), intervalSeconds: 1, cpuThresholdPercent: 0,
            memoryThresholdBytes: 0, sampledProcessCount: 1, unreadableProcessCount: 0, findings: [],
            recentActivity: recent)
        var overview = ContributorOverview()
        overview.receive(snapshot)
        let id = ContributorID.session(provider: "codex", session: "crossing", root: nil)
        #expect(overview.activity.spans.map(\.duration) == [1, 2])
        let samples = try #require(overview.activity.samples[id])
        #expect(samples.compactMap { $0?.cpuSeconds } == [3, 6])
        #expect(overview.activity.ceiling >= 300)
    }
}

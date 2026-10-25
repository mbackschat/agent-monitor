import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct FrozenGroupingTests {
    @Test(arguments: [false, true])
    func labelChangesPartitionCPUWithoutDuplicatingProcessRows(previouslyExact: Bool) throws {
        let id = ProcessIdentity(pid: 42, startMicroseconds: 1)
        func sample(_ tick: Int) -> ProcessSample {
            ProcessSample(
                identity: id, parentPID: 0, executable: "/bin/worker", name: "worker",
                sampledAt: Double(tick) / 2, cpuSeconds: Double(tick) / 10,
                footprintBytes: 200_000_000)
        }
        var ledger = CounterLedger()
        var window = AccountingWindow(baseline: ledger.ingest([sample(0)], listedAt: 0))
        for tick in 1...10 {
            let value = sample(tick)
            let exact = tick > 3 || previouslyExact
            let owner = Attribution(
                provider: .codex, evidence: exact ? .marker : .runtimeOnly,
                context: .unverified, threadID: exact ? (tick > 3 ? "A" : "B") : nil,
                rootSessionID: nil, runtime: nil, terminal: nil, runtimeDirectory: nil,
                candidateThreadIDs: [], ancestry: [])
            let row = HeavyProcess(
                process: id, executable: value.executable, name: value.name, cpuPercent: nil,
                footprintBytes: value.footprintBytes, cwd: "/fixture", command: nil,
                metadataStatus: .markerRead, attribution: owner)
            try window.append(ledger.ingest([value], listedAt: value.sampledAt), rows: [row])
        }
        let rows = try window.findings(scope: .agentsOnly)
        let store = RecentActivityStore()
        store.append(window.seal(scope: .agentsOnly), current: window.current, present: window.present)
        let snapshot = MonitoringSnapshot(
            cpuAccounting: CPUAccounting(
                hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 20,
                unmeasuredLifetimeCount: 0, previousScanSeconds: nil), timestamp: Date(),
            intervalSeconds: 0.1, cpuThresholdPercent: 0, memoryThresholdBytes: 0,
            sampledProcessCount: 1, unreadableProcessCount: 0, findings: rows,
            window: window.summary, recentActivity: store.snapshot())
        var state = LiveReportState(grouping: .session)
        state.receive(snapshot)
        let a = try #require(state.groups.first { $0.sessionID == "A" })
        let earlier = try #require(state.groups.first { $0.sessionID == (previouslyExact ? "B" : nil) })
        #expect(abs(try #require(a.cpuTotal) - 14) < 1e-9)
        #expect(abs(try #require(earlier.cpuTotal) - 6) < 1e-9)
        #expect(a.memoryGBTotal == 0.2)
        #expect(earlier.memoryGBTotal == 0)
        #expect(state.groups.flatMap(\.processes).map(\.process) == [id])
        #expect(rows.first?.attribution.evidence != .ambiguous)
        let text = TextReport.render(snapshot, grouping: .session)
        #expect(text.contains("14.00%"))
        #expect(text.contains("6.00%"))
        #expect(text.contains("Label changed in window"))
        let overviewCPU = try #require(
            state.overview.nodes[.session(provider: "codex", session: "A", root: nil)])
        #expect(abs(overviewCPU.stats.currentCPU - 0.7) < 1e-9)
        state.togglePin(.process(id))
        #expect(state.projection.unpinnedRows.count == 2)
        #expect(state.groups.allSatisfy { !$0.canFlatten })
        #expect(earlier.label.contains(previouslyExact ? "point-candidate CPU" : "uncertain CPU"))
    }

    @Test func changedRootCorroborationKeepsFrozenCPUAndUniqueCurrentMemory() throws {
        let rootID = ProcessIdentity(pid: 1, startMicroseconds: 1)
        let childID = ProcessIdentity(pid: 2, startMicroseconds: 2)
        func samples(_ tick: Int) -> [ProcessSample] {
            (tick == 2 ? [childID] : [rootID, childID]).map {
                ProcessSample(
                    identity: $0, parentPID: 0, executable: "/bin/worker", name: "worker",
                    sampledAt: Double(tick), cpuSeconds: Double(tick) / 10, footprintBytes: 200_000_000)
            }
        }
        func rows(_ values: [ProcessSample]) -> [HeavyProcess] {
            values.map {
                HeavyProcess(
                    process: $0.identity, executable: $0.executable, name: $0.name,
                    cpuPercent: nil, footprintBytes: $0.footprintBytes, cwd: "/fixture", command: nil,
                    metadataStatus: .markerRead,
                    attribution: Attribution(
                        provider: .codex, evidence: .marker, context: .terminal,
                        threadID: $0.identity == rootID ? "R" : "T", rootSessionID: "R", runtime: rootID,
                        terminal: "tty", runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []))
            }
        }
        var ledger = CounterLedger()
        var window = AccountingWindow(baseline: ledger.ingest(samples(0), listedAt: 0))
        for tick in 1...2 {
            try window.append(ledger.ingest(samples(tick), listedAt: Double(tick)), rows: rows(samples(tick)))
        }
        let groups = SessionGrouping.groups(try window.findings(scope: .agentsOnly), window: window.summary)
        let root = try #require(groups.first { $0.sessionID == "R" })
        let thread = try #require(groups.first { $0.sessionID == "T" })
        #expect(root.cpuTotal == 10)
        #expect(thread.cpuTotal == 5)
        #expect(root.memoryGBTotal == 0)
        #expect(thread.memoryGBTotal == 0.2)
        #expect(!root.canFlatten && !thread.canFlatten)
        #expect(root.labelChangedInWindow && thread.labelChangedInWindow)
        #expect(root.observedCount == 2)
        #expect(groups.flatMap(\.processes).count == 2)
    }
}

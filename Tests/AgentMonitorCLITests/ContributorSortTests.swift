import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct ContributorSortTests {
    @Test func selectedMetricOrdersEveryDisclosedLevelAndSurvivesRefresh() throws {
        var ledger = CounterLedger()
        let store = RecentActivityStore()
        var state = LiveReportState()
        let executables = ["java", "java", "zsh"]
        let rates = [0.1, 3.4, 0.0]
        let memory: [UInt64] = [500_000_000, 100_000_000, 900_000_000]
        func samples(_ tick: Int) -> [ProcessSample] {
            executables.indices.map { index in
                ProcessSample(
                    identity: ProcessIdentity(pid: Int32(index + 1), startMicroseconds: 1),
                    parentPID: 0, executable: "/bin/" + executables[index], name: executables[index],
                    sampledAt: Double(tick), cpuSeconds: rates[index] * Double(tick),
                    footprintBytes: memory[index])
            }
        }
        var previous = ledger.ingest(samples(0), listedAt: 0)
        let session = ContributorID.session(provider: "claude", session: "fixture", root: nil)
        let java = ContributorID.executable(parent: session, name: "java", cwd: "/fixture")
        let zsh = ContributorID.executable(parent: session, name: "zsh", cwd: "/fixture")
        for tick in 1...3 {
            let values = samples(tick)
            let scan = ledger.ingest(values, listedAt: Double(tick))
            var window = AccountingWindow(baseline: previous)
            try window.append(
                scan,
                rows: values.map { value in
                    HeavyProcess(
                        process: value.identity, executable: value.executable, name: value.name,
                        cpuPercent: nil, footprintBytes: value.footprintBytes, cwd: "/fixture", command: nil,
                        metadataStatus: .markerRead,
                        attribution: Attribution(
                            provider: .claude, evidence: .marker, context: .unverified,
                            threadID: "fixture", rootSessionID: nil, runtime: nil, terminal: nil,
                            runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []))
                })
            store.append(window.seal(scope: .agentsOnly), current: window.current, present: window.present)
            state.receive(
                MonitoringSnapshot(
                    cpuAccounting: CPUAccounting(
                        hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 350,
                        unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
                    timestamp: Date(), intervalSeconds: 0.1, cpuThresholdPercent: 0, memoryThresholdBytes: 0,
                    sampledProcessCount: 3, unreadableProcessCount: 0, findings: [],
                    recentActivity: store.snapshot()))
            if tick == 1 {
                state.overview.toggle(session)
                state.overview.toggle(java)
            }
            let totals = state.overview.totals
            let selection = state.overview.selection
            let disclosure = state.overview.open
            #expect(state.overview.nodes[session]?.children == (tick == 2 ? [zsh, java] : [java, zsh]))
            state.overview.sort(by: .cpu)
            #expect(state.overview.nodes[session]?.children == [java, zsh])
            #expect(
                state.overview.nodes[java]?.children.compactMap { state.overview.nodes[$0]?.process?.pid }
                    == [2, 1])
            let cpuRows = state.overview.visibleRows
            #expect(cpuRows.filter { $0.node.process != nil }.compactMap { $0.node.process?.pid } == [2, 1])
            let lines = ContributorLayout.lines(state: state, width: 120, height: 40).map(\.text)
            let javaLine = try #require(lines.firstIndex { $0.contains("java ×2") })
            let zshLine = try #require(lines.firstIndex { $0.contains("zsh") })
            #expect(javaLine < zshLine)
            state.overview.sort(by: .memory)
            #expect(state.overview.nodes[session]?.children == [zsh, java])
            #expect(
                state.overview.nodes[java]?.children.compactMap { state.overview.nodes[$0]?.process?.pid }
                    == [1, 2])
            #expect(state.overview.totals == totals)
            #expect(state.overview.selection == selection)
            #expect(state.overview.open == disclosure)
            if tick == 2 { state.overview.sort(by: .cpu) }
            previous = scan
        }
    }
}

extension ContributorSortTests {
    private func session(_ name: String) -> ContributorID {
        .session(provider: "claude", session: name, root: nil)
    }

    /// Locks the refresh rule shared by every level: survivors keep their order only while no
    /// contributor below exceeds one above it by more than the 1.2× ranking band.
    @Test func refreshPromotesContributorsBeyondTheRankingBandAtEveryLevel() throws {
        var feed = OverviewFeed()
        var overview = ContributorOverview()
        func tick(_ a: Double, _ b: Double, java: Double, rustc: Double) throws {
            overview.receive(
                try feed.advance([
                    .init(session: "alpha", executable: "java", pid: 1, cpuPerSecond: a * java),
                    .init(session: "alpha", executable: "rustc", pid: 2, cpuPerSecond: a * rustc),
                    .init(session: "beta", executable: "node", pid: 3, cpuPerSecond: b),
                ]))
        }
        try tick(0, 0, java: 0, rustc: 0)
        try tick(4, 0.5, java: 0.9, rustc: 0.1)
        #expect(overview.main == [session("alpha"), session("beta")])
        let java = ContributorID.executable(parent: session("alpha"), name: "java", cwd: "/fixture")
        let rustc = ContributorID.executable(parent: session("alpha"), name: "rustc", cwd: "/fixture")
        #expect(overview.nodes[session("alpha")]?.children == [java, rustc])

        try tick(0.4, 3, java: 0.1, rustc: 0.9)
        #expect(overview.main == [session("beta"), session("alpha")])
        #expect(overview.nodes[session("alpha")]?.children == [rustc, java])

        // Within the band, a refresh must not reshuffle rows under the user's selection.
        try tick(3.3, 3, java: 0.52, rustc: 0.48)
        #expect(overview.main == [session("beta"), session("alpha")])
        #expect(overview.nodes[session("alpha")]?.children == [rustc, java])
    }

    @Test func largerNewcomerIsNotAppendedBelowSmallerIncumbents() throws {
        var feed = OverviewFeed()
        var overview = ContributorOverview()
        func tick(_ workers: [OverviewFeed.Worker]) throws { overview.receive(try feed.advance(workers)) }
        let incumbents: [OverviewFeed.Worker] = [
            .init(session: "alpha", executable: "java", pid: 1, cpuPerSecond: 0.5),
            .init(session: "beta", executable: "node", pid: 2, cpuPerSecond: 0.4),
        ]
        try tick(incumbents)
        try tick(incumbents)
        let gamma = OverviewFeed.Worker(session: "gamma", executable: "rustc", pid: 3, cpuPerSecond: 8)
        // The first reading of a lifetime born before the listing only establishes its baseline.
        try tick(incumbents + [gamma])
        try tick(incumbents + [gamma])
        #expect(overview.main == [session("gamma"), session("alpha"), session("beta")])
    }
}

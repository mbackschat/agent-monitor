import AgentMonitorPresentation
import Testing

@testable import AgentMonitorCore

@Suite struct PinAdmissionTests {
    private func snapshot(count: Int, name: String = "worker", session: String? = nil) throws
        -> MonitoringSnapshot
    {
        var feed = OverviewFeed()
        let workers = (0..<count).map {
            OverviewFeed.Worker(
                session: session ?? "session-\($0)", executable: name, pid: Int32($0 + 1), cpuPerSecond: 0.6)
        }
        _ = try feed.advance(workers)
        let recent = try feed.advance(workers)
        let rows = workers.map { worker in
            HeavyProcess(
                process: ProcessIdentity(pid: worker.pid, startMicroseconds: 1),
                executable: "/bin/" + worker.executable, name: worker.executable,
                cpuPercent: 60, footprintBytes: 1_000_000, cwd: worker.cwd,
                command: nil, metadataStatus: .markerRead,
                attribution: Attribution(
                    provider: .claude, evidence: .marker, context: .unverified,
                    threadID: worker.session, rootSessionID: nil, runtime: nil,
                    terminal: nil, runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []))
        }
        return MonitoringSnapshot(
            cpuAccounting: recent.cpuAccounting, timestamp: recent.timestamp, intervalSeconds: 0.1,
            cpuThresholdPercent: 0, memoryThresholdBytes: 0, sampledProcessCount: rows.count,
            unreadableProcessCount: 0, findings: rows, recentActivity: recent.recentActivity)
    }

    @Test func processPinsHaveCountAndByteAdmissionButMissingPinsCanBeRemoved() throws {
        var state = LiveReportState(grouping: .none)
        let sample = try snapshot(count: 257)
        state.receive(sample)
        for row in sample.findings { state.togglePin(.process(row.process)) }
        #expect(state.pins.count == 256)
        #expect(state.notice != nil)
        let first = try #require(state.pins.first)
        state.receive(try snapshot(count: 0))
        state.togglePin(first.id)
        #expect(state.pins.count == 255)
        #expect(!state.pins.contains { $0.id == first.id })
        var oversized = LiveReportState(grouping: .none)
        oversized.receive(try snapshot(count: 1, name: String(repeating: "x", count: 70_000)))
        oversized.overview.enabled = false
        oversized.toggleSelectedPin()
        #expect(oversized.pins.isEmpty)
    }

    @Test func overviewPinsBoundStoredIdentityAndRemoveMissingPlaceholders() throws {
        var state = LiveReportState()
        let sample = try snapshot(count: 257)
        state.receive(sample)
        for row in sample.findings {
            state.overview.select(
                .session(provider: "claude", session: try #require(row.attribution.threadID), root: nil))
            state.overview.togglePin()
        }
        #expect(state.overview.pinned.count == 256)
        let first = try #require(state.overview.pinned.first)
        state.receive(try snapshot(count: 0))
        state.overview.select(first)
        state.overview.togglePin()
        #expect(!state.overview.pinned.contains(first))
        #expect(!state.overview.visibleRows.contains { $0.id == first })
        var oversized = LiveReportState()
        oversized.receive(try snapshot(count: 1, session: String(repeating: "s", count: 70_000)))
        oversized.overview.togglePin()
        #expect(oversized.overview.pinned.isEmpty)
    }

    @Test func cumulativePinTextRefusesAdditionWithoutEvictingExistingPins() throws {
        var state = LiveReportState(grouping: .none)
        let sample = try snapshot(count: 64, name: String(repeating: "x", count: 1024))
        state.receive(sample)
        state.overview.enabled = false
        for row in sample.findings { state.togglePin(.process(row.process)) }
        #expect(state.pins.count == 63)
        #expect(state.pins.reduce(0) { $0 + $1.label.utf8.count } <= 64 * 1024)
        #expect(
            LiveReportLayout.lines(state: state, width: 80, height: 24).contains {
                $0.text.contains("Pin limit")
            })
        let removed = try #require(state.pins.first).id
        state.togglePin(removed)
        state.togglePin(.process(try #require(sample.findings.last).process))
        #expect(state.pins.count == 63 && state.notice == nil)

        var overview = LiveReportState()
        overview.receive(try snapshot(count: 1, session: "a" + String(repeating: "s", count: 40_000)))
        overview.overview.togglePin()
        let first = overview.overview.pinned
        overview.receive(try snapshot(count: 1, session: "b" + String(repeating: "s", count: 40_000)))
        let next = ContributorID.session(
            provider: "claude", session: "b" + String(repeating: "s", count: 40_000), root: nil)
        overview.overview.select(next)
        overview.overview.togglePin()
        #expect(overview.overview.pinned == first)
        #expect(
            ContributorLayout.lines(state: overview, width: 80, height: 24).contains {
                $0.text.contains("Pin limit")
            })
    }

    @Test(arguments: [false, true])
    func unpinAllClearsBothViewsEvenWhenTheSelectedViewIsEmpty(overview: Bool) throws {
        var state = LiveReportState()
        let sample = try snapshot(count: 1)
        state.receive(sample)
        state.togglePin(.process(try #require(sample.findings.first).process))
        state.overview.togglePin()
        #expect(state.pins.count == 1 && state.overview.pinned.count == 1)
        state.receive(try snapshot(count: 0))
        state.overview.enabled = overview
        let shortcut = try #require(ReportShortcut(rawValue: "u"))
        state.apply(shortcut)
        #expect(state.pins.isEmpty && state.overview.pinned.isEmpty)
        #expect(!state.overview.visibleRows.contains { $0.node.title.contains("Pinned") })
    }
}

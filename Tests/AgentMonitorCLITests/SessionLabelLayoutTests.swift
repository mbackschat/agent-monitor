import AgentMonitorCore
import AgentMonitorPresentation
import Testing

@Suite struct SessionLabelLayoutTests {
    private let sessions = [
        "abcdabcd-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "12345678-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    ]

    private func state(
        directories: [String] = ["/work/alpha/project", "/tmp/alpha/project"], memory: UInt64 = 320_000_000
    ) throws
        -> LiveReportState
    {
        let workers = sessions.enumerated().map { index, session in
            OverviewFeed.Worker(
                session: session, executable: "java", pid: Int32(index + 1),
                cpuPerSecond: index == 0 ? 0.9 : 0.8, memory: memory,
                cwd: directories[index])
        }
        var feed = OverviewFeed()
        var state = LiveReportState()
        state.receive(try feed.advance(workers))
        state.receive(try feed.advance(workers))
        return state
    }

    @Test(arguments: [40, 80, 100, 160], [UInt64(320_000_000), 1_500_000_000_000_000])
    func bothSessionIdentitiesAndContributionsStayVisible(width: Int, memory: UInt64) throws {
        var state = try state(memory: memory)
        let lines = ContributorLayout.lines(state: state, width: width, height: 40)
        let text = lines.map(\.text).joined(separator: "\n")
        // At 40 columns beside a petabyte figure the provider name abbreviates so the eight-character
        // session ID survives (docs/usage.md: IDs keep eight characters; names abbreviate).
        #expect(text.contains("cla"))
        for (index, session) in sessions.enumerated() {
            state.overview.select(.session(provider: "claude", session: session, root: nil))
            let selected = ContributorLayout.lines(state: state, width: width, height: 40)
            let block = selectedBlock(selected)
            #expect(block.contains(session.prefix(8)))
            #expect(block.contains(index == 0 ? "90.0%" : "80.0%"))
            #expect(block.contains(memory == 320_000_000 ? "320.0 MB" : "1500000.0 GB"))
            #expect(block.contains(index == 0 ? "work" : "tmp"))
        }
        #expect(lines.allSatisfy { TerminalCells.width($0.text) <= width })
    }

    @Test(arguments: [40, 80, 120], [8, 40])
    func longExecutableKeepsDirectoryAndResourcesInOneBlock(width: Int, height: Int) throws {
        var feed = OverviewFeed()
        let workers = ["/work/api", "/tmp/web"].enumerated().map { index, cwd in
            OverviewFeed.Worker(
                session: sessions[0], executable: "rust-analyzer-proc-macro-srv", pid: Int32(index + 1),
                cpuPerSecond: index == 0 ? 0.9 : 0.8, memory: 320_000_000, cwd: cwd)
        }
        var state = LiveReportState()
        state.receive(try feed.advance(workers))
        state.receive(try feed.advance(workers))
        state.overview.toggle(try #require(state.overview.main.first))
        let families = state.overview.visibleRows.filter {
            if case .executable = $0.id { true } else { false }
        }
        #expect(families.count == 2)
        for family in families {
            state.overview.select(family.id)
            let lines = ContributorLayout.lines(state: state, width: width, height: height)
            let selected = selectedBlock(lines)
            let directory = try #require(family.node.inspectionFields.first { $0.label == "Directory" }).value
            #expect(selected.contains("rust-analyzer-proc-macro-srv"), "\(selected)")
            #expect(selected.contains(directory), "\(selected)")
            #expect(selected.contains(directory == "/work/api" ? "90.0%" : "80.0%"), "\(selected)")
            #expect(selected.contains("320.0 MB"), "\(selected)")
            #expect(lines.count <= height)
            #expect(lines.allSatisfy { TerminalCells.width($0.text) <= width })
        }
    }

    @Test func clippedDirectoryLabelsRetainExplicitFullPathInspection() throws {
        let directories = [
            "/workspace-client-common-common-common-alpha/shared/project",
            "/workspace-client-common-common-common-beta/shared/project",
        ]
        var state = try state(directories: directories)
        for (index, session) in sessions.enumerated() {
            state.overview.select(.session(provider: "claude", session: session, root: nil))
            state.overview.toggleDetails()
            let lines = ContributorLayout.lines(state: state, width: 40, height: 60)
            let text = lines.map(\.text).joined().filter { !$0.isWhitespace }
            #expect(text.contains(directories[index]))
        }
    }

    @Test(arguments: [0, 1])
    func shortViewportKeepsSessionIdentityAndResourcesTogether(selected: Int) throws {
        var state = try state()
        state.overview.select(.session(provider: "claude", session: sessions[selected], root: nil))
        let lines = ContributorLayout.lines(state: state, width: 40, height: 11)
        #expect(lines.contains { $0.text.contains(sessions[selected].prefix(8)) })
        for (index, session) in sessions.enumerated() {
            let identity = lines.firstIndex { $0.text.contains(session.prefix(8)) }
            let resources = lines.firstIndex { $0.text.contains(index == 0 ? "90.0%" : "80.0%") }
            #expect((identity == nil) == (resources == nil))
            if let identity, let resources { #expect(resources == identity) }
        }
    }
    @Test(arguments: [0, 1], [false, true])
    func minimumViewportKeepsSelectedResponsibilityBesideCoverage(selected: Int, filtered: Bool) throws {
        var feed = OverviewFeed()
        var workers = sessions.enumerated().map { index, session in
            OverviewFeed.Worker(
                session: session, executable: "java", pid: Int32(index + 1),
                cpuPerSecond: index == 0 ? 0.9 : 0.8, memory: 320_000_000,
                cwd: "/work/backend")
        }
        workers.append(
            OverviewFeed.Worker(
                session: "cccccccc-cccc-4ccc-8ccc-cccccccccccc", executable: "node", pid: 3,
                cpuPerSecond: 0, memory: nil))
        var state = LiveReportState()
        state.receive(try feed.advance(workers))
        state.receive(
            try feed.advance(
                workers, failures: [.permissionDenied, .identityMismatch, .lookupUnavailable],
                overrun: true))
        if filtered { state.setThresholds(Thresholds(cpuPercent: 25)) }
        state.overview.select(.session(provider: "claude", session: sessions[selected], root: nil))
        let lines = ContributorLayout.lines(state: state, width: 40, height: 8)
        let identity = try #require(lines.firstIndex { $0.text.contains(sessions[selected].prefix(8)) })
        let resources = lines[identity].text
        #expect(resources.contains(selected == 0 ? "90.0%" : "80.0%"))
        #expect(resources.contains("320.0 MB"))
        #expect(showsCoverageWarningBadge(lines))
        let text = lines.map(\.text).joined(separator: "\n")
        #expect(text.contains("q/Ctrl-C quit"))
        #expect(text.contains("p pause"))
        #expect(text.contains("? help"))
        if filtered {
            #expect(text.contains(ThresholdContext.text(state.thresholds)))
        }
        #expect(lines.count <= 8)
    }

}

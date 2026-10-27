import AgentMonitorCore
import AgentMonitorPresentation
import Testing

@Suite struct ReportReferenceTests {
    @Test func liveProcessHeaderKeepsInspectionContextAndMovesCollectionDetailsToDiagnostics() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture(includeProcesses: true))
        state.overview.enabled = false
        let overview = LiveReportLayout.lines(state: state, width: 140, height: 30).map(\.text).joined(
            separator: "\n")
        #expect(!overview.contains("CPU: host"))
        #expect(overview.contains("shown") && overview.contains("sampled"))
        #expect(overview.contains("All observed processes"))
        #expect(!overview.contains("without data"))
        #expect(!overview.contains("point candidates"))
        state.showReference(.diagnostics)
        let diagnostics = ReportReferenceLayout.content(state: state, page: .diagnostics).map(\.text).joined(
            separator: "\n")
        #expect(diagnostics.contains("CPU: host"))
        #expect(diagnostics.contains("without data"))
        #expect(diagnostics.contains(ProviderRuntimeAvailability.sessionListingUnavailableReason))
        #expect(diagnostics.contains(ProviderRuntimeAvailability.messagingUnavailableReason))
    }

    @Test(arguments: [40, 80, 140])
    func passivePagesPreserveInspectionPauseAndSupportBoundedScrolling(width: Int) throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        state.overview.toggleDetails()
        state.toggleFreeze()
        let original = state
        state.showReference(.glossary)
        let top = LiveReportLayout.lines(state: state, width: width, height: 12)
        #expect(top.first?.text == "Help & glossary")
        #expect(top.map(\.text).joined().contains("Esc back"))
        #expect(top.map(\.text).joined().contains("D diagnostics"))
        state.scrollReference(by: Int.max, width: width, height: 12)
        #expect(state.referenceOffset > 0)
        #expect(LiveReportLayout.lines(state: state, width: width, height: 12) != top)
        state.scrollReference(by: -Int.max, width: width, height: 12)
        #expect(state.referenceOffset == 0)
        #expect(LiveReportLayout.lines(state: state, width: width, height: 12) == top)
        state.showReference(.diagnostics)
        #expect(state.referenceOffset == 0)
        #expect(state.frozen)
        #expect(state.overview.selection == original.overview.selection)
        #expect(state.overview.detailsVisible == original.overview.detailsVisible)
        state.dismissReference()
        #expect(state == original)
        #expect(top.allSatisfy { TerminalCells.width($0.text) <= width })
    }

    @Test func wideningAHelpPageAtItsEndKeepsOneLineScrollingResponsive() {
        var state = LiveReportState()
        state.showReference(.glossary)
        state.scrollReference(by: Int.max, width: 40, height: 12)
        let bottom = LiveReportLayout.lines(state: state, width: 140, height: 12)
        state.scrollReference(by: -1, width: 140, height: 12)
        #expect(LiveReportLayout.lines(state: state, width: 140, height: 12) != bottom)
    }

    @Test(arguments: [40, 80, 140])
    func diagnosticsRetainFullCoverageWhileOverviewUsesOneActionableRow(width: Int) throws {
        var state = LiveReportState()
        var feed = OverviewFeed()
        let workers = [OverviewFeed.Worker(session: "A", executable: "java", pid: 1, cpuPerSecond: 0.5)]
        _ = try feed.advance(workers)
        state.receive(
            try feed.advance(workers, failures: [.permissionDenied, .permissionDenied, .permissionDenied]))
        let live = LiveReportLayout.lines(state: state, width: width, height: 24)
        #expect(live.contains { $0.text.contains("D diagnostics") })
        #expect(live.contains { $0.style == .warning })
        #expect(!live.contains { $0.text.contains("PID detail") })
        #expect(live.map(\.text).joined().contains("? help"))
        state.showReference(.diagnostics)
        let details = ReportReferenceLayout.content(state: state, page: .diagnostics)
        let text = details.map(\.text).joined(separator: "\n")
        #expect(text.contains("Read failures: 3 same-user PIDs"))
        #expect(text.contains("Their CPU and memory are unmeasured"))
        #expect(text.contains("Sampled:"))
        #expect(text.contains("ownership is unknown"))
        #expect(LiveReportLayout.lines(state: state, width: width, height: 12).first?.text == "Diagnostics")
    }

    @Test(arguments: [60, 80, 140])
    func overviewCountNamesProcessesRatherThanTime(width: Int) throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        let heading = try #require(
            LiveReportLayout.lines(state: state, width: width, height: 30).first { $0.style == .heading })
        #expect(heading.text.contains("PROCS"))
        #expect(!heading.text.contains("NOW"))
    }
}

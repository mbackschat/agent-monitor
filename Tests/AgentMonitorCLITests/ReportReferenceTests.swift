import AgentMonitorCore
import AgentMonitorPresentation
import Testing

@Suite struct ReportReferenceTests {
    @Test(arguments: [ContributorChartStyle.compact, .stacked])
    func keyboardChartLegendFitsTheNarrowestHelpColumn(style: ContributorChartStyle) throws {
        var state = LiveReportState()
        state.chartStyle = style
        let source = ReportReferenceLayout.content(state: state, page: .keyboard)
        let start = try #require(source.lastIndex { $0.text == "Contributor CPU charts" })
        let chart = source.suffix(from: start)
        #expect(chart.allSatisfy { TerminalCells.width($0.text) <= 48 })
        for symbol in ["█", "·", "_", "~"] {
            #expect(chart.contains { $0.runs.first?.text == symbol })
        }
        #expect(chart.contains { $0.runs.contains { $0.style == .shortcut && $0.text == "G" } })
    }

    @Test func historicalFilterIsDiscoverableAndReversibleWithoutChangingTotals() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture(includeProcesses: true))
        state.view = .allContributors
        let rows = state.overview.visibleRows
        let totals = state.overview.totals
        let activity = state.overview.activity
        let help = ReportReferenceLayout.content(state: state, page: .keyboard)
        #expect(help.contains { $0.text == "H hide/show no longer observed" })
        state.overview.hideNoLongerObserved.toggle()
        #expect(state.overview.hideNoLongerObserved)
        #expect(state.overview.visibleRows.count < rows.count)
        #expect(state.overview.visibleRows.allSatisfy { !$0.node.stats.isNoLongerObserved })
        let lines = ContributorLayout.lines(state: state, width: 100, height: 30)
        #expect(lines.contains { $0.text.contains("H show no longer observed") })
        #expect(state.overview.totals == totals)
        #expect(state.overview.activity == activity)
        state.overview.hideNoLongerObserved.toggle()
        #expect(state.overview.visibleRows == rows)
    }

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

    @Test(arguments: [40, 80, 140], [ReportReferencePage.glossary, .keyboard])
    func passivePagesPreserveInspectionPauseAndSupportBoundedScrolling(width: Int, page: ReportReferencePage)
        throws
    {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        state.overview.toggleDetails()
        state.toggleFreeze()
        let shortcuts = ReportReferenceLayout.content(state: state, page: .keyboard).map(\.text).joined(
            separator: "\n")
        #expect(shortcuts.contains("i show/hide contributor details"))
        #expect(
            !shortcuts.contains("k review") && !shortcuts.contains("n sort")
                && !shortcuts.contains("s messaging"))
        let original = state
        state.showReference(page)
        let top = LiveReportLayout.lines(state: state, width: width, height: 12)
        #expect(top.first?.text.hasPrefix(page.title) == true)
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

    @Test(arguments: [100, 120, 160], [ReportView.mainContributors, .processes])
    func wideKeyboardHelpBalancesSectionsAndPreservesStyledShortcuts(width: Int, view: ReportView) throws {
        var state = LiveReportState()
        state.receive(try overviewFixture(includeProcesses: true))
        state.view = view
        state.showReference(.keyboard)
        let source = ReportReferenceLayout.content(state: state, page: .keyboard)
        let lines = ReportReferenceLayout.lines(state: state, width: width, height: 60)
        let first = lines[1]
        #expect(first.runs.filter { $0.style == .title }.count == 2)
        let secondHeading = try #require(first.runs.last { $0.style == .title })
        let headingIndex = try #require(first.runs.lastIndex { $0 == secondHeading })
        let secondColumn = TerminalCells.width(first.runs[..<headingIndex].map(\.text).joined())
        #expect(secondColumn < width / 2)

        let expectedKeys = source.flatMap(\.runs).filter { $0.style == .shortcut }.map(\.text).sorted()
        let renderedKeys = lines.flatMap(\.runs).filter { $0.style == .shortcut }.map(\.text).sorted()
        #expect(renderedKeys == expectedKeys)
        for heading in source.filter({ $0.style == .title }) {
            #expect(lines.flatMap(\.runs).filter { $0.style == .title && $0.text == heading.text }.count == 1)
        }
        #expect(lines.allSatisfy { TerminalCells.width($0.text) <= width })
        #expect(lines[57].text == String(repeating: "─", count: width))
        let singleColumnRows = source.count
        #expect(
            ReportReferenceLayout.maximumOffset(state: state, width: width, height: 12) < singleColumnRows - 8
        )
    }

    @Test func narrowKeyboardHelpRetainsSectionReadingOrder() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        state.showReference(.keyboard)
        let source = ReportReferenceLayout.content(state: state, page: .keyboard)

        let lines = ReportReferenceLayout.lines(state: state, width: 80, height: 80)
        #expect(Array(lines.dropFirst().prefix(source.count)) == source)
    }

    @Test(arguments: [ReportReferencePage.glossary, .keyboard])
    func wideningAHelpPageAtItsEndKeepsOneLineScrollingResponsive(page: ReportReferencePage) {

        var state = LiveReportState()
        state.showReference(page)
        state.scrollReference(by: Int.max, width: 40, height: 12)
        let bottom = LiveReportLayout.lines(state: state, width: 140, height: 12)
        state.scrollReference(by: -1, width: 140, height: 12)
        #expect(LiveReportLayout.lines(state: state, width: 140, height: 12) != bottom)
    }

    @Test(arguments: [40, 80, 140])
    func diagnosticsRetainFullCoverageWhileOverviewUsesAnActionBadge(width: Int) throws {
        var state = LiveReportState()
        var feed = OverviewFeed()
        let workers = [OverviewFeed.Worker(session: "A", executable: "java", pid: 1, cpuPerSecond: 0.5)]
        _ = try feed.advance(workers)
        state.receive(
            try feed.advance(workers, failures: [.permissionDenied, .permissionDenied, .permissionDenied]))
        let live = LiveReportLayout.lines(state: state, width: width, height: 24)
        #expect(live.contains { $0.text.contains(width < 60 ? "D !" : "D diagnostics !") })
        #expect(state.displayCoverageStatus.severity == .warning)
        #expect(!live.contains { $0.text.contains("PID detail") || $0.text.contains("Read failures:") })
        #expect(live.map(\.text).joined().contains("? help"))
        state.showReference(.diagnostics)
        let details = ReportReferenceLayout.content(state: state, page: .diagnostics)
        let text = details.map(\.text).joined(separator: "\n")
        #expect(text.contains("Read failures: 3 same-user PIDs"))
        #expect(text.contains("Their CPU and memory are unmeasured"))
        #expect(text.contains("Sampled:"))
        #expect(text.contains("ownership is unknown"))
        #expect(
            LiveReportLayout.lines(state: state, width: width, height: 12).first?.text.hasPrefix(
                "Diagnostics") == true)
    }

}

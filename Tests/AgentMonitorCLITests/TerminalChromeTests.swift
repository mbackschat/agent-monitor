import AgentMonitorPresentation
import Testing

@Suite struct TerminalChromeTests {
    @Test(arguments: [ReportView.mainContributors, .sessions, .processes], [40, 120])
    func reportChromeKeepsViewSortAndEssentialControls(view: ReportView, width: Int) throws {
        var state = LiveReportState()
        state.receive(try overviewFixture(includeProcesses: true))
        state.view = view
        state.sortCurrentView(by: .memory)
        let lines = LiveReportLayout.lines(state: state, width: width, height: 30)
        let text = lines.map(\.text).joined(separator: "\n")
        #expect(lines.first?.text.contains("Memory ↓") == true)
        #expect(text.contains("v view") && text.contains("g group"))
        #expect(text.contains("q/Ctrl-C quit"))
        #expect(!text.contains("Read failures:") && !text.contains("same-user PIDs"))
        #expect(lines.count == 30)
    }

    @Test(arguments: [40, 120], [24, 60])
    func shortContributorDetailsLeaveFooterAtScreenBottom(width: Int, height: Int) throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        state.overview.select(.section(.recent))
        state.showDetails()
        let lines = LiveReportLayout.lines(state: state, width: width, height: height)
        #expect(lines.count == height)
        #expect(lines.last?.text.contains("q/Ctrl-C quit") == true)
    }

    @Test(arguments: [ReportView.mainContributors, .sessions, .processes], [60, 120])
    func pagingMovesThroughTableAndKeepsSelectionInView(view: ReportView, width: Int) throws {
        var state = LiveReportState()
        state.receive(try overviewFixture(includeProcesses: true))
        state.view = view
        if state.showsOverview { state.overview.showAll = true }
        let original =
            state.showsOverview
            ? String(describing: state.overview.selection) : String(describing: state.selection)
        let before = LiveReportLayout.lines(state: state, width: width, height: 16)
        #expect(before.map(\.text).joined().contains("↓"))
        LiveReportLayout.page(state: &state, width: width, height: 16, direction: 1)
        let next =
            state.showsOverview
            ? String(describing: state.overview.selection) : String(describing: state.selection)
        #expect(next != original)
        let after = LiveReportLayout.lines(state: state, width: width, height: 16)
        #expect(after.contains { $0.style == .selected })
        #expect(after != before)
        LiveReportLayout.page(state: &state, width: width, height: 16, direction: -1)
        #expect(
            LiveReportLayout.lines(state: state, width: width, height: 16).contains { $0.style == .selected })
    }

    @Test(arguments: [ReportReferencePage.keyboard, .glossary, .diagnostics])
    func halfPageUsesViewportCapacityAndPreservesSelection(page: ReportReferencePage) throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        let selection = state.overview.selection
        state.showReference(page)
        LiveReportLayout.page(state: &state, width: 80, height: 12, direction: 1)
        #expect(state.referenceOffset == 4)
        LiveReportLayout.page(state: &state, width: 80, height: 12, direction: -1)
        #expect(state.referenceOffset == 0)
        #expect(state.overview.selection == selection)
    }

    @Test func contributorPlotsOccupyOneTextLineEach() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        let lines = LiveReportLayout.lines(state: state, width: 120, height: 60)
        let charts = lines.filter { line in
            line.runs.contains {
                $0.style == .separator && $0.text.contains(where: { "▁▂▃▄▅▆▇█↑·_".contains($0) })
            }
        }
        #expect(charts.count == state.overview.visibleRows.count + 1)
    }

    @Test func contributorDetailPagingKeepsTableSelectionAndSignalsMoreContent() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        state.showDetails()
        let selected = state.overview.selection
        let before = LiveReportLayout.lines(state: state, width: 80, height: 24)
        #expect(before.contains { $0.text.hasPrefix("DETAILS") && $0.text.contains("↓") })
        LiveReportLayout.page(state: &state, width: 80, height: 24, direction: 1)
        #expect(state.overview.detailOffset > 0)
        #expect(state.overview.selection == selected)
        LiveReportLayout.page(state: &state, width: 80, height: 24, direction: -1)
        #expect(state.overview.detailOffset == 0)
    }

    @Test(arguments: [ReportReferencePage.keyboard, .glossary])
    func referencesExplainChartSymbolsAndShowScrollPosition(page: ReportReferencePage) {
        var state = LiveReportState()
        state.showReference(page)
        let content = ReportReferenceLayout.content(state: state, page: page).map(\.text).joined()
        #expect(content.contains("↑ above range"))
        #expect(content.contains("· no measurement"))
        let lines = LiveReportLayout.lines(state: state, width: 80, height: 12)
        #expect(lines.first?.text.contains("1–8/") == true)
        #expect(lines.map(\.text).joined().contains("Space"))
    }
}

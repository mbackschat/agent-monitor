import Testing

@testable import AgentMonitorPresentation

@Suite struct TableViewportTests {
    private func state(view: ReportView) throws -> LiveReportState {
        var state = LiveReportState()
        state.receive(try overviewFixture(includeProcesses: true))
        state.view = view
        if state.showsOverview {
            for _ in 0..<4 {
                for row in state.overview.visibleRows {
                    state.overview.setDisclosure(expanded: true, for: row.id)
                }
            }
        }
        return state
    }

    private func rail(_ lines: [ReportLine], width: Int) -> String {
        String(
            lines.filter { TerminalCells.width($0.text) == width }.compactMap { line in
                guard let last = line.text.last, "│█↑↓".contains(last) else { return nil }
                return last
            })
    }

    @Test(arguments: [ReportView.allContributors, .sessions, .processes], [60, 120])
    func pagingMovesTheViewportAndItsScrollbar(view: ReportView, width: Int) throws {
        var state = try state(view: view)
        let before = LiveReportLayout.lines(state: state, width: width, height: 20)
        let firstRail = rail(before, width: width)
        #expect(firstRail.contains("█"))
        #expect(firstRail.last == "↓")
        let open = state.overview.open
        let totals = state.overview.totals
        LiveReportLayout.page(state: &state, width: width, height: 20, direction: 1)
        let after = LiveReportLayout.lines(state: state, width: width, height: 20)
        #expect(rail(after, width: width).first == "↑")
        #expect(after.contains { $0.style == .selected })
        #expect(state.overview.open == open)
        #expect(state.overview.totals == totals)
        LiveReportLayout.page(state: &state, width: width, height: 20, direction: -1)
        let restored = LiveReportLayout.lines(state: state, width: width, height: 20)
        #expect(rail(restored, width: width).first != "↑")
        #expect(restored.allSatisfy { TerminalCells.width($0.text) <= width })
    }

    @Test(arguments: [ReportView.allContributors, .sessions, .processes])
    func scrollbarReachesTheBottomAndDisappearsWhenEverythingFits(view: ReportView) throws {
        var state = try state(view: view)
        for _ in 0..<100 {
            LiveReportLayout.page(state: &state, width: 120, height: 20, direction: 1, half: false)
        }
        let bottom = LiveReportLayout.lines(state: state, width: 120, height: 20)
        let lastRail = rail(bottom, width: 120)
        #expect(lastRail.first == "↑")
        #expect(lastRail.contains("█"))
        #expect(lastRail.last != "↓")
        #expect(bottom.contains { $0.style == .selected })
        let tall = LiveReportLayout.lines(state: state, width: 120, height: 400)
        #expect(rail(tall, width: 120).isEmpty)
    }
    @Test func mixedHeightRowsKeepTheThumbProportionalAndTheAnchorStable() throws {
        let ids = Array(0..<20)
        let heights = ids.map { $0.isMultiple(of: 2) ? 2 : 4 }
        let first = TerminalTableViewport(ids: ids, heights: heights, capacity: 12, anchor: nil, selection: 0)
        let next = try #require(first.page(direction: 1, half: true))
        let page = TerminalTableViewport(
            ids: ids, heights: heights, capacity: 12, anchor: next.anchor, selection: next.selection)
        #expect(page.start == 6)
        #expect(page.end == 18)
        let body = Array(repeating: ReportLine("row"), count: 12)
        #expect(page.decorate(body, width: 60).filter { $0.text.last == "█" }.count == 2)
        let inserted = TerminalTableViewport(
            ids: [-1] + ids, heights: [4] + heights, capacity: 12, anchor: page.anchor,
            selection: next.selection)
        #expect(inserted.start == 10)
        #expect(inserted.anchor == page.anchor)
        let removed = TerminalTableViewport(
            ids: Array(ids.dropFirst(4)), heights: Array(heights.dropFirst(4)), capacity: 12,
            anchor: page.anchor, selection: 6)
        #expect(removed.start >= 0)
        #expect(removed.visibleRows.contains(2))
    }

    @Test(arguments: [ReportView.allContributors, .sessions, .processes])
    func arrowsRevealSelectionAfterPagingAndResize(view: ReportView) throws {
        var state = try state(view: view)
        LiveReportLayout.page(state: &state, width: 120, height: 20, direction: 1, half: false)
        for delta in [-1, -1, 1, 1, 1, 1] {
            LiveReportLayout.moveSelection(state: &state, by: delta, width: 60, height: 16)
            let lines = LiveReportLayout.lines(state: state, width: 60, height: 16)
            #expect(lines.contains { $0.style == .selected })
            #expect(lines.allSatisfy { TerminalCells.width($0.text) <= 60 })
        }
    }

    @Test(arguments: [ReportView.allContributors, .processes])
    func pagingFollowsDetailsFocus(view: ReportView) throws {
        var state = try state(view: view)
        state.showDetails()
        let selected = state.selection
        let contributor = state.overview.selection
        LiveReportLayout.page(state: &state, width: 60, height: 20, direction: 1)
        #expect(state.selection == selected)
        #expect(state.overview.selection == contributor)
        #expect(state.detailsFocused)
        state.togglePaneFocus()
        LiveReportLayout.page(state: &state, width: 60, height: 20, direction: 1)
        #expect(!state.detailsFocused)
        if state.showsOverview {
            #expect(state.overview.selection != contributor)
        } else {
            #expect(state.selection != selected)
        }
    }

    @Test func halfPageAdvancesWhenOnlyOneCompleteContributorFits() throws {
        let first = TerminalTableViewport(
            ids: [0, 1, 2], heights: [5, 5, 5], capacity: 5, anchor: nil, selection: 0)
        let next = try #require(first.page(direction: 1, half: true))
        let page = TerminalTableViewport(
            ids: [0, 1, 2], heights: [5, 5, 5], capacity: 5, anchor: next.anchor, selection: next.selection)
        #expect(page.start > first.start)
        #expect(next.selection == 1)
        let back = try #require(page.page(direction: -1, half: true))
        let restored = TerminalTableViewport(
            ids: [0, 1, 2], heights: [5, 5, 5], capacity: 5, anchor: back.anchor, selection: back.selection)
        #expect(restored.start == 0)
    }

}

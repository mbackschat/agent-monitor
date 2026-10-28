import AgentMonitorPresentation
import Testing

@Suite struct ContributorLayoutTests {
    @Test func lanesHaveVisibleBoundsAndDetailsDoNotReplaceSelectedRow() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        let id = try #require(state.overview.main.first)
        state.overview.select(id)
        state.overview.toggleDetails()
        let lines = ContributorLayout.lines(state: state, width: 120, height: 30)
        let text = lines.map(\.text).joined(separator: "\n")
        #expect(text.contains("0–800%"))
        #expect(text.contains("┌") && text.contains("└"))
        #expect(text.contains("Tab") && text.contains("Esc"))
        #expect(lines.contains { $0.style == .selected && $0.text.contains("session-") })
    }

    @Test func detailsKeepSelectionVisibleAndClampScrollingAfterResize() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        state.overview.select(.section(.remainder))
        state.overview.toggleDetails()
        let selected = state.overview.selection
        for height in [8, 12, 24, 40] {
            let lines = ContributorLayout.lines(state: state, width: 40, height: height)
            #expect(lines.contains { $0.style == .selected && $0.text.contains("More processes") })
            #expect(lines.map(\.text).joined().contains("Esc close"))
            #expect(lines.count <= height)
            let maximum = ContributorLayout.maximumDetailOffset(state: state, width: 40, height: height)
            state.overview.scroll(by: 1000, maximum: maximum)
            #expect(state.overview.detailOffset == maximum)
            #expect(state.overview.selection == selected)
        }
        state.overview.scroll(by: 100)
        state.overview.scroll(by: -1, maximum: 20)
        #expect(state.overview.detailOffset == 19)
    }

    @Test(arguments: [40, 80, 120])
    func overviewPinsDoNotReplaceTheSelectionMarker(width: Int) throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        let pinned = try #require(state.overview.main.first)
        state.overview.select(pinned)
        state.overview.togglePin()
        var lines = ContributorLayout.lines(state: state, width: width, height: 40)
        #expect(try #require(lines.first { $0.style == .selected }).text.hasPrefix(">★▸ "))
        state.overview.select(.section(.remainder))
        lines = ContributorLayout.lines(state: state, width: width, height: 40)
        #expect(try #require(lines.first { $0.style == .selected }).text.hasPrefix("> ▸ "))
        #expect(lines.contains { $0.text.hasPrefix(" ★▸ ") })
        #expect(lines.allSatisfy { TerminalCells.width($0.text) <= width })
    }

    @Test(arguments: [40, 60, 80, 120], [false, true])
    func footerKeepsControlsDiscoverableAtNormalAndMinimumHeight(width: Int, paused: Bool) throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        if paused { state.toggleFreeze() }
        let height = paused ? 8 : 24
        let lines = LiveReportLayout.lines(state: state, width: width, height: height)
        #expect(lines.count <= height)
        let text = lines.map(\.text).joined(separator: "\n")
        #expect(text.contains("? help"))
        #expect(text.contains(paused ? "p resume" : DiagnosisViewState.keyHint))
        #expect(text.contains("q quit"))
        #expect(lines.allSatisfy { TerminalCells.width($0.text) <= width })
    }

}

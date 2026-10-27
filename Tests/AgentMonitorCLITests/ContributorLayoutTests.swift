import AgentMonitorPresentation
import Testing

@Suite struct ContributorLayoutTests {
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

    @Test(arguments: [40, 60, 80, 120])
    func footerKeepsHelpDiagnosisAndQuitDiscoverable(width: Int) throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        let lines = LiveReportLayout.lines(state: state, width: width, height: 24)
        let text = lines.map(\.text).joined(separator: "\n")
        #expect(text.contains("? help"))
        #expect(text.contains(DiagnosisViewState.keyHint))
        #expect(text.contains("q quit"))
        #expect(lines.allSatisfy { TerminalCells.width($0.text) <= width })
    }

    @Test(arguments: [40, 60, 80, 120])
    func minimumHeightKeepsHelpResumeAndQuitControls(width: Int) throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        state.toggleFreeze()
        let lines = LiveReportLayout.lines(state: state, width: width, height: 8)
        let text = lines.map(\.text).joined(separator: "\n")
        #expect(lines.count <= 8)
        #expect(text.contains("? help"))
        #expect(text.contains("p resume"))
        #expect(text.contains("q quit"))
        #expect(lines.allSatisfy { TerminalCells.width($0.text) <= width })
    }
}

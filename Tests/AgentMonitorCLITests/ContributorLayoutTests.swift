import AgentMonitorPresentation
import Testing

@Suite struct ContributorLayoutTests {
    @Test(arguments: [40, 60, 80, 120])
    func footerShowsCompleteControlsOrAdvertisesReducedHelp(width: Int) throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        let lines = LiveReportLayout.lines(state: state, width: width, height: 24)
        let text = lines.map(\.text).joined(separator: "\n")
        let controls = [
            "↑/↓ select", "←/→ fold", "a show all", ". pin session", "Enter inspect",
            "c/m CPU/memory order", "i details", "PgUp/PgDn scroll", "v processes",
            "p pause", "q quit",
        ]
        #expect(controls.allSatisfy { text.contains($0) } || text.contains("Resize for all keys"))
        #expect(text.contains(DiagnosisViewState.keyHint))
        #expect(text.contains("q quit"))
        #expect(lines.allSatisfy { TerminalCells.width($0.text) <= width })
    }

    @Test(arguments: [40, 60, 80, 120])
    func minimumHeightKeepsResizeResumeAndQuitControls(width: Int) throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        state.toggleFreeze()
        let lines = LiveReportLayout.lines(state: state, width: width, height: 8)
        let text = lines.map(\.text).joined(separator: "\n")
        #expect(lines.count <= 8)
        #expect(text.contains("Resize for all keys"))
        #expect(text.contains("p resume"))
        #expect(text.contains("q quit"))
        #expect(lines.allSatisfy { TerminalCells.width($0.text) <= width })
    }
}

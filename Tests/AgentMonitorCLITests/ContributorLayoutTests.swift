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
        #expect(text.contains("Resize for all keys") || text.contains("Enter inspect"))
        #expect(text.contains("p resume"))
        #expect(text.contains("q quit"))
        #expect(lines.allSatisfy { TerminalCells.width($0.text) <= width })
    }
    @Test func fullHelpFitsAfterOptionalHeaderRowsAreRemoved() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        let lines = ContributorLayout.lines(state: state, width: 40, height: 11)
        let text = lines.map(\.text).joined(separator: "\n")
        #expect(text.contains("c/m CPU/memory order"))
        #expect(text.contains("Enter inspect"))
        #expect(!text.contains("Resize for all keys"))
        #expect(lines.contains { $0.style == .selected })
        #expect(lines.count <= 11)
    }

}

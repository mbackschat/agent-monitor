import AgentMonitorPresentation
import ArgumentParser
import Testing

@testable import AgentMonitor
@testable import AgentMonitorTUI

@Suite struct TerminalChartTests {
    @Test(arguments: [ContributorChartStyle.compact, .stacked])
    func aboveRangeChartsKeepFilledBarsWithWarningColor(style: ContributorChartStyle) throws {
        var feed = OverviewFeed()
        let workers = [OverviewFeed.Worker(session: "A", executable: "java", pid: 1, cpuPerSecond: 4.5)]
        _ = try feed.advance(workers)
        var state = LiveReportState()
        state.chartStyle = style
        state.receive(try feed.advance(workers))
        state.overview.setChartRange(.percent(400))
        let lines = ContributorLayout.lines(state: state, width: 160, height: 60)
        let selected = try #require(lines.firstIndex { $0.style == .selected })
        for index in [style == .compact ? 2 : 0, selected] {
            let bar = try #require(
                lines[index].runs.first {
                    !$0.text.isEmpty && $0.text.allSatisfy { $0 == "█" || $0 == "↑" }
                })
            #expect(bar.text.allSatisfy { $0 == "█" })
            #expect(bar.renderedText(monochrome: true).allSatisfy { $0 == "↑" })
            let ansi = ANSIText.styled(ReportLine(runs: [bar]))
            #expect(ansi.contains(style == .compact ? "\u{1B}[33m" : "\u{1B}[33;43m"))
        }
        #expect(
            state.overview.activity.totalSamples.first??.percent(in: state.overview.activity.spans[0]) == 450)
    }

    @Test(arguments: [
        "MesloLGLDZForPowerline-Regular", "Meslo LG L DZ Regular for Powerline",
        "MesloLGS-NerdFont-Regular", "Unknown Font", "",
    ])
    func appleTerminalFallsBackForMesloAndUnknownFonts(font: String) {
        #expect(
            TerminalChartSelection.resolve(environment: ["TERM_PROGRAM": "Apple_Terminal"], font: { font })
                == .compact)
    }

    @Test(arguments: ["Menlo-Regular", "SourceCodeProRoman-Regular", "Monaco", "BitstreamVeraSansMono-Roman"])
    func appleTerminalKeepsAcceptedStackedFonts(font: String) {
        #expect(
            TerminalChartSelection.resolve(environment: ["TERM_PROGRAM": "Apple_Terminal"], font: { font })
                == .stacked)
    }

    @Test func unavailableFontFallsBackWithoutGuessingTheDefaultProfile() {
        #expect(
            TerminalChartSelection.resolve(environment: ["TERM_PROGRAM": "Apple_Terminal"], font: { nil })
                == .compact)
    }

    @Test func overrideAndOtherTerminalsDoNotReadAppleSettings() {
        for style in [ContributorChartStyle.compact, .stacked] {
            #expect(
                TerminalChartSelection.resolve(
                    requested: style, environment: ["TERM_PROGRAM": "Apple_Terminal"],
                    font: {
                        Issue.record("An explicit style must not query the font")
                        return nil
                    }) == style)
        }
        #expect(
            TerminalChartSelection.resolve(
                environment: ["TERM_PROGRAM": "WezTerm"],
                font: {
                    Issue.record("Do not query unrelated Apple Terminal tabs")
                    return "MesloLGLDZForPowerline-Regular"
                }) == .stacked)
    }

    @Test(arguments: [0.0, 50, 150, 250, 400, 450])
    func compactModeUsesTheSameSingleRowScaleForTotalAndEveryContributor(percent: Double) throws {
        var feed = OverviewFeed()
        let workers = [
            OverviewFeed.Worker(session: "A", executable: "java", pid: 1, cpuPerSecond: percent / 100)
        ]
        _ = try feed.advance(workers)
        var state = LiveReportState()
        state.chartStyle = .compact
        state.receive(try feed.advance(workers))
        state.overview.setChartRange(.percent(400))
        let lines = ContributorLayout.lines(state: state, width: 160, height: 60)
        let expected =
            percent == 0
            ? "_"
            : String(Array("▁▂▃▄▅▆▇█")[min(8, Int((percent / 400 * 8).rounded(.up))) - 1])
        let selected = try #require(lines.firstIndex { $0.style == .selected })
        let expectedStyle: ReportLine.Style = percent > 400 ? .chartOverflow : .separator
        #expect(lines[2].runs.contains { $0.style == expectedStyle && $0.text.contains(expected) })
        #expect(lines[selected].runs.contains { $0.style == expectedStyle && $0.text.contains(expected) })
        #expect(!lines.flatMap(\.runs).contains { $0.style == .chartFill })
        let bars = Set("▁▂▃▄▅▆▇█")
        for index in [0, 1, selected + 1, selected + 2] {
            #expect(
                !lines[index].runs.filter { $0.style == .separator }.flatMap(\.text).contains {
                    bars.contains($0)
                })
        }
        #expect(lines[1].text.contains("compact"))
        let help = ReportReferenceLayout.content(state: state, page: .keyboard).map(\.text).joined()
        #expect(help.contains("8 steps in one row"))
        #expect(!help.contains("24 steps across three rows"))
    }

    @Test func deniedInvalidAndFailedFontLookupsRemainUnavailable() {
        #expect(
            TerminalChartSelection.appleTerminalFont(
                tty: "/dev/ttys123", permitted: { false },
                query: { _ in
                    Issue.record("Denied lookup must not start automation")
                    return "Menlo-Regular"
                }) == nil)
        for tty in [nil, "not a device", "/dev/tty\nmalformed"] as [String?] {
            #expect(
                TerminalChartSelection.appleTerminalFont(
                    tty: tty,
                    permitted: {
                        Issue.record("Invalid device must not check automation")
                        return true
                    }, query: { _ in "Menlo-Regular" }) == nil)
        }
        enum LookupError: Error { case unavailable }
        #expect(
            TerminalChartSelection.appleTerminalFont(
                tty: "/dev/ttys123", permitted: { true },
                query: { _ in
                    throw LookupError.unavailable
                }) == nil)
        for reply in ["", "\n", "Meslo\u{1b}[31m", String(repeating: "x", count: 257)] {
            #expect(
                TerminalChartSelection.appleTerminalFont(
                    tty: "/dev/ttys123", permitted: { true }, query: { _ in reply }) == nil)
        }
        let font = TerminalChartSelection.appleTerminalFont(
            tty: "/dev/ttys123", permitted: { true },
            query: { device in
                #expect(device == "/dev/ttys123")
                return "MesloLGLDZForPowerline-Regular\n"
            })
        #expect(font == "MesloLGLDZForPowerline-Regular")
    }

    @Test(arguments: ["TMUX", "STY", "SSH_CONNECTION"])
    func indirectTerminalDoesNotReadLocalFont(key: String) {
        #expect(
            TerminalChartSelection.resolve(
                environment: ["TERM_PROGRAM": "Apple_Terminal", key: "active"],
                font: {
                    Issue.record("Indirect terminals must not inspect local tabs")
                    return "Menlo-Regular"
                }) == .compact)
    }

    @Test func chartOptionRequiresTUIAndAcceptsOnlyDocumentedValues() throws {
        #expect(try Options.parse(["--tui"]).report.tuiChartStyle == nil)
        for value in ["auto", "compact", "stacked"] {
            #expect(
                try Options.parse(["--tui", "--tui-chart-style", value]).report.tuiChartStyle?.rawValue
                    == value)
            #expect(throws: (any Error).self) { try Options.parse(["--tui-chart-style", value]) }
        }
        #expect(throws: (any Error).self) { try Options.parse(["--tui", "--tui-chart-style", "braille"]) }
        #expect(AgentMonitorCommand.helpMessage().contains("--tui-chart-style"))
    }
}

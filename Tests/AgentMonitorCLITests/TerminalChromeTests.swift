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
        let footer = TerminalChrome.footer(state: state, width: width)
        #expect(footer.count <= 3)
        #expect(footer.first?.text == String(repeating: "─", count: width))
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

    @Test func contributorPlotsOccupyThreeTextLinesEach() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        let lines = LiveReportLayout.lines(state: state, width: 120, height: 60)
        let row = try #require(lines.firstIndex { $0.style == .selected })
        for index in row..<(row + 3) {
            #expect(
                lines[index].runs.filter { $0.style == .separator || $0.style == .chartFill }.map {
                    TerminalCells.width($0.text)
                }.reduce(0, +) >= 24)
        }
    }

    @Test(arguments: [120, 160], [24, 60])
    func overallChartSpansHeaderFromTopOfScreen(width: Int, height: Int) throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        state.overview.setChartRange(.percent(100))
        state.overview.showAll = true
        let lines = ContributorLayout.lines(state: state, width: width, height: height)
        let chartWidth = min(24, width / 5)
        for level in 0..<3 {
            let chart = lines[level].runs.filter { $0.style == .separator || $0.style == .chartFill }
                .map(\.text).joined()
            #expect(
                chart == " " + state.overview.activity.terminalLane(width: chartWidth, level: level, rows: 3))
        }
        #expect(
            lines[0].text.contains("CPU ↓")
                && lines[0].text.contains("/\(state.overview.visibleRows.count) ↓"))
        #expect(
            lines[1].text.contains("Overall CPU")
                && lines[1].text.contains(state.overview.activity.scaleLabel))
        #expect(lines[0].runs.contains { $0.style == .chartFill })
        #expect(lines[2].text.contains("Memory"))
        #expect(lines[3].text.hasPrefix("CONTRIBUTOR"))
        #expect(lines.count == height)
        #expect(lines.allSatisfy { TerminalCells.width($0.text) <= width })
    }

    @Test func narrowHeaderPreservesSummaryAndScaleWithoutOverallChart() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        let lines = ContributorLayout.lines(state: state, width: 90, height: 30)
        #expect(lines[1].text.contains(TerminalChrome.cadence(state: state).text))
        #expect(lines[1].text.contains(state.overview.activity.scaleLabel))
        #expect(lines[2].text == state.overview.totals.summary(duration: state.overview.duration))
        #expect(
            lines.prefix(3).allSatisfy { line in
                !line.runs.contains { $0.style == .separator || $0.style == .chartFill }
            })
        #expect(lines[3].text.contains("CPU HISTORY"))
    }

    @Test func fractionalChartCapsKeepTheirShapeAboveSolidBackgroundCells() throws {
        var feed = OverviewFeed()
        let workers = [
            OverviewFeed.Worker(session: "A", executable: "java", pid: 1, cpuPerSecond: 1.5)
        ]
        _ = try feed.advance(workers)
        var state = LiveReportState()
        state.receive(try feed.advance(workers))
        state.overview.setChartRange(.percent(400))
        let lines = ContributorLayout.lines(state: state, width: 160, height: 40)
        let selected = try #require(lines.firstIndex { $0.style == .selected })
        for start in [0, selected] {
            #expect(lines[start + 1].runs.contains { $0.style == .separator && $0.text.contains("▁") })
            #expect(lines[start + 2].runs.contains { $0.style == .chartFill && $0.text.contains("█") })
        }
        #expect(
            lines.flatMap(\.runs).filter { $0.style == .chartFill }.allSatisfy { run in
                run.text.allSatisfy { $0 == "█" }
            })
    }

    @Test func contributorDetailsHonorResizeAndAdvertiseIt() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        state.showDetails()
        let before = LiveReportLayout.lines(state: state, width: 120, height: 50)
        let original = try #require(before.firstIndex { $0.text.hasPrefix("DETAILS") })
        state.adjustDetails(by: 20)
        let larger = LiveReportLayout.lines(state: state, width: 120, height: 50)
        #expect(try #require(larger.firstIndex { $0.text.hasPrefix("DETAILS") }) < original)
        #expect(larger.map(\.text).joined().contains("-/+ size"))
        state.adjustDetails(by: -20)
        #expect(LiveReportLayout.lines(state: state, width: 120, height: 50) == before)
    }

    @Test func helpHighlightsKeysAndSeparatesFiltersFromSections() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        state.showReference(.keyboard)
        let lines = LiveReportLayout.lines(state: state, width: 100, height: 60)
        let text = lines.map(\.text).joined(separator: "\n")
        #expect(!text.contains("8 collapse") && !text.contains("6 fold"))
        #expect(text.contains("S") && text.contains("Sessions"))
        #expect(text.contains("Ctrl-U") && text.contains("Ctrl-D"))
        let control = try #require(lines.first { $0.text.contains("sort CPU") })
        #expect(control.runs.count > 1)
        #expect(ANSIText.styled(control).contains("\u{1b}[1;4;36m"))
    }

    @Test func contributorDetailPagingKeepsTableSelectionAndSignalsMoreContent() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        state.showDetails()
        let selected = state.overview.selection
        let before = LiveReportLayout.lines(state: state, width: 80, height: 20)
        #expect(before.contains { $0.text.hasPrefix("DETAILS") && $0.text.contains("↓") })
        LiveReportLayout.page(state: &state, width: 80, height: 20, direction: 1)
        #expect(state.overview.detailOffset > 0)
        #expect(state.overview.selection == selected)
        LiveReportLayout.page(state: &state, width: 80, height: 20, direction: -1)
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
        #expect(lines.map(\.text).joined().contains("u/d"))
    }
    @Test(arguments: [120, 160, 200], [12, 32])
    func chartLegendUsesOnlySpareFooterSpace(width: Int, height: Int) throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        let footer = TerminalChrome.footer(state: state, width: width)
        let rendered = ContributorLayout.lines(state: state, width: width, height: height)
        let legend = ["↑  above chart range", "·  no measurement", "_  measured zero"]
        let fits = footer.dropFirst().allSatisfy { TerminalCells.width($0.text) + 3 + 20 <= width }
        let expected = height >= 20 && fits
        #expect(rendered.count == height)
        for (index, line) in rendered.suffix(3).enumerated() {
            if index > 0 || !expected { #expect(line.text.hasPrefix(footer[index].text)) }
            #expect(line.text.contains(legend[index]) == expected)
            if expected { #expect(TerminalCells.width(line.text) == width) }
        }
    }

}

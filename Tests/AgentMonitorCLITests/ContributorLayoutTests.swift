import AgentMonitorPresentation
import Foundation
import Testing

@Suite struct ContributorLayoutTests {
    @Test func treeConnectsSiblingAndNestedRowsThroughContextLines() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture(includeProcesses: true, mixedSession: true, splitWorkloads: true))
        state.overview.sort(by: .memory)
        let root = try #require(state.overview.main.first)
        state.overview.setDisclosure(expanded: true, for: root)
        let child = try #require(state.overview.visibleRows.first { $0.depth == 1 })
        state.overview.setDisclosure(expanded: true, for: child.id)
        let lines = ContributorLayout.lines(state: state, width: 120, height: 80)
        let text = lines.map(\.text).joined(separator: "\n")
        #expect(text.contains("├─ ▾ node"))
        #expect(text.contains("│  └─ ·"))
        #expect(text.contains("└─ ▸ node"))
        #expect(lines.contains { $0.text.hasPrefix("  │  │ ") && $0.text.contains("1 process") })
        #expect(lines.contains { $0.text.hasPrefix("  │    ") && $0.text.contains("/fixture") })
        #expect(!text.contains("1 processes"))
        #expect(lines.filter { $0.text.contains("/fixture") }.allSatisfy { $0.style == .normal })
    }

    @Test func syntheticGroupsShowTheirPopulationOnlyOnce() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        let lines = ContributorLayout.lines(state: state, width: 120, height: 60).map(\.text)
        let start = try #require(lines.firstIndex { $0.contains("Recent contributors") })
        let group = lines.dropFirst(start).prefix(3).joined(separator: "\n")
        #expect(group.components(separatedBy: "0 processes").count == 2)
    }

    @Test func rowStylesKeepIdentityPathsMetricsAndSelectionDistinct() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        let lines = ContributorLayout.lines(state: state, width: 120, height: 60)
        let selected = try #require(lines.first { $0.style == .selected })
        #expect(selected.runs.contains { $0.style == .selected && $0.text.contains("session-") })
        #expect(selected.runs.contains { $0.style == .separator && !$0.text.contains("┌") })
        #expect(selected.runs.contains { $0.style == .heading && $0.text.contains("MB") })
        let context = try #require(lines.first { $0.text.contains("/fixture") })
        #expect(context.runs.contains { $0.style == .normal && $0.text.contains("/fixture") })
        #expect(ANSIText.styled(context).contains("\u{1B}[1;34m"))
        #expect(ANSIText.styled(selected).contains("\u{1B}[1;7m"))
        #expect(ANSIText.styled(selected).contains("\u{1B}[34m"))
    }

    @Test(arguments: [99, 100, 140])
    func wideContextStopsBeforeHistoryAndContributorsHaveSeparation(width: Int) throws {
        var state = LiveReportState()
        state.receive(try overviewFixture(invocationName: String(repeating: "long-workload-", count: 8)))
        let lines = ContributorLayout.lines(state: state, width: width, height: 60)
        let header = try #require(lines.first { $0.text.contains("CPU HISTORY") })
        let chart = try #require(header.text.range(of: "CPU HISTORY"))
        let boundary = TerminalCells.width(String(header.text[..<chart.lowerBound])) - 1
        let context = lines.filter { $0.style == .normal && $0.text.contains("long-workload") }
        #expect(!context.isEmpty)
        if width >= 100 {
            #expect(context.allSatisfy { TerminalCells.width($0.text) <= boundary })
        } else {
            #expect(context.contains { TerminalCells.width($0.text) > boundary })
        }
        let count = try #require(lines.first { $0.text.contains("1 process") })
        #expect(count.runs.filter { $0.text.contains("1 process") }.allSatisfy { $0.style != .muted })
        let next = try #require(lines.firstIndex { $0.text.contains("Unresolved / uncertain") })
        #expect(lines[next - 1].text.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @Test(arguments: [ContributorOrder.cpu, .memory], [false, true])
    func resourceAccentFollowsSortAndHasATextArrow(order: ContributorOrder, ascending: Bool) throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        state.overview.sort(by: order, ascending: ascending)
        let lines = ContributorLayout.lines(state: state, width: 120, height: 40)
        let header = try #require(lines.first { $0.text.contains("CPU HISTORY") })
        let label = (order == .cpu ? "CPU" : "MEMORY") + (ascending ? " ↑" : " ↓")
        #expect(header.text.contains(label))
        let selected = try #require(lines.first { $0.style == .selected })
        let value = try #require(selected.runs.first { $0.text.contains(order == .cpu ? "%" : "MB") })
        #expect(ANSIText.styled(ReportLine(runs: [value])).contains("\u{1B}[1;36m"))
    }

    @Test func contributorDetailsKeepColoredLabelsAndReadableValues() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        state.overview.toggleDetails()
        let lines = ContributorLayout.lines(state: state, width: 120, height: 60)
        let detail = try #require(lines.first { $0.text.contains("Exact session:") })
        #expect(detail.runs.contains { $0.style == .identity && $0.text.contains("Exact session:") })
        #expect(detail.runs.contains { $0.style == .normal && $0.text.contains("session-1") })
    }

    @Test func tableFoldingHasADiscoverableTerminalControl() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        let text = ContributorLayout.lines(state: state, width: 120, height: 30).map(\.text).joined(
            separator: "\n")
        #expect(text.contains("Overall CPU"))
        let fold = try #require(ReportShortcut(rawValue: "8"))
        let selected = state.overview.selection
        state.apply(fold)
        #expect(state.overview.visibleRows.isEmpty)
        #expect(state.overview.selection == selected)
        let folded = ContributorLayout.lines(state: state, width: 120, height: 30).map(\.text).joined(
            separator: "\n")
        #expect(folded.contains("8 expand"))
        #expect(!folded.contains("CONTRIBUTOR"))
        #expect(folded.contains("Overall CPU"))
        state.apply(fold)
        #expect(!state.overview.visibleRows.isEmpty)
    }

    @Test func borderlessLanesAndDetailsKeepTheSelectedRow() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        let id = try #require(state.overview.main.first)
        state.overview.select(id)
        state.overview.toggleDetails()
        let lines = ContributorLayout.lines(state: state, width: 120, height: 30)
        let text = lines.map(\.text).joined(separator: "\n")
        #expect(text.contains("0–800%"))
        #expect(!text.contains("┌") && !text.contains("┐") && !text.contains("┘"))
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
        #expect(text.contains(paused ? "p resume" : "p pause"))
        #expect(text.contains("q/Ctrl-C quit"))
        #expect(lines.allSatisfy { TerminalCells.width($0.text) <= width })
    }

}

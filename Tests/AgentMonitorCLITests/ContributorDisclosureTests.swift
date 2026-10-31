import AgentMonitorPresentation
import Testing

@Suite struct ContributorDisclosureTests {
    @Test(arguments: ContributorTableSection.allCases)
    func foldingASectionHidesItsEntireSubtreesOnly(section: ContributorTableSection) throws {
        var overview = ContributorOverview()
        overview.receive(try overviewFixture(includeProcesses: true))
        overview.togglePin(for: try #require(overview.main.first))
        overview.showAll = true
        for _ in 0..<4 {
            for row in overview.visibleRows { overview.setDisclosure(expanded: true, for: row.id) }
        }
        var rowSection = ContributorTableSection.other
        let expected = overview.visibleRows.filter { row in
            if row.depth == 0 {
                rowSection =
                    overview.pinned.contains(row.id)
                    ? .pinned
                    : (overview.main.contains(row.id) ? .sessions : .other)
            }
            return rowSection != section
        }
        overview.toggleSection(section)
        #expect(overview.visibleRows.map(\.id) == expected.map(\.id))
    }

    @Test func sectionAndTableFoldingPreserveInspectionAcrossRefresh() throws {
        let snapshot = try overviewFixture(includeProcesses: true)
        var state = LiveReportState()
        state.receive(snapshot)
        let parent = try #require(state.overview.main.first)
        state.overview.setDisclosure(expanded: true, for: parent)
        let child = try #require(state.overview.nodes[parent]?.children.first)
        state.overview.select(child)
        state.overview.toggleDetails()
        let rows = state.overview.visibleRows
        let open = state.overview.open
        let totals = state.overview.totals
        let activity = state.overview.activity
        state.apply(.foldSessions)
        #expect(!state.overview.selectionIsVisible)
        #expect(!state.overview.detailsVisible)
        #expect(state.contributorProcesses(for: child).isEmpty)
        state.overview.toggleDetails()
        #expect(!state.overview.detailsVisible)
        let pinnedHiddenSelection = state.overview.togglePin()
        #expect(!pinnedHiddenSelection)
        state.overview.receive(snapshot)
        #expect(state.overview.selection == child)
        #expect(state.overview.open == open)
        #expect(state.overview.totals == totals)
        #expect(state.overview.activity == activity)
        state.apply(.foldSessions)
        #expect(state.overview.visibleRows == rows)
        #expect(state.overview.selection == child)
        state.apply(.foldTable)
        state.overview.hideNoLongerObserved = true
        #expect(state.overview.selection == child)
        state.overview.hideNoLongerObserved = false
        state.overview.receive(snapshot)
        #expect(state.overview.visibleRows.isEmpty)
        #expect(state.overview.selection == child)
        state.apply(.foldTable)
        #expect(state.overview.visibleRows == rows)
        #expect(state.overview.open == open)
    }

    @Test(arguments: [false, true])
    func hidingHistoricalRowsPreservesMeasuredWorkAndCurrentMembers(mixedSession: Bool) throws {
        let snapshot = try overviewFixture(includeProcesses: true, mixedSession: mixedSession)
        var overview = ContributorOverview()
        overview.receive(snapshot)
        overview.showAll = true
        for _ in 0..<4 {
            for row in overview.visibleRows { overview.setDisclosure(expanded: true, for: row.id) }
        }
        if !mixedSession {
            let session = try #require(
                overview.visibleRows.first {
                    if case .session = $0.id { return $0.node.stats.isNoLongerObserved }
                    return false
                })
            overview.togglePin(for: session.id)
        }
        let historical = try #require(overview.visibleRows.first { $0.node.stats.isNoLongerObserved })
        let rows = overview.visibleRows
        let totals = overview.totals
        let activity = overview.activity
        let pins = overview.pinned
        overview.select(historical.id)
        overview.toggleDetails()
        overview.hideNoLongerObserved = true
        #expect(overview.visibleRows.allSatisfy { !$0.node.stats.isNoLongerObserved })
        #expect(overview.visibleRows.map(\.id) == rows.filter { !$0.node.stats.isNoLongerObserved }.map(\.id))
        #expect(overview.selection != historical.id)
        #expect(!overview.detailsVisible)
        #expect(overview.totals == totals)
        #expect(overview.activity == activity)
        #expect(overview.pinned == pins)
        overview.hideNoLongerObserved = false
        #expect(overview.visibleRows.map(\.id) == rows.map(\.id))
        overview.hideNoLongerObserved = true
        overview.receive(try overviewFixture(includeProcesses: true, mixedSession: mixedSession))
        #expect(overview.hideNoLongerObserved)
        #expect(overview.visibleRows.allSatisfy { !$0.node.stats.isNoLongerObserved })
    }

    @Test func expandingAnotherContributorPreservesSelectionAndTotals() throws {
        var overview = ContributorOverview()
        overview.receive(try overviewFixture())
        let selected = try #require(overview.main.first)
        let target = ContributorID.section(.remainder)
        let totals = overview.totals
        overview.select(selected)
        overview.setDisclosure(expanded: true, for: target)
        #expect(overview.selection == selected)
        #expect(overview.open.contains(target))
        #expect(overview.totals == totals)
        overview.setDisclosure(expanded: true, for: target)
        #expect(overview.selection == selected)
        #expect(overview.open.contains(target))
    }

    @Test func collapsingASelectedDescendantReturnsSelectionToItsVisibleParent() throws {
        var overview = ContributorOverview()
        overview.receive(try overviewFixture())
        let parent = try #require(overview.main.first)
        overview.setDisclosure(expanded: true, for: parent)
        let child = try #require(overview.nodes[parent]?.children.first)
        overview.select(child)
        overview.toggleDetails()
        overview.setDisclosure(expanded: false, for: parent)
        #expect(overview.selection == parent)
        #expect(!overview.detailsVisible)
        #expect(!overview.open.contains(parent))
        #expect(!overview.visibleRows.contains { $0.id == child })
    }

    @Test func collapsingShowAllSectionPreservesTheOtherSectionDisclosure() throws {
        var overview = ContributorOverview()
        overview.receive(try overviewFixture())
        overview.showAll = true
        overview.setDisclosure(expanded: false, for: .section(.remainder))
        #expect(!overview.showAll)
        #expect(!overview.open.contains(.section(.remainder)))
        #expect(overview.open.contains(.section(.recent)))
        #expect(
            !overview.visibleRows.contains { row in
                overview.nodes[.section(.remainder)]?.children.contains(row.id) == true
            })
        #expect(
            overview.visibleRows.contains { row in
                overview.nodes[.section(.recent)]?.children.contains(row.id) == true
            })
    }
}

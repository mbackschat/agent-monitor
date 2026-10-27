import AgentMonitorPresentation
import Testing

@Suite struct ContributorDisclosureTests {
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

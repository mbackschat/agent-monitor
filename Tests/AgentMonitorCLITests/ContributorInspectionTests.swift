import AgentMonitorCore
import AgentMonitorPresentation
import Testing

@Suite struct ContributorInspectionTests {
    @Test func foldingAWorkerDoesNotOpenEvidenceAndExplicitDetailsAreStructured() throws {
        var state = LiveReportState()
        state.receive(try overviewFixture())
        let session = try #require(state.overview.main.first)
        state.overview.toggle(session)
        let family = try #require(state.overview.nodes[session]?.children.first)
        state.overview.toggle(family)
        let familyFields = try #require(state.overview.nodes[family]).inspectionFields
        #expect(familyFields.contains { $0.label == "Agent" && $0.value == "codex" })
        #expect(familyFields.contains { $0.label == "Session" && !$0.value.isEmpty })
        let worker = try #require(state.overview.nodes[family]?.children.first)
        state.overview.toggle(worker)
        let folded = ContributorLayout.lines(state: state, width: 120, height: 60).map(\.text).joined(
            separator: "\n")
        #expect(!folded.contains("Lifetime:"))
        state.overview.toggleDetails()
        let fields = try #require(state.overview.nodes[worker]).inspectionFields
        #expect(fields.contains { $0.label == "Agent" && $0.value == "codex" })
        #expect(fields.contains { $0.label == "Session" && !$0.value.isEmpty })
        #expect(fields.prefix(5).contains { $0.label == "Directory" })
        #expect(fields.contains { $0.label == "Executable" && $0.value == "/bin/node" })
        #expect(fields.contains { $0.label == "Directory" && $0.value == "/fixture" })
        #expect(fields.contains { $0.label == "State" && $0.value.contains("final scan") })
        let detailed = ContributorLayout.lines(state: state, width: 120, height: 60).map(\.text).joined(
            separator: "\n")
        #expect(detailed.contains("Lifetime:"))
        #expect(!detailed.contains("CPU history"), "Details must not repeat interval data from row charts")
        #expect(detailed.contains("/fixture"))
    }
    @Test func refreshThatHidesTheInspectedRowClosesDetailsInsteadOfRetargeting() throws {
        let snapshot = try overviewFixture()
        var overview = ContributorOverview()
        overview.receive(snapshot)
        let session = try #require(overview.main.first)
        overview.toggle(session)
        let family = try #require(overview.nodes[session]?.children.first)
        overview.toggle(family)
        let worker = try #require(overview.nodes[family]?.children.first)
        overview.select(worker)
        overview.toggleDetails()
        #expect(overview.detailsVisible)
        overview.receive(
            MonitoringSnapshot(
                cpuAccounting: snapshot.cpuAccounting, timestamp: snapshot.timestamp,
                intervalSeconds: snapshot.intervalSeconds, cpuThresholdPercent: 1_000,
                memoryThresholdBytes: 1_000_000_000_000, sampledProcessCount: snapshot.sampledProcessCount,
                unreadableProcessCount: 0, findings: [], observedFindings: snapshot.observedFindings,
                window: snapshot.window, recentActivity: snapshot.recentActivity))
        #expect(overview.selection != worker)
        #expect(!overview.detailsVisible)
    }

    @Test func changingSelectionClosesDetailsButReselectingKeepsThem() throws {
        var overview = ContributorOverview()
        overview.receive(try overviewFixture())
        let session = try #require(overview.main.first)
        overview.toggle(session)
        let family = try #require(overview.nodes[session]?.children.first)
        overview.toggleDetails()
        overview.select(session)
        #expect(overview.detailsVisible)
        overview.select(family)
        #expect(overview.selection == family)
        #expect(!overview.detailsVisible)
    }

}

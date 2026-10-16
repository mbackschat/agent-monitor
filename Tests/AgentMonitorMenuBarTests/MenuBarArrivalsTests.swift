import AgentMonitorCore
import AgentMonitorPresentation
import Testing

@testable import AgentMonitorMenuBar

@Test func arrivalsSkipInitialRowsAndIgnoreReorderingButExpireIndependently() throws {
    let now = ContinuousClock.now
    let first = try menuBarFixture(pids: [42001])
    let second = try menuBarFixture(pids: [42001, 42002])
    let third = try menuBarFixture(pids: [42003, 42002, 42001])
    var arrivals = MenuBarArrivals()
    arrivals.update(first, now: now)
    #expect(arrivals.deadlines.isEmpty)
    arrivals.update(second, now: now + .seconds(1))
    let added = LiveReportRowID.process(second.findings[1].process)
    let parent = LiveReportRowID.group(try #require(SessionGrouping.groups(second.findings).first).id)
    #expect(Set(arrivals.deadlines.keys) == [added, parent])
    arrivals.update(third, now: now + .seconds(2))
    #expect(arrivals.deadlines[added] == now + .seconds(4))
    arrivals.expire(at: now + .seconds(4))
    #expect(Set(arrivals.deadlines.keys) == [.process(third.findings[0].process), parent])
    arrivals.expire(at: now + .seconds(5))
    #expect(arrivals.deadlines.isEmpty)
}

@Test func arrivalsMarkNewSessionsAndReturningIdentitiesButResetOnReopening() throws {
    let now = ContinuousClock.now
    let first = try menuBarFixture()
    let second = try menuBarFixture(pids: [42002], sessionID: "22222222-2222-4222-8222-222222222222")
    var arrivals = MenuBarArrivals()
    arrivals.update(first, now: now)
    arrivals.update(second, now: now)
    #expect(
        Set(arrivals.deadlines.keys) == [
            .process(second.findings[0].process), .group(SessionGrouping.groups(second.findings)[0].id),
        ])
    arrivals.update(first, now: now + .seconds(1))
    #expect(arrivals.deadlines[.process(first.findings[0].process)] != nil)
    #expect(arrivals.deadlines[.process(second.findings[0].process)] == nil)
    arrivals.update(nil, now: now)
    arrivals.update(second, now: now)
    #expect(arrivals.deadlines.isEmpty)
}

@Test @MainActor func rowActionsRespectAvailableTargetsAndReviewState() async throws {
    let sample = try menuBarFixture(pids: [42001, 42002])
    let model = MenuBarModel { _, _, _, receive in try await receive(sample) }
    model.open()
    await model.waitForCollection()
    let group = LiveReportRowID.group(try #require(model.report.groups.first).id)
    #expect(model.canBegin(.focus, row: group))
    #expect(!model.canBegin(.terminate, row: group))
    #expect(!model.canBegin(.message, row: group))
    model.report.select(group)
    model.report.toggleDisclosure()
    let row = LiveReportRowID.process(sample.findings[0].process)
    #expect(model.canBegin(.terminate, row: row))
    #expect(model.canBegin(.message, row: row))
    #expect(model.canBegin(.focus, row: row))
    model.begin(.terminate, row: row)
    #expect(model.report.actionPanel?.phase == .confirmTermination)
    #expect(!model.canBegin(.message, row: row))
    model.input(.escape)
    model.togglePin(row)
    model.report.receive(try menuBarFixture(pids: []))
    #expect(!model.canBegin(.terminate, row: row))
    #expect(!model.canBegin(.message, row: row))
    #expect(!model.canBegin(.focus, row: row))
    await model.stop()
}

@Test @MainActor func unresolvedSessionCannotOfferMessaging() async throws {
    let sample = try menuBarFixture(sessionID: "unresolved")
    let model = MenuBarModel { _, _, _, receive in try await receive(sample) }
    model.open()
    await model.waitForCollection()
    let row = LiveReportRowID.process(sample.findings[0].process)
    #expect(!model.canBegin(.message, row: row))
    #expect(model.canBegin(.terminate, row: row))
    await model.stop()
}

@Test(arguments: [[Int32(42001)], [42001, 42002]])
func newProcessHighlightsItsExistingSessionEvenWhenCollapsed(pids: [Int32]) throws {
    let now = ContinuousClock.now
    let first = try menuBarFixture(pids: pids)
    let next = try menuBarFixture(pids: pids + [42003])
    var arrivals = MenuBarArrivals()
    arrivals.update(first, now: now)
    arrivals.update(next, now: now + .seconds(1))
    let group = try #require(SessionGrouping.groups(next.findings).first)
    #expect(arrivals.deadlines[.group(group.id)] == now + .seconds(4))
}

import AgentMonitorCore
import Foundation
import Synchronization
import Testing

@testable import AgentMonitorMenuBar

private let emptySnapshot = MonitoringSnapshot(
    timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1,
    cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
    sampledProcessCount: 4, unreadableProcessCount: 1, findings: [])

@Test @MainActor func closedPanelDoesNotStartCollection() async {
    let calls = Mutex(0)
    let model = MenuBarModel { _, _, _ in calls.withLock { $0 += 1 } }
    await model.stop()
    #expect(calls.withLock { $0 } == 0)
    #expect(model.report.snapshot == nil)
}

@Test @MainActor func closingCancelsCollectionAndRejectsLateSnapshots() async {
    let (events, continuation) = AsyncStream<Void>.makeStream()
    let model = MenuBarModel { _, _, receive in
        try await receive(emptySnapshot)
        continuation.yield(())
        do { try await Task.sleep(for: .seconds(3600)) } catch {}
        try await receive(emptySnapshot)
    }
    model.open()
    var iterator = events.makeAsyncIterator()
    await iterator.next()
    #expect(model.report.snapshot == emptySnapshot)
    await model.stop()
    #expect(model.report.snapshot == nil)
    #expect(!model.isOpen)
    #expect(model.error == nil)
}

@Test @MainActor func rapidReopeningWaitsForPreviousCollectorToFinish() async {
    let (events, continuation) = AsyncStream<String>.makeStream()
    let calls = Mutex(0)
    let model = MenuBarModel { _, _, _ in
        let call = calls.withLock { value in
            value += 1
            return value
        }
        continuation.yield("start \(call)")
        do { try await Task.sleep(for: .seconds(3600)) } catch {}
        continuation.yield("end \(call)")
    }
    var iterator = events.makeAsyncIterator()
    model.setLiveIcon(false)
    model.open()
    model.open()
    #expect(await iterator.next() == "start 1")
    model.close()
    model.open()
    #expect(await iterator.next() == "end 1")
    #expect(await iterator.next() == "start 2")
    await model.stop()
    #expect(await iterator.next() == "end 2")
    #expect(calls.withLock { $0 } == 2)
}

@Test @MainActor func collectionFailureIsVisibleAndReopeningClearsIt() async {
    struct Failure: LocalizedError {
        var errorDescription: String? { "Fixture collection failed" }
    }
    let model = MenuBarModel { _, _, _ in throw Failure() }
    model.open()
    await model.waitForCollection()
    #expect(model.error == "Fixture collection failed")
    model.close()
    model.open()
    #expect(model.error == nil)
    #expect(model.report.snapshot == nil)
    await model.stop()
}

@Test @MainActor func pauseHoldsRowsUntilResumeAndReopeningStartsLive() async throws {
    let first = try menuBarFixture(pids: [42001, 42002])
    let pending = try menuBarFixture(pids: [42003])
    let latest = try menuBarFixture(pids: [42004])
    let (samples, input) = AsyncStream<MonitoringSnapshot>.makeStream()
    let (received, output) = AsyncStream<Void>.makeStream()
    let model = MenuBarModel { _, _, receive in
        for await sample in samples {
            try await receive(sample)
            output.yield(())
        }
    }
    var acknowledgements = received.makeAsyncIterator()
    model.toggleFreeze()
    #expect(!model.report.frozen)
    model.open()
    model.toggleFreeze()
    #expect(!model.report.frozen)
    input.yield(first)
    await acknowledgements.next()
    model.report.toggleDisclosure()
    let rows = model.report.visibleRows
    model.toggleFreeze()
    input.yield(pending)
    await acknowledgements.next()
    input.yield(latest)
    await acknowledgements.next()
    #expect(model.report.frozen)
    #expect(model.report.snapshot == first)
    #expect(model.report.visibleRows == rows)
    #expect(model.arrivals.deadlines.isEmpty)
    model.toggleFreeze()
    #expect(!model.report.frozen)
    #expect(model.report.snapshot == latest)
    #expect(model.arrivals.deadlines[.process(latest.findings[0].process)] != nil)
    let row = try #require(latest.findings.first)
    model.begin(.terminate, row: .process(row.process))
    model.toggleFreeze()
    #expect(!model.report.frozen)
    model.input(.escape)
    model.toggleFreeze()
    #expect(model.report.frozen)
    model.panelSize = .tall
    await model.stop()
    model.open()
    #expect(!model.report.frozen)
    #expect(model.report.snapshot == nil)
    #expect(model.panelSize == .tall)
    #expect(model.arrivals.deadlines.isEmpty)
    await model.stop()
}

@Test @MainActor func nativeSamplingOptionsReachTheRunningSourceWithoutRestarting() async {
    let (requests, trigger) = AsyncStream<Void>.makeStream()
    let (observations, observed) = AsyncStream<(Double, Double)>.makeStream()
    let calls = Mutex(0)
    let model = MenuBarModel { thresholds, interval, _ in
        calls.withLock { $0 += 1 }
        for await _ in requests {
            observed.yield((await thresholds().cpuPercent, interval.seconds))
        }
    }
    model.open()
    model.report.adjustThreshold(.cpuUp)
    model.adjustInterval(.slower)
    trigger.yield(())
    var iterator = observations.makeAsyncIterator()
    let values = await iterator.next()
    #expect(values?.0 == 35)
    #expect(values?.1 == 2)
    model.adjustInterval(.faster)
    trigger.yield(())
    #expect(await iterator.next()?.1 == 1)
    model.setInterval(15)
    model.report.setThresholds(Thresholds(cpuPercent: 50, memoryBytes: 500_000_000))
    trigger.yield(())
    let selectedValues = await iterator.next()
    #expect(selectedValues?.0 == 50)
    #expect(selectedValues?.1 == 15)
    model.close()
    model.setInterval(2)
    trigger.yield(())
    #expect(await iterator.next()?.1 == 15)
    #expect(calls.withLock { $0 } == 1)
    await model.stop()
}

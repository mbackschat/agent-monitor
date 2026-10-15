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
    let model = MenuBarModel { _ in calls.withLock { $0 += 1 } }
    await model.stop()
    #expect(calls.withLock { $0 } == 0)
    #expect(model.report.snapshot == nil)
}

@Test @MainActor func closingCancelsCollectionAndRejectsLateSnapshots() async {
    let (events, continuation) = AsyncStream<Void>.makeStream()
    let model = MenuBarModel { receive in
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
    let model = MenuBarModel { _ in
        let call = calls.withLock { value in
            value += 1
            return value
        }
        continuation.yield("start \(call)")
        do { try await Task.sleep(for: .seconds(3600)) } catch {}
        continuation.yield("end \(call)")
    }
    var iterator = events.makeAsyncIterator()
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
    let model = MenuBarModel { _ in throw Failure() }
    model.open()
    await model.waitForCollection()
    #expect(model.error == "Fixture collection failed")
    model.close()
    model.open()
    #expect(model.error == nil)
    #expect(model.report.snapshot == nil)
    await model.stop()
}

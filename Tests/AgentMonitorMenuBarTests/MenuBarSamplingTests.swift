import AgentMonitorCore
import Synchronization
import Testing

@testable import AgentMonitorMenuBar

@Test @MainActor func nativeCollectorStartsWithFixedHundredMillisecondSettingsWhileClosed() async {
    let (events, output) = AsyncStream<(SamplingSettings, Bool)>.makeStream()
    let model = MenuBarModel { _, interval, _ in
        output.yield((interval.settings, interval.panelVisible))
    }
    model.start()
    var iterator = events.makeAsyncIterator()
    let initial = await iterator.next()
    #expect(initial?.0 == SamplingSettings())
    #expect(initial?.1 == false)
    await model.stop()
}

@Test @MainActor func panelVisibilityReachesTheRunningCollectorWithoutRestarting() async {
    let (requests, trigger) = AsyncStream<Void>.makeStream()
    let (events, output) = AsyncStream<Bool>.makeStream()
    let calls = Mutex(0)
    let model = MenuBarModel { _, interval, _ in
        calls.withLock { $0 += 1 }
        output.yield(interval.panelVisible)
        for await _ in requests { output.yield(interval.panelVisible) }
    }
    var iterator = events.makeAsyncIterator()
    model.start()
    #expect(await iterator.next() == false)
    model.open()
    trigger.yield(())
    #expect(await iterator.next() == true)
    model.close()
    trigger.yield(())
    #expect(await iterator.next() == false)
    model.open()
    trigger.yield(())
    #expect(await iterator.next() == true)
    #expect(calls.withLock { $0 } == 1)
    await model.stop()
}

@Test @MainActor func nativeIntervalPresetsPreserveSamplingSettingsAndRejectInvalidCombinations() {
    let model = MenuBarModel { _, _, _ in }
    var settings = SamplingSettings(
        enabled: true, minimum: 0.25, visibleMaximum: 5, closedMultiplier: 2.5, window: 45)
    let accepted = model.report.setSamplingSettings(settings)
    #expect(accepted)
    model.setInterval(15)
    settings.visibleMaximum = 15
    #expect(model.report.samplingSettings == settings)
    model.setInterval(30)
    #expect(model.report.samplingSettings == settings)
    var invalid = settings
    invalid.minimum = 20
    let invalidAccepted = model.report.setSamplingSettings(invalid)
    #expect(!invalidAccepted)
    #expect(model.report.samplingSettings == settings)
}

@Test @MainActor func nativeSamplingSettingsReachTheCollectorWhilePresentationIsPaused() async throws {
    let first = try menuBarFixture(pids: [42001])
    let second = try menuBarFixture(pids: [42001, 42002])
    let (requests, input) = AsyncStream<MonitoringSnapshot>.makeStream()
    let (events, output) = AsyncStream<(SamplingSettings, Bool)>.makeStream()
    let calls = Mutex(0)
    let model = MenuBarModel { _, interval, receive in
        calls.withLock { $0 += 1 }
        output.yield((interval.settings, interval.panelVisible))
        for await snapshot in requests {
            try await receive(snapshot)
            output.yield((interval.settings, interval.panelVisible))
        }
    }
    var settings = SamplingSettings(
        enabled: true, minimum: 0.25, visibleMaximum: 5, closedMultiplier: 2.5, window: 45)
    let accepted = model.report.setSamplingSettings(settings)
    #expect(accepted)
    var iterator = events.makeAsyncIterator()
    model.start()
    let initial = await iterator.next()
    #expect(initial?.0 == settings)
    #expect(initial?.1 == false)
    model.open()
    input.yield(first)
    #expect(await iterator.next()?.1 == true)
    model.toggleFreeze()
    #expect(model.report.frozen)
    settings.window = 120
    let windowAccepted = model.report.setSamplingSettings(settings)
    #expect(windowAccepted)
    model.adjustInterval(.slower)
    settings.visibleMaximum = 10
    input.yield(second)
    let paused = await iterator.next()
    #expect(paused?.0 == settings)
    #expect(paused?.1 == true)
    #expect(model.report.snapshot == first)
    model.toggleFreeze()
    #expect(model.report.snapshot == second)
    model.close()
    input.yield(second)
    let closed = await iterator.next()
    #expect(closed?.0 == settings)
    #expect(closed?.1 == false)
    #expect(calls.withLock { $0 } == 1)
    await model.stop()
}

@Test @MainActor func staticIconRetainsSamplingSettingsButStartsFreshCollectionOnReopening() async {
    let (events, output) = AsyncStream<(SamplingSettings, Bool)>.makeStream()
    let calls = Mutex(0)
    let model = MenuBarModel { _, interval, _ in
        calls.withLock { $0 += 1 }
        output.yield((interval.settings, interval.panelVisible))
        try await Task.sleep(for: .seconds(3600))
    }
    let settings = SamplingSettings(
        enabled: true, minimum: 0.25, visibleMaximum: 5, closedMultiplier: 2.5, window: 45)
    let accepted = model.report.setSamplingSettings(settings)
    #expect(accepted)
    model.setLiveIcon(false)
    model.start()
    #expect(model.collection == nil)
    var iterator = events.makeAsyncIterator()
    for _ in 0..<2 {
        model.open()
        let opened = await iterator.next()
        #expect(opened?.0 == settings)
        #expect(opened?.1 == true)
        model.close()
        await model.waitForCollection()
        #expect(model.collection == nil)
        #expect(model.report.samplingSettings == settings)
    }
    #expect(calls.withLock { $0 } == 2)
    await model.stop()
}

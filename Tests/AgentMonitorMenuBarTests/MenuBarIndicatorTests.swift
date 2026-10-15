import AgentMonitorCore
import AppKit
import Foundation
import Synchronization
import Testing

@testable import AgentMonitorMenuBar

private func loadSample(_ cpu: Double, pid: Int32 = 42001, time: Double = 1) throws -> MonitoringSnapshot {
    let sample = try menuBarFixture(pids: [pid], cpu: cpu, memoryBytes: 10)
    return MonitoringSnapshot(
        timestamp: Date(timeIntervalSince1970: time), intervalSeconds: 15,
        cpuThresholdPercent: 999, memoryThresholdBytes: 999, sampledProcessCount: 1,
        unreadableProcessCount: 0, findings: [], agentLoad: AgentLoadSummary(processes: sample.findings))
}

@Test func loadBarsUseFixedMachineCapacityAndDistinguishUnknown() throws {
    var indicator = MenuBarIndicator(processorCount: 8)
    #expect(indicator.level == nil)
    for (cpu, bars) in [(0.0, 0), (8, 1), (199, 1), (200, 2), (399, 2), (400, 3), (1200, 3)] {
        indicator.receive(try loadSample(cpu))
        #expect(indicator.level == bars)
    }
    indicator.fail()
    #expect(indicator.level == nil)
    #expect(!indicator.highlighted)
    #expect(indicator.statusDescription.contains("unavailable"))
}

@Test func newHeavyLoadHighlightsForTwoSamplesWithoutRenewingSustainedLoad() throws {
    var indicator = MenuBarIndicator(processorCount: 8)
    indicator.receive(try loadSample(50))
    #expect(!indicator.highlighted)
    indicator.receive(try loadSample(0))
    indicator.receive(try loadSample(50))
    #expect(indicator.highlighted)
    indicator.receive(try loadSample(80))
    #expect(indicator.highlighted)
    indicator.receive(try loadSample(100))
    #expect(!indicator.highlighted)
    indicator.receive(try loadSample(150))
    #expect(!indicator.highlighted)
    indicator.receive(try loadSample(150, pid: 42002))
    #expect(indicator.highlighted)
}

@Test @MainActor func loadIconsKeepSizeAndIncreaseFilledAreaAtActualResolution() throws {
    var areas: [Int] = []
    for level in 0...3 {
        let image = MenuBarStatusImage.make(level: level, highlighted: false)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.isTemplate)
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 18, pixelsHigh: 18, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
        NSGraphicsContext.restoreGraphicsState()
        var opaque = 0
        for y in 0..<18 {
            for x in 0..<18 where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.9 { opaque += 1 }
        }
        areas.append(opaque)
    }
    #expect(zip(areas, areas.dropFirst()).allSatisfy { $0 < $1 })
}

@Test func unavailableLoadNeverMasqueradesAsIdleAndRecoveryDoesNotTriggerAnAlert() throws {
    var indicator = MenuBarIndicator(processorCount: 8)
    indicator.receive(try loadSample(0))
    indicator.receive(try loadSample(50))
    #expect(indicator.highlighted)
    indicator.fail()
    #expect(indicator.level == nil)
    indicator.receive(try loadSample(50))
    #expect(!indicator.highlighted)
    #expect(indicator.statusDescription.contains("50"))
}

@Test @MainActor func newLoadBadgeInvertsTheBarsInsideAFilledBackground() throws {
    let image = MenuBarStatusImage.make(level: 3, highlighted: true)
    #expect(image.isTemplate)
    #expect(image.size == NSSize(width: 18, height: 18))
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 18, pixelsHigh: 18, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    image.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
    NSGraphicsContext.restoreGraphicsState()
    #expect((bitmap.colorAt(x: 6, y: 8)?.alphaComponent ?? 0) > 0.9)
    #expect((bitmap.colorAt(x: 14, y: 8)?.alphaComponent ?? 1) < 0.1)
    #expect((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1)
}

@Test @MainActor func liveIconSamplesClosedAtFifteenSecondsAndKeepsOneCollector() async throws {
    let (requests, input) = AsyncStream<MonitoringSnapshot>.makeStream()
    let (events, output) = AsyncStream<Double>.makeStream()
    let calls = Mutex(0)
    let model = MenuBarModel { _, interval, receive in
        calls.withLock { $0 += 1 }
        for await sample in requests {
            try await receive(sample)
            output.yield(interval.seconds)
        }
    }
    var iterator = events.makeAsyncIterator()
    model.start()
    input.yield(try loadSample(0))
    #expect(await iterator.next() == 15)
    #expect(model.report.snapshot == nil)
    #expect(model.indicator.level == 0)
    model.open()
    input.yield(try loadSample(50))
    #expect(await iterator.next() == 1)
    model.toggleFreeze()
    let held = model.report.snapshot
    input.yield(try loadSample(400, time: 2))
    #expect(await iterator.next() == 1)
    #expect(model.report.snapshot == held)
    #expect(model.indicator.level != 0)
    model.close()
    model.adjustInterval(.slower)
    input.yield(try loadSample(0, time: 3))
    #expect(await iterator.next() == 15)
    #expect(model.report.snapshot == nil)
    #expect(calls.withLock { $0 } == 1)
    model.open()
    #expect(model.report.snapshot?.timestamp == Date(timeIntervalSince1970: 3))
    await model.stop()
    #expect(model.indicator.level == nil)
}

@Test @MainActor func staticIconCancelsClosedSamplingAndCanEnableItAgain() async throws {
    let (events, output) = AsyncStream<String>.makeStream()
    let model = MenuBarModel { _, _, receive in
        output.yield("start")
        do { try await Task.sleep(for: .seconds(3600)) } catch {}
        output.yield("end")
        try await receive(loadSample(100))
    }
    var iterator = events.makeAsyncIterator()
    model.setLiveIcon(false)
    model.start()
    #expect(model.indicator.level == nil)
    model.setLiveIcon(true)
    #expect(await iterator.next() == "start")
    model.setLiveIcon(false)
    await model.waitForCollection()
    #expect(await iterator.next() == "end")
    #expect(model.indicator.level == nil)
    model.setLiveIcon(true)
    #expect(await iterator.next() == "start")
    await model.stop()
    #expect(await iterator.next() == "end")
    #expect(model.report.snapshot == nil)
}

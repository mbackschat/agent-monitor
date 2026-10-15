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
    #expect(indicator.heavyCount == nil)
    #expect(indicator.statusDescription.contains("unavailable"))
}

@Test func badgeCountsCurrentHeavyProcessesFromTheFirstSampleUntilTheyBecomeQuiet() throws {
    var indicator = MenuBarIndicator(processorCount: 8)
    #expect(indicator.level == nil)
    #expect(indicator.heavyCount == nil)
    for cpu in [50.0, 80, 100, 150] {
        indicator.receive(try loadSample(cpu))
        #expect(indicator.heavyCount == 1)
    }
    indicator.receive(try loadSample(0))
    #expect(indicator.heavyCount == 0)
    #expect(indicator.level == 0)
    indicator.receive(try loadSample(150, pid: 42002))
    #expect(indicator.heavyCount == 1)
    #expect(!indicator.statusDescription.contains("temporary"))
}

@Test func badgeIncludesMemoryHeavyProcessesAndDeduplicatesProcessLifetimes() throws {
    let fixture = try menuBarFixture(pids: [42001, 42002], cpu: 0, memoryBytes: 2_000_000_000)
    var indicator = MenuBarIndicator()
    indicator.receive(
        MonitoringSnapshot(
            timestamp: fixture.timestamp, intervalSeconds: 15, cpuThresholdPercent: 999,
            memoryThresholdBytes: 999_000_000_000, sampledProcessCount: 2, unreadableProcessCount: 0,
            findings: [], agentLoad: AgentLoadSummary(processes: fixture.findings + fixture.findings)))
    #expect(indicator.heavyCount == 2)
    #expect(indicator.level == 0)
}

@Test @MainActor func loadIconsKeepSizeAndIncreaseFilledAreaAtActualResolution() throws {
    var areas: [Int] = []
    for level in 0...3 {
        let image = MenuBarStatusImage.make(level: level, heavyCount: nil)
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

@Test func unavailableLoadClearsTheBadgeAndRecoveryRestoresTheActualCount() throws {
    var indicator = MenuBarIndicator(processorCount: 8)
    indicator.receive(try loadSample(50))
    #expect(indicator.heavyCount == 1)
    indicator.fail()
    #expect(indicator.level == nil)
    #expect(indicator.heavyCount == nil)
    indicator.receive(try loadSample(50))
    #expect(indicator.heavyCount == 1)
    #expect(indicator.statusDescription.contains("50"))
}

@Test @MainActor func numericBadgeOverlaysTheCornerWithoutWideningTheIcon() throws {
    let startup = try iconBitmap(MenuBarStatusImage.make(level: nil, heavyCount: nil))
    let quiet = try iconBitmap(MenuBarStatusImage.make(level: 0, heavyCount: nil))
    #expect(
        startup.representation(using: .png, properties: [:])
            == quiet.representation(using: .png, properties: [:]))
    let normal = try iconBitmap(MenuBarStatusImage.make(level: 3, heavyCount: nil))
    for count in [0, 1, 12, 99, 100, 1234] {
        let image = MenuBarStatusImage.make(level: 3, heavyCount: count)
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
        let bitmap = try iconBitmap(image)
        for y in 12..<18 {
            for x in 0..<18 {
                #expect(bitmap.colorAt(x: x, y: y) == normal.colorAt(x: x, y: y))
            }
        }
    }
    let one = try iconBitmap(MenuBarStatusImage.make(level: 1, heavyCount: 1))
    let two = try iconBitmap(MenuBarStatusImage.make(level: 1, heavyCount: 2))
    #expect(
        one.representation(using: .png, properties: [:]) != two.representation(using: .png, properties: [:]))
    let hundred = try iconBitmap(MenuBarStatusImage.make(level: 1, heavyCount: 100))
    let thousand = try iconBitmap(MenuBarStatusImage.make(level: 1, heavyCount: 1000))
    #expect(
        hundred.representation(using: .png, properties: [:])
            == thousand.representation(using: .png, properties: [:]))
}

@MainActor private func iconBitmap(_ image: NSImage) throws -> NSBitmapImageRep {
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(image.size.width), pixelsHigh: 18, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    image.draw(in: NSRect(origin: .zero, size: image.size))
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
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

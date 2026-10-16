import AgentMonitorCore
import AgentMonitorPresentation
import AppKit
import Foundation
import Synchronization
import Testing

@testable import AgentMonitorMenuBar

private func loadSample(_ cpu: Double, pid: Int32 = 42001, time: Double = 1) throws -> MonitoringSnapshot {
    let sample = try menuBarFixture(pids: [pid], cpu: cpu, memoryBytes: 10)
    return MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
            unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
        timestamp: Date(timeIntervalSince1970: time), intervalSeconds: 15,
        cpuThresholdPercent: 0, memoryThresholdBytes: 999, sampledProcessCount: 1,
        unreadableProcessCount: 0, findings: cpu > 0 ? sample.findings : [], agentLoad: nil)
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
            cpuAccounting: CPUAccounting(
                hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
                unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
            timestamp: fixture.timestamp, intervalSeconds: 15, cpuThresholdPercent: 999,
            memoryThresholdBytes: 1_000_000_000, sampledProcessCount: 2, unreadableProcessCount: 0,
            findings: fixture.findings + fixture.findings, agentLoad: nil))
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
        for x in 0..<18 {
            #expect((bitmap.colorAt(x: x, y: 10)?.alphaComponent ?? 0) < 0.1)
        }
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
    let model = MenuBarModel { _, interval, _, receive in
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
    #expect(await iterator.next() == 5)
    model.toggleFreeze()
    let held = model.report.snapshot
    let heldLevel = model.indicator.level
    let heldCount = model.indicator.heavyCount
    input.yield(try loadSample(Double(ProcessInfo.processInfo.activeProcessorCount) * 100, time: 2))
    #expect(await iterator.next() == 5)
    #expect(model.report.snapshot == held)
    #expect(model.indicator.level == heldLevel)
    #expect(model.indicator.heavyCount == heldCount)
    model.toggleFreeze()
    #expect(model.report.snapshot?.timestamp == Date(timeIntervalSince1970: 2))
    #expect(model.indicator.level != heldLevel)
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
    let model = MenuBarModel { _, _, _, receive in
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

@Test @MainActor func startupUsesOneFastSampleThenReturnsToNormalCadence() async throws {
    let (requests, input) = AsyncStream<Void>.makeStream()
    let (events, output) = AsyncStream<Double>.makeStream()
    let model = MenuBarModel { _, interval, _, receive in
        output.yield(interval.seconds)
        for await _ in requests {
            try await receive(loadSample(100))
            output.yield(interval.seconds)
        }
    }
    var iterator = events.makeAsyncIterator()
    model.start()
    #expect(await iterator.next() == 0.25)
    model.open()
    model.close()
    input.yield(())
    #expect(await iterator.next() == 15)
    model.open()
    model.setInterval(5)
    input.yield(())
    #expect(await iterator.next() == 5)
    model.close()
    input.yield(())
    #expect(await iterator.next() == 15)
    await model.stop()
}

@Test func tableFindingsDriveBarsAndBadgeEvenWithoutAHistorySummary() throws {
    var indicator = MenuBarIndicator(processorCount: 8)
    indicator.receive(try loadSample(400))
    #expect(indicator.heavyCount == 1)
    #expect(indicator.level == 3)
    let fixture = try menuBarFixture(pids: [42001, 42002], cpu: 10, memoryBytes: 10)
    indicator.receive(
        MonitoringSnapshot(
            cpuAccounting: CPUAccounting(
                hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
                unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
            timestamp: Date(timeIntervalSince1970: 2), intervalSeconds: 5,
            cpuThresholdPercent: 5, memoryThresholdBytes: 500_000_000,
            sampledProcessCount: 3, unreadableProcessCount: 0, findings: fixture.findings,
            agentLoad: AgentLoadSummary(processes: (try loadSample(2000)).findings)))
    #expect(indicator.heavyCount == 2)
    #expect(indicator.level == 1)
    #expect(indicator.statusDescription.contains("2 heavy processes in view"))
    #expect(!indicator.statusDescription.contains("CPU > 25%"))
    indicator.receive(try loadSample(0, time: 3))
    #expect(indicator.availability == .current)
    #expect(indicator.heavyCount == 0)
    #expect(indicator.level == 0)
}

@Test @MainActor func headingAndIconCountCollapsedChildrenSingletonsAndExcludeMissingPins() async throws {
    let grouped = try menuBarFixture(pids: [42001, 42002])
    let singleton = try menuBarFixture(pids: [42003], sessionID: "22222222-2222-4222-8222-222222222222")
    let snapshot = MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
            unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
        timestamp: grouped.timestamp, intervalSeconds: 5,
        cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
        sampledProcessCount: 3, unreadableProcessCount: 0, findings: grouped.findings + singleton.findings)
    let (samples, input) = AsyncStream<MonitoringSnapshot>.makeStream()
    let (received, output) = AsyncStream<Void>.makeStream()
    let model = MenuBarModel { _, _, _, receive in
        for await sample in samples {
            try await receive(sample)
            output.yield(())
        }
    }
    var iterator = received.makeAsyncIterator()
    model.open()
    input.yield(snapshot)
    _ = await iterator.next()
    #expect(model.visibleRowIDs.count == 2)
    #expect(model.displayedProcessCount == 3)
    #expect(model.indicator.heavyCount == model.displayedProcessCount)
    let group = try #require(model.report.groups.first { $0.processes.count == 2 })
    model.togglePin(.group(group.id))
    model.toggleFreeze()
    input.yield(try menuBarFixture(pids: []))
    _ = await iterator.next()
    #expect(model.displayedProcessCount == 3)
    #expect(model.indicator.heavyCount == 3)
    #expect(model.indicator.statusDescription.contains("Paused"))
    model.toggleFreeze()
    #expect(model.visibleRowIDs.count == 1)
    #expect(model.displayedProcessCount == 0)
    #expect(model.indicator.heavyCount == 0)
    await model.stop()
}

@Test func statusAndAccessibilityIncludeContextWithoutChangingIconTotals() {
    let context = CPUAccounting(
        hostBusyPercent: 700, logicalCPUCount: 8, measuredUserPercent: 600,
        unmeasuredLifetimeCount: 3, previousScanSeconds: 0.01)
    let snapshot = MonitoringSnapshot(
        cpuAccounting: context,
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1, cpuThresholdPercent: 25,
        memoryThresholdBytes: 1_000_000_000, sampledProcessCount: 20, unreadableProcessCount: 0, findings: [])
    var indicator = MenuBarIndicator(processorCount: 8)
    indicator.receive(snapshot)
    #expect(indicator.level == 0)
    #expect(indicator.heavyCount == 0)
    #expect(indicator.statusLines.contains(CPUContext.text(context)))
    #expect(indicator.statusDescription.contains(CPUContext.text(context)))
}

@Test func statusMenuLabelsAgentCPUApartFromHostContext() {
    let snapshot = MonitoringSnapshot(
        cpuAccounting: CPUAccounting(
            hostBusyPercent: 700, logicalCPUCount: 8, measuredUserPercent: 600,
            unmeasuredLifetimeCount: 0, previousScanSeconds: 0.01),
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1, cpuThresholdPercent: 25,
        memoryThresholdBytes: 1_000_000_000, sampledProcessCount: 20, unreadableProcessCount: 0, findings: [])
    var indicator = MenuBarIndicator(processorCount: 8)
    indicator.receive(snapshot)
    #expect(
        indicator.statusLines.contains {
            $0.hasPrefix("Agents in view: CPU ") && $0.hasSuffix("% (100% = one core)")
        })
    #expect(indicator.statusLines.filter { $0.hasPrefix("CPU") } == [CPUContext.text(snapshot.cpuAccounting)])
}

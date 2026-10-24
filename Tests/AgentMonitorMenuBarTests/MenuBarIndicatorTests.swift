import AgentMonitorPresentation
import AppKit
import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore
@testable import AgentMonitorMenuBar

@Test func indicatorIncludesAgentResourcesHiddenByDisplayFilters() throws {
    let fixture = try menuBarFixture(pids: [42001, 42002], cpu: 100, memoryBytes: 100_000_000)
    let snapshot = MonitoringSnapshot(
        cpuAccounting: fixture.cpuAccounting, timestamp: fixture.timestamp,
        intervalSeconds: 1, cpuThresholdPercent: 200, memoryThresholdBytes: 1_000_000_000,
        sampledProcessCount: 2, unreadableProcessCount: 0, findings: [],
        observedFindings: fixture.findings)
    var indicator = MenuBarIndicator(processorCount: 8)
    indicator.receive(snapshot)
    #expect(indicator.level == 2)
    #expect(indicator.processCount == 2)
    #expect(
        indicator.statusDescription.contains(200.0.formatted(.number.precision(.fractionLength(1))) + "%"))
    #expect(
        indicator.statusDescription.contains(0.2.formatted(.number.precision(.fractionLength(1))) + " GB"))
}

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
    #expect(indicator.processCount == nil)
    #expect(indicator.statusDescription.contains("unavailable"))
}

@Test func badgeCountsCurrentHeavyProcessesFromTheFirstSampleUntilTheyBecomeQuiet() throws {
    var indicator = MenuBarIndicator(processorCount: 8)
    #expect(indicator.level == nil)
    #expect(indicator.processCount == nil)
    for cpu in [50.0, 80, 100, 150] {
        indicator.receive(try loadSample(cpu))
        #expect(indicator.processCount == 1)
    }
    indicator.receive(try loadSample(0))
    #expect(indicator.processCount == 0)
    #expect(indicator.level == 0)
    indicator.receive(try loadSample(150, pid: 42002))
    #expect(indicator.processCount == 1)
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
    #expect(indicator.processCount == 2)
    #expect(indicator.level == 0)
}

@Test @MainActor func loadIconsKeepSizeAndIncreaseFilledAreaAtActualResolution() throws {
    var areas: [Int] = []
    for level in 0...3 {
        let image = MenuBarStatusImage.make(level: level)
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
    #expect(indicator.processCount == 1)
    indicator.fail()
    #expect(indicator.level == nil)
    #expect(indicator.processCount == nil)
    indicator.receive(try loadSample(50))
    #expect(indicator.processCount == 1)
    #expect(indicator.statusDescription.contains("50"))
}

@Test @MainActor func statusBarsKeepTheTemplateSizeAndNeutralStartup() throws {
    let startup = try iconBitmap(MenuBarStatusImage.make(level: nil))
    let quiet = try iconBitmap(MenuBarStatusImage.make(level: 0))
    #expect(
        startup.representation(using: .png, properties: [:])
            == quiet.representation(using: .png, properties: [:]))
    for level in 0...3 {
        let image = MenuBarStatusImage.make(level: level)
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
    }
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

@Test @MainActor func liveIconPreservesFastCollectionWhileClosedAndKeepsOneCollector() async throws {
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
    #expect(await iterator.next() == 0.1)
    #expect(model.report.snapshot == nil)
    #expect(model.indicator.level == 0)
    model.open()
    input.yield(try loadSample(50))
    #expect(await iterator.next() == 0.1)
    model.toggleFreeze()
    let held = model.report.snapshot
    let heldLevel = model.indicator.level
    let heldCount = model.indicator.processCount
    input.yield(try loadSample(Double(ProcessInfo.processInfo.activeProcessorCount) * 100, time: 2))
    #expect(await iterator.next() == 0.1)
    #expect(model.report.snapshot == held)
    #expect(model.indicator.level == heldLevel)
    #expect(model.indicator.processCount == heldCount)
    model.toggleFreeze()
    #expect(model.report.snapshot?.timestamp == Date(timeIntervalSince1970: 2))
    #expect(model.indicator.level != heldLevel)
    model.close()
    model.setInterval(2)
    input.yield(try loadSample(0, time: 3))
    #expect(await iterator.next() == 2)
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

@Test @MainActor func startupUsesOneFastSampleThenReturnsToNormalCadence() async throws {
    let (requests, input) = AsyncStream<Void>.makeStream()
    let (events, output) = AsyncStream<Double>.makeStream()
    let model = MenuBarModel { _, interval, receive in
        output.yield(interval.seconds)
        for await _ in requests {
            try await receive(loadSample(100))
            output.yield(interval.seconds)
        }
    }
    var iterator = events.makeAsyncIterator()
    model.setInterval(5)
    model.start()
    #expect(await iterator.next() == 0.25)
    model.open()
    model.close()
    input.yield(())
    #expect(await iterator.next() == 5)
    model.open()
    model.setInterval(5)
    input.yield(())
    #expect(await iterator.next() == 5)
    model.close()
    input.yield(())
    #expect(await iterator.next() == 5)
    await model.stop()
}

@Test func tableFindingsDriveBarsAndQualifiedCensusEvenWithoutAHistorySummary() throws {
    var indicator = MenuBarIndicator(processorCount: 8)
    indicator.receive(try loadSample(400))
    #expect(indicator.processCount == 1)
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
    #expect(indicator.processCount == 2)
    #expect(indicator.level == 1)
    #expect(indicator.statusDescription.contains("2 observed agent-associated processes in this window"))
    #expect(!indicator.statusDescription.contains("CPU > 25%"))
    indicator.receive(try loadSample(0, time: 3))
    #expect(indicator.availability == .current)
    #expect(indicator.processCount == 0)
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
    let model = MenuBarModel { _, _, receive in
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
    #expect(model.observedProcessCount == 3)
    #expect(model.indicator.processCount == model.observedProcessCount)
    let group = try #require(model.report.groups.first { $0.processes.count == 2 })
    model.togglePin(.group(group.id))
    model.toggleFreeze()
    input.yield(try menuBarFixture(pids: []))
    _ = await iterator.next()
    #expect(model.observedProcessCount == 3)
    #expect(model.indicator.processCount == 3)
    #expect(model.indicator.statusDescription.contains("Paused"))
    model.toggleFreeze()
    #expect(model.visibleRowIDs.count == 1)
    #expect(model.observedProcessCount == 0)
    #expect(model.indicator.processCount == 0)
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
    #expect(indicator.processCount == 0)
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
            $0.hasPrefix("Observed agents: CPU ") && $0.hasSuffix("% (100% = one core)")
        })
    #expect(indicator.statusLines.filter { $0.hasPrefix("CPU") } == [CPUContext.text(snapshot.cpuAccounting)])
}

@Test @MainActor func statusBarsUseTheFullIconHeight() throws {
    let bitmap = try iconBitmap(MenuBarStatusImage.make(level: 3))
    #expect((bitmap.colorAt(x: 15, y: 3)?.alphaComponent ?? 0) > 0.5)
}

@Test func exactCollapsedCensusDoesNotReportZeroRetainedRows() throws {
    let fixture = try menuBarFixture(pids: [42001, 42002], cpu: 100, memoryBytes: 100)
    var ledger = CounterLedger()
    func samples(_ time: Double) -> [ProcessSample] {
        fixture.findings.map {
            ProcessSample(
                identity: $0.process, parentPID: 0, executable: $0.executable,
                name: $0.name, sampledAt: time, cpuSeconds: time, footprintBytes: 100)
        }
    }
    var window = AccountingWindow(baseline: ledger.ingest(samples(0), listedAt: 0))
    try window.append(ledger.ingest(samples(1), listedAt: 1), rows: fixture.findings)
    try window.append(ledger.ingest([], listedAt: 2), rows: [])
    window.compact(to: MonitoringPipelineLimits(pendingObservations: 1))
    var indicator = MenuBarIndicator()
    indicator.receive(
        MonitoringSnapshot(
            cpuAccounting: fixture.cpuAccounting, timestamp: fixture.timestamp,
            intervalSeconds: 0.1, cpuThresholdPercent: 0, memoryThresholdBytes: 0,
            sampledProcessCount: 0, unreadableProcessCount: 0, findings: [], window: window.summary))
    let bounds = AgentLoadSummary(processes: [], window: window.summary).processCountRange
    #expect(bounds.maximum > 0)
    #expect(indicator.statusDescription.contains("\(bounds.text) observed agent-associated processes"))
    #expect(indicator.statusDescription.contains("older detail collapsed"))
}

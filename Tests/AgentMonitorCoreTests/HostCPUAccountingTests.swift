import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private struct FakeHostSource: HostCPUReading {
    let counters: HostCPUCounters?
    func read() -> HostCPUCounters? { counters }
}

private func host(_ user: UInt32, _ system: UInt32 = 0, _ idle: UInt32 = 0, _ nice: UInt32 = 0)
    -> HostCPUCounters
{
    HostCPUCounters(processors: [HostCPUTicks(user: user, system: system, idle: idle, nice: nice)])
}

@Test func hostOccupancySumsAllStatesAndScalesByLogicalCPUCount() throws {
    let baseline = FakeHostSource(
        counters: HostCPUCounters(processors: [
            HostCPUTicks(user: 10, system: 10, idle: 10, nice: 10),
            HostCPUTicks(user: 10, system: 10, idle: 10, nice: 10),
        ]))
    let current = FakeHostSource(
        counters: HostCPUCounters(processors: [
            HostCPUTicks(user: 20, system: 20, idle: 70, nice: 30),
            HostCPUTicks(user: 50, system: 20, idle: 50, nice: 20),
        ]))
    #expect(current.read()?.busyPercent(since: baseline.read()) == 100)
}

@Test func hostFirstSnapshotAndFailureHaveNoOccupancy() {
    let source = FakeHostSource(counters: host(100))
    #expect(source.read()?.busyPercent(since: nil) == nil)
    #expect(FakeHostSource(counters: nil).read()?.busyPercent(since: source.read()) == nil)
}

@Test(arguments: [
    host(10, 10, 10, 10), host(9, 20, 20, 20), host(20, 9, 20, 20),
    host(20, 20, 9, 20), host(20, 20, 20, 9), HostCPUCounters(processors: []),
    HostCPUCounters(processors: [
        HostCPUTicks(user: 20, system: 20, idle: 20, nice: 20),
        HostCPUTicks(user: 20, system: 20, idle: 20, nice: 20),
    ]),
]) func hostRejectsZeroDeltaAnyDecreaseAndCPUCountChange(current: HostCPUCounters) {
    #expect(FakeHostSource(counters: current).read()?.busyPercent(since: host(10, 10, 10, 10)) == nil)
}

@Test func hostRejectsWrapEvenWhenAnotherCPUHidesTheDecrease() {
    let previous = HostCPUCounters(processors: [
        HostCPUTicks(user: .max, system: 0, idle: 0, nice: 0),
        HostCPUTicks(user: 0, system: 0, idle: 0, nice: 0),
    ])
    let current = HostCPUCounters(processors: [
        HostCPUTicks(user: 1, system: 0, idle: 0, nice: 0),
        HostCPUTicks(user: .max, system: 0, idle: 0, nice: 0),
    ])
    #expect(FakeHostSource(counters: current).read()?.busyPercent(since: previous) == nil)
}

@Test func hostIdleTicksProduceMeasuredZero() {
    #expect(
        FakeHostSource(counters: host(10, 10, 110, 10)).read()?.busyPercent(since: host(10, 10, 10, 10)) == 0)
}

private final class SequenceHostSource: HostCPUReading, Sendable {
    let values: Mutex<[HostCPUCounters?]>
    let reads = Mutex(0)
    init(_ values: [HostCPUCounters?]) { self.values = Mutex(values) }
    func read() -> HostCPUCounters? {
        reads.withLock { $0 += 1 }
        return values.withLock { $0.removeFirst() }
    }
}

@Test func hostFailureBreaksBaselineAndReaderSamplesOncePerListing() throws {
    let source = SequenceHostSource([host(10), host(20), nil, host(30), host(40)])
    let reader = try NativeProcessReader(hostSource: source)
    var monitor = Monitor()
    for expected: Double? in [nil, 100, nil, nil, 100] {
        let snapshot = try reader.snapshot(processIDs: { [] })
        #expect(monitor.ingest(snapshot).hostBusyPercent == expected)
    }
    #expect(source.reads.withLock { $0 } == 5)
}

@Test func accountingIncludesQuietUnrelatedLifetimesAndPreviousScanSkew() {
    var monitor = Monitor()
    let first = monitor.ingest(
        ProcessSnapshot(
            samples: [sample(10, at: 11, cpu: 1, memory: 0)], enumeratedCount: 1, unreadableCount: 0,
            listedAt: 10, scanSeconds: 0.4, hostCounters: host(10), logicalCPUCount: 1))
    #expect(first.previousScanSeconds == nil)
    #expect(first.unmeasuredLifetimeCount == 1)
    var newborn = sample(20, at: 14, cpu: 0.4, memory: 0)
    newborn.startedAt = 12
    let next = monitor.ingest(
        ProcessSnapshot(
            samples: [sample(10, at: 13, cpu: 1.2, memory: 0), newborn, sample(30, cpu: nil, memory: nil)],
            enumeratedCount: 5, unreadableCount: 2, listedAt: 12, scanSeconds: 0.6,
            hostCounters: host(20), logicalCPUCount: 1))
    #expect(abs(next.measuredUserPercent - 20) < 1e-10)
    #expect(next.unmeasuredLifetimeCount == 1)
    #expect(next.previousScanSeconds == 0.4)
    #expect(monitor.findings().isEmpty)
}

@Test func hostNativeSourceReturnsPerCPUStates() throws {
    let counters = try #require(NativeHostCPUReader().read())
    #expect(counters.processors.count == ProcessInfo.processInfo.activeProcessorCount)
}

@Test(arguments: [
    [host(10), host(10), host(20)],
    [host(10), host(1), host(2)],
    [host(.max), host(1), host(2)],
]) func hostUnusableReadingEstablishesTheNextBaseline(values: [HostCPUCounters]) throws {
    let source = SequenceHostSource(values.map { $0 })
    let reader = try NativeProcessReader(hostSource: source)
    var monitor = Monitor()
    for expected: Double? in [nil, nil, 100] {
        #expect(monitor.ingest(try reader.snapshot(processIDs: { [] })).hostBusyPercent == expected)
    }
}

@Test func excludedMonitorDoesNotEnterMeasuredPopulation() throws {
    let pid = ProcessInfo.processInfo.processIdentifier
    let reader = try NativeProcessReader(hostSource: FakeHostSource(counters: host(10)))
    var monitor = Monitor()
    let snapshot = try reader.snapshot(processIDs: { [pid] }, excluding: [pid])
    #expect(snapshot.samples.isEmpty)
    let accounting = monitor.ingest(snapshot)
    #expect(accounting.measuredUserPercent == 0)
    #expect(accounting.unmeasuredLifetimeCount == 0)
}

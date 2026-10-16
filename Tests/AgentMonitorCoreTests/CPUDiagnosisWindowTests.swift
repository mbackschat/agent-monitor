import Foundation
import Testing

@testable import AgentMonitorCore

func diagnosisScan(
    _ samples: [ProcessSample] = [], at: Double, scan: Double = 0.25,
    host: HostCPUCounters? = nil, count: Int = 1, unreadable: Int = 0
) -> ProcessSnapshot {
    ProcessSnapshot(
        samples: samples, enumeratedCount: samples.count + unreadable, unreadableCount: unreadable,
        listedAt: at, scanSeconds: scan, hostCounters: host, logicalCPUCount: count)
}

@Suite struct CPUDiagnosisWindowTests {
    @Test func contributionUsesR1WindowsAcrossExecAndReuse() throws {
        var monitor = Monitor()
        let old = sample(10, at: 10.25, cpu: 100)
        monitor.ingest(diagnosisScan([old], at: 10))
        #expect(monitor.cpuContribution(for: old.identity) == nil)
        let replaced = sample(10, executable: "/bin/other", at: 12.25, cpu: 101)
        monitor.ingest(diagnosisScan([replaced], at: 12))
        let interval = try #require(monitor.cpuContribution(for: old.identity))
        #expect(interval.cpuSeconds == 1)
        #expect(interval.observedSeconds == 2)
        var newborn = sample(10, start: 100, at: 14.5, cpu: 0.5)
        newborn.startedAt = 13
        monitor.ingest(diagnosisScan([newborn], at: 14, scan: 0.5))
        #expect(monitor.cpuContribution(for: old.identity) == nil)
        #expect(monitor.cpuContribution(for: newborn.identity)?.observedSeconds == 2.5)
        #expect(monitor.cpuContribution(for: newborn.identity)?.cpuSeconds == 0.5)
    }

    @Test func ranksCPUSecondsRetainsEarlierContributorsAndConservesOmissions() throws {
        var window = CPUDiagnosisWindow()
        let baseline = (1...12).map { sample(Int32($0), at: 10.05, cpu: 100) }
        window.ingest(diagnosisScan(baseline, at: 10, unreadable: 2))
        let steady = (1...12).map { sample(Int32($0), at: 12.05, cpu: 101) }
        window.ingest(diagnosisScan(steady, at: 12, scan: 0.05))
        var burst = sample(50, at: 12.2, cpu: 0.2)
        burst.startedAt = 12.1
        window.ingest(diagnosisScan([burst], at: 12.1, scan: 0.1, unreadable: 1))
        window.ingest(diagnosisScan([], at: 14, scan: 0.5))
        #expect(window.rankedContributors.count == 13)
        #expect(window.contributors.map(\.sample.identity.pid) == Array(1...10).map(Int32.init))
        #expect(window.omittedContributorCount == 3)
        #expect(window.cpuSeconds == 12.2)
        let returnedCPU = window.contributors.map(\.cpuSeconds).reduce(0, +)
        let omittedCPU = window.rankedContributors.dropFirst(10).map(\.cpuSeconds).reduce(0, +)
        #expect(returnedCPU == 10)
        #expect(omittedCPU == 2.2)
        #expect(returnedCPU + omittedCPU == window.cpuSeconds)
        #expect(window.observedLifetimeCount == 13)
        #expect(window.unreadableObservationCount == 3)
        #expect(window.unmeasuredObservationCount == 0)
        #expect(window.elapsedSeconds == 4.5)
        #expect(window.maximumScanSeconds == 0.5)
        let earlier = try #require(window.contributors.first)
        #expect(earlier.observedSeconds == 2)
        #expect(earlier.meanCPUPercent == 50)
        #expect(earlier.peakCPUPercent == 50)
        #expect(earlier.validIntervals == 1)
        #expect(try #require(window.rankedContributors.last).meanCPUPercent > earlier.meanCPUPercent)
    }

    @Test func gapsAndInvalidCountersNeverBridgeAndZeroRemainsMeasured() {
        var window = CPUDiagnosisWindow()
        window.ingest(diagnosisScan([sample(1, at: 10, cpu: 1), sample(2, at: 10, cpu: 2)], at: 10))
        window.ingest(diagnosisScan([sample(1, at: 11, cpu: nil), sample(2, at: 11, cpu: 2)], at: 11))
        window.ingest(diagnosisScan([sample(1, at: 12, cpu: 3)], at: 12))
        window.ingest(diagnosisScan([sample(1, at: 13, cpu: 2), sample(2, at: 13, cpu: 4)], at: 13))
        #expect(window.unmeasuredObservationCount == 4)
        #expect(window.cpuSeconds == 0)
        #expect(window.windowCPUPercent == 0)
        #expect(window.measuredLifetimeCount == 1)
        #expect(window.contributors.first?.sample.identity.pid == 2)
    }

    @Test func baselineAndOlderFirstObservationDoNotBecomeContributions() {
        var window = CPUDiagnosisWindow()
        var older = sample(1, at: 11, cpu: 20)
        older.startedAt = 10
        window.ingest(diagnosisScan([], at: 10))
        window.ingest(diagnosisScan([older], at: 11))
        #expect(window.cpuSeconds == nil)
        #expect(window.windowCPUPercent == nil)
        #expect(window.contributors.isEmpty)
        #expect(window.unmeasuredObservationCount == 1)
        #expect(window.observedLifetimeCount == 1)
        #expect(CPUDiagnosisWindow().cpuSeconds == nil)
    }

    @Test func hostWeightsListingDurationsRatherThanWaitsOrScanEnd() {
        var window = CPUDiagnosisWindow()
        window.ingest(diagnosisScan(at: 10, host: ticks(0, 0)))
        window.ingest(diagnosisScan(at: 12, host: ticks(10, 10)))
        window.ingest(diagnosisScan(at: 15, host: ticks(20, 10)))
        window.ingest(diagnosisScan(at: 16, scan: 2, host: ticks(20, 20)))
        #expect(window.host.meanBusyPercent == 400.0 / 6)
        #expect(window.host.observedSeconds == 6)
        #expect(window.host.validIntervals == 3)
        #expect(window.elapsedSeconds == 8)
        #expect(window.host.logicalCPUCount == 1)
    }

    @Test func hostFailuresZeroDeltaWrapAndCountChangesDoNotBridge() {
        var window = CPUDiagnosisWindow()
        window.ingest(diagnosisScan(at: 10, host: ticks(.max, 0)))
        window.ingest(diagnosisScan(at: 11, host: ticks(0, 0)))
        window.ingest(diagnosisScan(at: 12, host: ticks(0, 0)))
        window.ingest(diagnosisScan(at: 13, host: nil))
        window.ingest(diagnosisScan(at: 14, host: ticks(10, 0)))
        #expect(window.host.meanBusyPercent == nil)
        window.ingest(diagnosisScan(at: 15, host: ticks(20, 0)))
        window.ingest(diagnosisScan(at: 16, host: ticks(30, 0, count: 2), count: 2))
        window.ingest(diagnosisScan(at: 17, host: ticks(40, 0, count: 2), count: 2))
        #expect(window.host.meanBusyPercent == 150)
        #expect(window.host.validIntervals == 2)
        #expect(window.host.observedSeconds == 2)
        #expect(window.host.logicalCPUCount == nil)
    }

    @Test func tiesUseExactIdentityAndKeepLatestMeasuredFootprint() throws {
        var window = CPUDiagnosisWindow()
        window.ingest(diagnosisScan([sample(7, start: 1, at: 10, cpu: 0)], at: 10))
        window.ingest(diagnosisScan([sample(7, start: 1, at: 11, cpu: 1, memory: 123)], at: 11))
        var reused = sample(7, start: 2, at: 12, cpu: 1, memory: 456)
        reused.startedAt = 11.5
        window.ingest(diagnosisScan([reused], at: 12))
        window.ingest(diagnosisScan([sample(7, start: 2, at: 13, cpu: nil, memory: nil)], at: 13))
        #expect(window.contributors.map(\.sample.identity.startMicroseconds) == [1, 2])
        #expect(window.cpuSeconds == 2)
        let latest = try #require(window.contributors.last)
        #expect(latest.footprint?.bytes == 456)
        #expect(latest.footprint?.sampledAt == 12)
    }

    @Test(arguments: [0.0, -1.0]) func nonpositiveSampleAndListingDeltasDoNotContribute(delta: Double) {
        var window = CPUDiagnosisWindow()
        window.ingest(diagnosisScan([sample(1, at: 10, cpu: 1)], at: 10, host: ticks(0, 0)))
        window.ingest(diagnosisScan([sample(1, at: 10 + delta, cpu: 2)], at: 10 + delta, host: ticks(10, 0)))
        #expect(window.cpuSeconds == nil)
        #expect(window.host.meanBusyPercent == nil)
        #expect(window.host.validIntervals == 0)
    }

    private func ticks(_ user: UInt32, _ idle: UInt32, count: Int = 1) -> HostCPUCounters {
        HostCPUCounters(
            processors: Array(
                repeating: HostCPUTicks(user: user, system: 0, idle: idle, nice: 0), count: count))
    }
}

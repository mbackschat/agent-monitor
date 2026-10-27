import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private final class AdaptiveClockReader: ProcessReading, AcquisitionClock, SessionRegistryReading,
    InspectionReading
{
    struct State {
        var time = 0.0
        var starts: [Double] = []
    }
    let state = Mutex(State())
    let interval: LiveInterval
    let deferDueDeadline: Bool
    let shortenAt: Double?
    let slowSettingsChange: Bool
    let permission: LiveInspection?
    let releaseInspectionAt: Double?
    init(
        _ interval: LiveInterval, deferDueDeadline: Bool = false,
        permission: LiveInspection? = nil, releaseInspectionAt: Double? = nil, shortenAt: Double? = nil,
        slowSettingsChange: Bool = false
    ) {
        self.interval = interval
        self.shortenAt = shortenAt
        self.slowSettingsChange = slowSettingsChange
        self.deferDueDeadline = deferDueDeadline
        self.permission = permission
        self.releaseInspectionAt = releaseInspectionAt
    }
    func snapshot(excluding: Set<Int32>) -> ProcessSnapshot {
        state.withLock {
            let start = $0.time
            $0.starts.append(start)
            if slowSettingsChange {
                if $0.starts.count > 1 { interval.set(0.1 + Double($0.starts.count - 1) * 0.02) }
                $0.time += 0.3
            }
            return diagnosisScan([sample(42, at: $0.time, cpu: 0)], at: start, scan: $0.time - start)
        }
    }
    func monotonicNow() -> Double { state.withLock { $0.time } }
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }
    func wait(until deadline: Double, wake: AcquisitionWake) {
        let first = state.withLock { state in
            let first = state.starts.count == 1 && state.time == 0
            state.time = first ? (shortenAt ?? deadline) : deadline
            return first
        }
        if first && deferDueDeadline { interval.set(1) }
        if first && shortenAt != nil { interval.set(0.1) }
        if let releaseInspectionAt, deadline >= releaseInspectionAt { permission?.set(false) }
    }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata { ProcessMetadata() }
    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        ProcessMetadata()
    }
    func output(of query: SessionRegistryQuery) throws -> Data { Data("[]".utf8) }
    func inspectionPIDs(allowance: InspectionAllowance) throws -> [Int32] { [] }
    func inspectionRead(_ pid: Int32, allowance: InspectionAllowance) -> InspectionRead? { nil }
}

@Suite struct AdaptiveAcquisitionTests {
    @Test(arguments: [false, true], [false, true])
    func inspectionNeedsBothFeatureAndPermission(feature: Bool, permitted: Bool) async throws {
        for enabled in [false, true] {
            let settings = SamplingSettings(enabled: enabled, visibleMaximum: 0.5, window: 1)
            let live = LiveInterval(settings: settings)
            let permission = LiveInspection(active: permitted)
            let reader = AdaptiveClockReader(live)
            let session = MonitoringSession(
                configuration: try MonitoringConfiguration(
                    samples: 4,
                    reportIntervalSeconds: 1, inspectionObservations: feature, sampling: settings),
                reader: reader, clock: reader, registry: reader)
            let result = Mutex<SamplingCoverage>(SamplingCoverage())
            try await session.run(interval: live, inspection: permission) { value in
                if let coverage = value.window?.acquisitionCoverage.sampling {
                    result.withLock { $0.merge(coverage) }
                }
            }
            let coverage = result.withLock { $0 }
            #expect(coverage.latest?.requestedSeconds == (feature && permitted ? 0.1 : 0.5))
            #expect(coverage.overrideActivations["inspection", default: 0] == (feature && permitted ? 1 : 0))
        }
    }

    @Test func leavingInspectionResumesMaximumWithoutResettingCounters() async throws {
        let settings = SamplingSettings(visibleMaximum: 0.5)
        let live = LiveInterval(settings: settings)
        let permission = LiveInspection(active: true)
        let reader = AdaptiveClockReader(live, permission: permission, releaseInspectionAt: 2)
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                samples: 4,
                reportIntervalSeconds: 1, inspectionObservations: true, sampling: settings),
            reader: reader, clock: reader, registry: reader)
        let result = Mutex<SamplingCoverage>(SamplingCoverage())
        try await session.run(interval: live, inspection: permission) { value in
            if let coverage = value.window?.acquisitionCoverage.sampling {
                result.withLock { $0.merge(coverage) }
            }
        }
        let coverage = result.withLock { $0 }
        #expect(coverage.overrideActivations["inspection"] == 1)
        #expect(coverage.latest?.requestedSeconds == 0.5)
        #expect((1.9...2.1).contains(coverage.overrideSeconds["inspection", default: 0]))
    }
    @Test func enabledStartsFastThenRelaxesInTheProductionLoop() async throws {
        let settings = SamplingSettings(enabled: true, visibleMaximum: 0.5, window: 1)
        let live = LiveInterval(settings: settings)
        let reader = AdaptiveClockReader(live)
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                samples: 4,
                reportIntervalSeconds: 1, sampling: settings), reader: reader, clock: reader, registry: reader
        )
        try await session.run(interval: live) { _ in }
        let starts = reader.state.withLock { $0.starts }
        #expect(starts[1] - starts[0] == 0.1)
        #expect(starts.filter { $0 < 1 }.count > 3)
        #expect(abs(starts[starts.count - 1] - starts[starts.count - 2] - 0.5) < 1e-9)
    }

    @Test func closedMaximumAppliesWithAdaptationOffFromStartup() async throws {
        let settings = SamplingSettings(visibleMaximum: 0.2, closedMultiplier: 2.5)
        let live = LiveInterval(settings: settings)
        live.setPanelVisible(false)
        let reader = AdaptiveClockReader(live)
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                samples: 1,
                sampling: settings), reader: reader, clock: reader, registry: reader)
        try await session.run(interval: live) { _ in }
        #expect(reader.state.withLock { $0.starts } == [0, 0.5])
    }

    @Test(arguments: [1, 3])
    func settingsAppliedDuringContinuousOverrunsRemainCountedThroughTheFinalScan(samples: Int) async throws {
        let live = LiveInterval(0.1)
        let reader = AdaptiveClockReader(live, slowSettingsChange: true)
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(intervalSeconds: 0.1, samples: samples),
            reader: reader, clock: reader, registry: reader)
        let timings = Mutex<[AcquisitionTiming]>([])
        try await session.run(interval: live) { value in
            if let timing = value.cpuAccounting.acquisition { timings.withLock { $0.append(timing) } }
        }
        let values = timings.withLock { $0 }
        #expect(values.count == samples)
        var coverage = AcquisitionCoverage()
        for (index, timing) in values.enumerated() {
            #expect(timing.sampling.latest?.maximumSeconds == 0.1 + Double(index + 1) * 0.02)
            #expect(timing.sampling.policyChangeCount == 1)
            // The deadline predates resolution of this scan's edit and is already due (architecture: adaptive acquisition).
            let effective = [0.1, 0.1, 0.12][index]
            #expect(abs(timing.effectivePeriodSeconds - effective) < 1e-9)
            coverage.append(timing)
        }
        #expect(coverage.sampling.policyChangeCount == samples)
        #expect(coverage.overrunCount == samples)
    }

    @Test func shorteningAnElapsedPeriodKeepsTheActualRequestAndEffectiveDeadlineSeparate() async throws {
        let live = LiveInterval(1)
        let reader = AdaptiveClockReader(live, shortenAt: 0.5)
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(intervalSeconds: 1, samples: 1),
            reader: reader, clock: reader, registry: reader)
        let timings = Mutex<[AcquisitionTiming]>([])
        try await session.run(interval: live) { value in
            if let timing = value.cpuAccounting.acquisition { timings.withLock { $0.append(timing) } }
        }
        let timing = try #require(timings.withLock { $0.first })
        #expect(reader.state.withLock { $0.starts } == [0, 0.5])
        #expect(timing.requestedPeriodSeconds == 0.1)
        #expect(timing.effectivePeriodSeconds == 0.5)
        #expect(timing.achievedPeriodSeconds == 0.5)
        #expect(timing.sampling.minimumRequestedSeconds == 0.1)
        #expect(timing.sampling.maximumRequestedSeconds == 1)
        #expect(timing.sampling.policyChangeCount == 1)
        var coverage = AcquisitionCoverage()
        coverage.append(timing)
        #expect(coverage.overrunCount == 0)
    }

    @Test func laterSettingCannotDeferAnAlreadyDueDeadline() async throws {
        let live = LiveInterval(0.1)
        let reader = AdaptiveClockReader(live, deferDueDeadline: true)
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(intervalSeconds: 0.1, samples: 1),
            reader: reader, clock: reader, registry: reader)
        let requested = Mutex<[Double]>([])
        try await session.run(interval: live) { value in
            requested.withLock { $0.append(value.intervalSeconds) }
        }
        #expect(reader.state.withLock { $0.starts } == [0, 0.1])
        #expect(requested.withLock { $0 } == [0.1])
    }
}

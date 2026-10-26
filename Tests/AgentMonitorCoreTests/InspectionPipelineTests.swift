import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

final class InspectionPipelineFixture: ProcessReading, AcquisitionClock, InspectionReading {
    struct State {
        var time = 0.0
        var supplemental = 0
        var waits: [Double] = []
    }
    let state = Mutex(State())
    func monotonicNow() -> Double { state.withLock { $0.time } }
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }
    func wait(until deadline: Double, wake: AcquisitionWake) {
        state.withLock {
            $0.time = deadline
            $0.waits.append(deadline)
        }
    }
    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let time = monotonicNow()
        return ProcessSnapshot(
            samples: [sample(1, start: 1, at: time, cpu: time)],
            enumeratedCount: 1, unreadableCount: 0, listedAt: time, scanSeconds: 0,
            hostCounters: nil, logicalCPUCount: 8, listedPIDs: [1])
    }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)], cwd: "/fake/work")
    }
    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        metadata(for: sample, includeCommand: false)
    }
    func inspectionPIDs(allowance: InspectionAllowance) throws -> [Int32] { [1, 42] }
    func inspectionRead(_ pid: Int32, allowance: InspectionAllowance) -> InspectionRead? {
        state.withLock { $0.supplemental += 1 }
        let time = monotonicNow()
        var worker = sample(42, parent: 1, start: UInt64(time * 1_000_000), at: time, cpu: 0.02)
        worker.startedAt = time - 0.03
        return InspectionRead(
            sample: worker, parent: ProcessIdentity(pid: 1, startMicroseconds: 1), cwd: "/fake/work")
    }
}

@Suite struct InspectionPipelineTests {
    @Test(arguments: [false, true]) func productionPipelineKeepsCompleteCadenceAndOnlyAdmitsHistoricalWorkers(
        enabled: Bool
    ) async throws {
        let reader = InspectionPipelineFixture()
        let history = RecentActivityStore()
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                intervalSeconds: 0.1,
                samples: 1, scope: .allProcesses, reportIntervalSeconds: 1, inspectionObservations: enabled),
            reader: reader, clock: reader, recentActivity: history)
        let reports = Mutex<[MonitoringSnapshot]>([])
        try await session.run(inspection: LiveInspection(active: true)) { snapshot in
            reports.withLock { $0.append(snapshot) }
        }
        let result = try #require(reports.withLock { $0.last })
        let window = try #require(result.window)
        #expect(window.finalScan == 10)
        #expect(window.acquisitionCoverage.scanCount == 10)
        #expect(window.acquisitionCoverage.overrunCount == 0)
        #expect(result.sampledProcessCount == 1)
        #expect(result.observedFindings.filter { !$0.isHistorical }.count == 1)
        #expect(reader.state.withLock { $0.supplemental } == (enabled ? 10 : 0))
        #expect(window.inspectionCoverage.mode == (enabled ? .enabled : .disabled))
        #expect(window.inspectionCoverage.carriedObservations == (enabled ? 10 : 0))
        let workers = window.contributions.filter { $0.process.pid == 42 }
        #expect(abs(workers.reduce(0) { $0 + $1.cpuSeconds } - (enabled ? 0.2 : 0)) < 1e-9)
        #expect(workers.allSatisfy { $0.attribution.threadID == sessionA })
        #expect(history.snapshot()?.current.count == 1)
    }
}

extension InspectionPipelineTests {
    @Test func disabledInspectionMatchesTheCompleteOnlyTrace() async throws {
        func collect(enabled: Bool, active: Bool) async throws -> MonitoringSnapshot {
            let reader = InspectionPipelineFixture()
            let session = MonitoringSession(
                configuration: try MonitoringConfiguration(
                    intervalSeconds: 0.1,
                    samples: 1, scope: .allProcesses, reportIntervalSeconds: 1,
                    inspectionObservations: enabled),
                reader: reader, clock: reader)
            let values = Mutex<[MonitoringSnapshot]>([])
            try await session.run(inspection: LiveInspection(active: active)) { value in
                values.withLock { $0.append(value) }
            }
            #expect(reader.state.withLock { $0.supplemental } == 0)
            return try #require(values.withLock { $0.last })
        }
        let baseline = try await collect(enabled: false, active: false)
        for flags in [(false, true), (true, false)] {
            let result = try await collect(enabled: flags.0, active: flags.1)
            #expect(result.observedFindings == baseline.observedFindings)
            #expect(result.sampledProcessCount == baseline.sampledProcessCount)
            #expect(result.unreadableProcessCount == baseline.unreadableProcessCount)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            func normalized(_ snapshot: MonitoringSnapshot) throws -> String {
                let window = try #require(snapshot.window)
                return String(decoding: try encoder.encode(window), as: UTF8.self)
                    .replacingOccurrences(of: window.runID.uuidString, with: "RUN")
            }
            #expect(try normalized(result) == normalized(baseline))
        }
    }
}

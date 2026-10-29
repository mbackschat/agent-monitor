import AgentMonitorCore
import AgentMonitorPresentation
import Foundation
import Synchronization

extension Preview {
    static func ledgerState(
        beforeMetadata: @escaping @Sendable () -> Void = {},
        receive: @escaping @Sendable (MonitoringSnapshot) -> Void = { _ in }
    ) async throws -> LiveReportState {
        let state = Mutex(
            LiveReportState(
                cpuTopology: ProcessorTopology(
                    logicalCPUCount: 8,
                    levels: [
                        .init(name: "Performance", logicalCPUCount: 4),
                        .init(name: "Efficiency", logicalCPUCount: 4),
                    ])))
        let fixture = LedgerPreviewReader(beforeMetadata: beforeMetadata)
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                intervalSeconds: 1, samples: 12, collectAgentLoad: true, reportIntervalSeconds: 1),
            reader: fixture, clock: fixture, recentActivity: RecentActivityStore())
        try await session.run { snapshot in
            state.withLock { $0.receive(snapshot) }
            receive(snapshot)
            fixture.acknowledge(snapshot)
        }
        return state.withLock { value in
            value.overview.showAll = true
            return value
        }
    }
}

private final class LedgerPreviewReader: ProcessReading, AcquisitionClock {
    let beforeMetadata: @Sendable () -> Void
    init(beforeMetadata: @escaping @Sendable () -> Void) { self.beforeMetadata = beforeMetadata }
    private struct ClockState {
        var time = 0.0
        var deliveredThrough = 0.0
        var waiter: AcquisitionWake?
    }
    private let clock = Mutex(ClockState())

    func monotonicNow() -> Double { clock.withLock { $0.time } }
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }

    func acknowledge(_ snapshot: MonitoringSnapshot) {
        let wake = clock.withLock { state in
            state.deliveredThrough = snapshot.timestamp.timeIntervalSince1970
            return state.waiter
        }
        wake?.signal()
    }

    func wait(until deadline: Double, wake: AcquisitionWake) throws {
        // PREVIEW-01: acknowledge each synthetic report before advancing to prevent
        // scheduling-dependent publication coalescing; the baseline has no report.
        let ready = clock.withLock { state in
            if state.deliveredThrough >= state.time {
                state.time = deadline
                state.waiter = nil
                return true
            }
            state.waiter = wake
            return false
        }
        if !ready {
            wake.wait(seconds: 5)
            guard clock.withLock({ $0.deliveredThrough >= $0.time }) else {
                throw PreviewError.message("Synthetic preview did not receive its pending report.")
            }
        }
    }
    private let names = ["java", "rustc", "node", "python", "swift-frontend", "node", "pytest", "node"]
    private let cpu = [1.42, 0.63, 0.37, 0.12, 0.014, 0.002, 0.096, 0.08]
    private let memory: [UInt64] = [
        1_800_000_000, 2_400_000_000, 900_000_000, 400_000_000, 200_000_000, 3_200_000_000, 100_000_000,
        300_000_000,
    ]
    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let time = Int(monotonicNow())
        let samples = names.indices.filter { $0 != 6 || time < 9 }.map { index in
            ProcessSample(
                identity: ProcessIdentity(pid: Int32(42000 + index), startMicroseconds: UInt64(index + 1)),
                parentPID: 0, executable: "/usr/local/bin/" + names[index], name: names[index],
                sampledAt: Double(time),
                cpuSeconds: (0..<time).reduce(0.0) { sum, interval in
                    let phases = [0.1, 0.2, 0.55, 1.0, 0.9, 0.75, 1.1, 0.9, 1.15, 0.95, 1.1, 1.0]
                    return sum + cpu[index] * phases[(interval + index * 2) % phases.count]
                }, footprintBytes: memory[index])
        }
        return ProcessSnapshot(
            samples: samples, enumeratedCount: samples.count, unreadableCount: 0,
            listedAt: Double(time), scanSeconds: 0, hostCounters: nil, logicalCPUCount: 8)
    }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        beforeMetadata()
        return metadataValue(for: sample)
    }

    func metadata(
        for sample: ProcessSample, includeCommand: Bool, capturedLaunch: ProcessMetadata?
    ) -> ProcessMetadata {
        metadata(for: sample, includeCommand: includeCommand)
    }

    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        metadataValue(for: sample)
    }

    private func metadataValue(for sample: ProcessSample) -> ProcessMetadata {
        let index = Int(sample.identity.pid - 42000)
        let projects = [
            "atlas/api", "orbit", "atlas/web", "harbor", "sample-app", "atlas/cache", "tests", "shared",
        ]
        return ProcessMetadata(
            markers: index == 7
                ? []
                : [
                    SessionMarker(
                        threadID: String(format: "%08d-1111-4111-8111-111111111111", index + 1),
                        provider: index.isMultiple(of: 2) ? .claude : .codex)
                ],
            status: .markerRead, cwd: "/projects/" + projects[index])
    }
}

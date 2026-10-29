import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private let claudeExecutable = "/Users/test/.local/share/claude/versions/2.1.301"

private final class NativeSessionFixture: AcquisitionClock, ProcessReading, Sendable {
    let reportRead = ClockGate()
    let marked: Bool
    let times = Mutex<[Double]>([0])

    init(marked: Bool) { self.marked = marked }

    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let at = monotonicNow()
        return ProcessSnapshot(
            samples: [sample(10, executable: marked ? "/usr/bin/node" : claudeExecutable, at: at, cpu: at)],
            enumeratedCount: 2, unreadableCount: 0, listedAt: at, scanSeconds: 0, hostCounters: nil,
            logicalCPUCount: 8)
    }

    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        metadata(for: sample, includeCommand: false)
    }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        ProcessArguments.parse(
            argumentBuffer(
                arguments: [marked ? "node" : "claude"],
                environment: marked ? ["CLAUDE_CODE_SESSION_ID=\(sessionA)"] : []))
    }

    func isCurrent(_ sample: ProcessSample) -> Bool { true }

    func wait(until deadline: Double, wake: AcquisitionWake) throws {
        let seconds = max(0, deadline - monotonicNow())
        if monotonicNow() > 0 {
            guard reportRead.wait(wake: wake) else { return }
        }
        times.withLock { $0.append(($0.last ?? 0) + seconds) }
    }
    func monotonicNow() -> Double { times.withLock { $0.last ?? 0 } }
    func now() -> Date { Date(timeIntervalSince1970: 0) }
}

@Test(arguments: [false, true])
func offlineMonitoringPreservesNativeEvidenceWithoutProviderWork(
    marked: Bool
) async throws {
    let fake = NativeSessionFixture(marked: marked)
    let configuration = try MonitoringConfiguration(samples: 3)
    let session = MonitoringSession(configuration: configuration, reader: fake, clock: fake)
    let findings = Mutex<[HeavyProcess]>([])
    try await session.run { snapshot in
        defer { fake.reportRead.signal() }
        findings.withLock { $0.append(contentsOf: snapshot.findings) }
    }
    let rows = findings.withLock { $0 }
    #expect(rows.count == 3)
    #expect(rows.allSatisfy { $0.cpuPercent == 100 })
    #expect(rows.allSatisfy { $0.attribution.threadID == (marked ? sessionA : nil) })
    #expect(rows.allSatisfy { $0.attribution.evidence == (marked ? .marker : .runtimeOnly) })
}

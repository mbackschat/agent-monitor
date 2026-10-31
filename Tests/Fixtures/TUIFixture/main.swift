import AgentMonitorActions
import AgentMonitorCore
import AgentMonitorTUI
import Foundation
import Synchronization

@main
enum TUIFixture {
    static func main() async throws {
        let samplingPath = ProcessInfo.processInfo.environment["AGENT_MONITOR_SAMPLING_FIXTURE"]
        let sampling = samplingPath.map { _ in
            SamplingSettings(
                enabled: true, minimum: 0.4, visibleMaximum: 1, closedMultiplier: 2.5, window: 17)
        }
        try await TerminalReport.run(
            sampling: sampling, color: !CommandLine.arguments.contains("--no-color"),
            actions: FixtureActions(),
            diagnosisSource: {
                if let path = ProcessInfo.processInfo.environment["AGENT_MONITOR_DIAGNOSIS_GATE"] {
                    while !FileManager.default.fileExists(atPath: path) {
                        try await Task.sleep(for: .milliseconds(20))
                    }
                }
                return try await CPUDiagnosisSession(
                    reader: FixtureDiagnosisReader(), excluding: [99], monitorPID: 99
                ).run()
            },
            commandSource: { _ in ["fixture-node", "--example", "two words"] },
            source: { currentThresholds, interval, receive in
                if ProcessInfo.processInfo.environment["AGENT_MONITOR_OVERVIEW_FIXTURE"] == "1" {
                    let session = MonitoringSession(
                        configuration: try MonitoringConfiguration(
                            intervalSeconds: 0.1, samples: 0, collectAgentLoad: true, reportIntervalSeconds: 1
                        ),
                        reader: FixtureOverviewReader(), recentActivity: RecentActivityStore())
                    try await session.run(thresholds: currentThresholds, interval: interval, receive)
                    return
                }
                var tick = 0
                var recordedSettings: SamplingSettings?
                while !Task.isCancelled {
                    if let samplingPath, interval.settings != recordedSettings {
                        let settings = interval.settings
                        try JSONEncoder().encode(settings).write(
                            to: URL(fileURLWithPath: samplingPath), options: .atomic)
                        recordedSettings = settings
                    }
                    tick += 1
                    let rows = try [
                        row(pid: 42, cpu: tick.isMultiple(of: 2) ? 40 : 90), row(pid: 84, cpu: 60),
                    ]
                    let thresholds = await currentThresholds()
                    let findings = rows.filter {
                        thresholds.includes(cpu: $0.cpuPercent, footprint: $0.footprintBytes)
                    }
                    try await receive(
                        MonitoringSnapshot(
                            cpuAccounting: CPUAccounting(
                                hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0,
                                unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
                            timestamp: Date(), intervalSeconds: 1,
                            cpuThresholdPercent: thresholds.cpuPercent,
                            memoryThresholdBytes: thresholds.memoryBytes,
                            sampledProcessCount: 2, unreadableProcessCount: 0, findings: findings,
                            agentLoad: AgentLoadSummary(processes: rows), observedFindings: rows))
                    try await Task.sleep(for: .seconds(1))
                }
            })
    }

    private static func row(pid: Int32, cpu: Int) throws -> HeavyProcess {
        try JSONDecoder().decode(
            HeavyProcess.self,
            from: Data(
                """
                {"process":{"pid":\(pid),"startMicroseconds":1},"executable":"/fixture/worker", "name":"fixture-\(pid)",
                 "cpuPercent":\(cpu),"footprintBytes":1200000000,"cwd":"/fixture/project", "metadataStatus":"notObserved",
                 "attribution":{"provider":"codex","evidence":"ambiguous","context":"terminal",
                 "terminal":"ttys001","candidateThreadIDs":["11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222"],
                 "runtime":{"pid":1234,"startMicroseconds":1},"ancestry":[]}}
                """.utf8))
    }
}

private struct FixtureActions: ProcessActions {
    func terminate(_ process: HeavyProcess) async throws {
        if let path = ProcessInfo.processInfo.environment["AGENT_MONITOR_TERMINATION_FIXTURE"] {
            try String(process.process.pid).write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
    func focusTerminal(of process: HeavyProcess) async throws -> FocusOutcome {
        .session(application: "Terminal", tty: "/dev/ttys001")
    }
}

private final class FixtureDiagnosisReader: DiagnosisReading, Sendable {
    private let index = Mutex(0)
    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let tick = index.withLock { value in
            defer { value += 1 }
            return value
        }
        let sample = ProcessSample(
            identity: ProcessIdentity(pid: 42001, startMicroseconds: 1), parentPID: 99,
            executable: "/fixture/diagnosis-worker", name: "diagnosis-worker", sampledAt: 100 + Double(tick),
            cpuSeconds: Double(tick), footprintBytes: 1_000_000)
        return ProcessSnapshot(
            samples: [sample], enumeratedCount: 1, unreadableCount: 0,
            listedAt: 100 + Double(tick), scanSeconds: 0.05, hostCounters: nil, logicalCPUCount: 8)
    }
    func observation(for sample: ProcessSample) -> DiagnosisObservation { .observed(ProcessMetadata()) }
    func isCurrent(_ sample: ProcessSample) -> Bool { true }
}

private final class FixtureOverviewReader: ProcessReading, Sendable {
    let tick = Mutex(0)
    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let step = tick.withLock { value in
            defer { value += 1 }
            return value
        }
        let sample = ProcessSample(
            identity: ProcessIdentity(pid: 42, startMicroseconds: 1), parentPID: 0,
            executable: "/fixture/node", name: "fixture-worker", sampledAt: Double(step),
            cpuSeconds: Double(step) * 0.2, footprintBytes: 400_000_000)
        return ProcessSnapshot(
            samples: [sample], enumeratedCount: 1, unreadableCount: 0,
            listedAt: Double(step), scanSeconds: 0, hostCounters: nil, logicalCPUCount: 8)
    }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        ProcessMetadata(
            markers: [SessionMarker(threadID: "11111111-1111-4111-8111-111111111111", provider: .codex)],
            status: .markerRead, cwd: "/fixture/overview-project")
    }
}

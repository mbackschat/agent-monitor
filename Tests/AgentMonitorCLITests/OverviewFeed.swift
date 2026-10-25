import AgentMonitorPresentation
import Foundation

@testable import AgentMonitorCore

/// Drives the production ledger, accounting window and recent-history store one second per tick,
/// so overview tests observe the same categories, crossings and current records as live collection.
struct OverviewFeed {
    struct Worker {
        var session: String?
        var provider: AgentProvider = .claude
        var executable: String
        var pid: Int32
        var cpuPerSecond: Double
        var memory: UInt64 = 1_000_000
        var cwd: String? = "/fixture"
        var command: [String]? = nil
        var runtime = false
    }

    private var ledger = CounterLedger()
    private var previous: CounterScan?
    private var cpu: [Int32: Double] = [:]
    private var tick = 0
    let store = RecentActivityStore()

    /// The first call only establishes the counter baseline; later calls each close one unit.
    mutating func advance(_ workers: [Worker]) throws -> MonitoringSnapshot {
        for worker in workers { cpu[worker.pid, default: 0] += worker.cpuPerSecond }
        let samples = workers.map { worker in
            ProcessSample(
                identity: ProcessIdentity(pid: worker.pid, startMicroseconds: 1), parentPID: 0,
                executable: "/bin/" + worker.executable, name: worker.executable, sampledAt: Double(tick),
                cpuSeconds: cpu[worker.pid] ?? 0, footprintBytes: worker.memory)
        }
        let scan = ledger.ingest(samples, listedAt: Double(tick))
        defer {
            previous = scan
            tick += 1
        }
        guard let previous else { return snapshot() }
        var window = AccountingWindow(baseline: previous)
        try window.append(
            scan,
            rows: zip(workers, samples).map { worker, value in
                HeavyProcess(
                    process: value.identity, executable: value.executable, name: value.name, cpuPercent: nil,
                    footprintBytes: value.footprintBytes, cwd: worker.cwd, command: worker.command,
                    metadataStatus: .markerRead,
                    attribution: Attribution(
                        provider: worker.session == nil ? nil : worker.provider,
                        evidence: worker.session == nil ? .unknown : .marker, context: .unverified,
                        threadID: worker.session, rootSessionID: nil, runtime: nil, terminal: nil,
                        runtimeDirectory: nil, candidateThreadIDs: [], ancestry: []))
            }, runtimes: Set(zip(workers, samples).filter { $0.0.runtime }.map(\.1.identity)))
        store.append(window.seal(scope: .agentsOnly), current: window.current, present: window.present)
        return snapshot()
    }

    private func snapshot() -> MonitoringSnapshot {
        MonitoringSnapshot(
            cpuAccounting: CPUAccounting(
                hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: 0, unmeasuredLifetimeCount: 0,
                previousScanSeconds: nil),
            timestamp: Date(timeIntervalSince1970: Double(tick)), intervalSeconds: 0.1,
            cpuThresholdPercent: 0,
            memoryThresholdBytes: 0, sampledProcessCount: 0, unreadableProcessCount: 0, findings: [],
            recentActivity: store.snapshot())
    }
}

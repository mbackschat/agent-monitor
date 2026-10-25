import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct WorkloadDirectoryTests {
    /// Locks the rule that CPU stays with the directory observed for its interval: a later `cd`
    /// must not relabel earlier work, and an unreadable directory stays its own category rather
    /// than inheriting a neighbour's. The oracle is conservation of every measured interval.
    @Test func directoryChangeSplitsCPUWithoutRelabelingEarlierWork() throws {
        var ledger = CounterLedger()
        let identity = ProcessIdentity(pid: 7, startMicroseconds: 1)
        func scan(_ tick: Int) -> CounterScan {
            ledger.ingest(
                [
                    ProcessSample(
                        identity: identity, parentPID: 0, executable: "/bin/cargo", name: "cargo",
                        sampledAt: Double(tick), cpuSeconds: Double(tick), footprintBytes: 1_000)
                ], listedAt: Double(tick))
        }
        func row(_ cwd: String?) -> HeavyProcess {
            HeavyProcess(
                process: identity, executable: "/bin/cargo", name: "cargo", cpuPercent: nil,
                footprintBytes: 1_000, cwd: cwd, command: nil, metadataStatus: .markerRead,
                attribution: Attribution(
                    provider: .codex, evidence: .marker, context: .unverified, threadID: "session",
                    rootSessionID: nil, runtime: nil, terminal: nil, runtimeDirectory: nil,
                    candidateThreadIDs: [], ancestry: []))
        }
        var window = AccountingWindow(baseline: scan(0))
        for (tick, cwd) in [(1, "/a"), (2, "/a"), (3, "/b"), (4, nil)] {
            try window.append(scan(tick), rows: [row(cwd)])
        }
        let records = window.seal(scope: .agentsOnly).records
        let byDirectory = Dictionary(grouping: records, by: \.cwd).mapValues {
            $0.reduce(0) { $0 + $1.cpuSeconds }
        }
        #expect(byDirectory == ["/a": 2, "/b": 1, nil: 1])
        #expect(Set(records.map(\.category.process)) == [identity])
    }
}

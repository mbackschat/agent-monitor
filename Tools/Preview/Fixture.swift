import AgentMonitorCore
import AgentMonitorPresentation
import Foundation

extension Preview {
    static func state() throws -> LiveReportState {
        let rows = try [
            row(
                pid: 42001, name: "swift-frontend", cpu: 184.6, memory: 1_420_000_000, provider: "codex",
                session: "11111111-1111-4111-8111-111111111111", project: "sample-app", tty: "ttys001",
                runtime: 41000),
            row(
                pid: 42002, name: "node", cpu: 76.3, memory: 620_000_000, provider: "claude",
                session: "22222222-2222-4222-8222-222222222222", project: "sample-web", tty: "ttys002",
                runtime: 41001),
            row(
                pid: 42003, name: "python", cpu: 38.2, memory: 310_000_000, provider: "codex",
                session: "11111111-1111-4111-8111-111111111111", project: "sample-app", tty: "ttys001",
                runtime: 41000),
            row(
                pid: 42004, name: "java", cpu: 8.5, memory: 2_160_000_000, provider: "claude",
                session: "22222222-2222-4222-8222-222222222222", project: "sample-web", tty: "ttys002",
                runtime: 41001),
            row(
                pid: 42005, name: "codex", cpu: 2.1, memory: 1_180_000_000, provider: "codex", session: nil,
                project: "sample-tools", tty: nil, runtime: 42005, ambiguous: true),
        ]
        var state = LiveReportState()
        for tick in 0..<40 {
            let historyRows =
                try [
                    row(
                        pid: 42001, name: "swift-frontend", cpu: [10, 30, 80, 260, 184.6][tick % 5],
                        memory: 1_420_000_000, provider: "codex",
                        session: "11111111-1111-4111-8111-111111111111", project: "sample-app",
                        tty: "ttys001", runtime: 41000)
                ] + rows.dropFirst()
            state.receive(
                MonitoringSnapshot(
                    timestamp: Date(timeIntervalSince1970: Double(tick * 15)), intervalSeconds: 15,
                    cpuThresholdPercent: 25, memoryThresholdBytes: 1_000_000_000,
                    sampledProcessCount: 624, unreadableProcessCount: 0, findings: historyRows,
                    agentLoad: AgentLoadSummary(processes: historyRows)))
        }
        state.select(.process(rows[0].process))
        state.toggleDisclosure()
        state.toggleSelectedPin()
        return state
    }

    private static func row(
        pid: Int, name: String, cpu: Double, memory: UInt64, provider: String, session: String?,
        project: String, tty: String?, runtime: Int, ambiguous: Bool = false
    ) throws -> HeavyProcess {
        var attribution: [String: Any] = [
            "provider": provider, "evidence": ambiguous ? "ambiguous" : "inheritedMarker",
            "context": tty == nil ? "nonterminal" : "terminal",
            "runtime": ["pid": runtime, "startMicroseconds": pid == runtime ? 2 : 1],
            "runtimeDirectory": "/projects/\(project)",
            "candidateThreadIDs": ambiguous
                ? ["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"] : [],
            "ancestry": pid == runtime
                ? [["pid": pid, "startMicroseconds": 2]]
                : [["pid": pid, "startMicroseconds": 2], ["pid": runtime, "startMicroseconds": 1]],
        ]
        if let tty { attribution["terminal"] = tty }
        if let session { attribution["threadID"] = session }
        let value: [String: Any] = [
            "process": ["pid": pid, "startMicroseconds": 2], "executable": "/usr/local/bin/\(name)",
            "name": name, "cpuPercent": cpu, "footprintBytes": memory, "cwd": "/projects/\(project)",
            "metadataStatus": "markerRead", "attribution": attribution,
        ]
        return try JSONDecoder().decode(
            HeavyProcess.self, from: JSONSerialization.data(withJSONObject: value))
    }
}

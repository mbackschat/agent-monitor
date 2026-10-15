import AgentMonitorActions
import AgentMonitorCore
import AgentMonitorTUI
import Foundation

@main
enum TUIFixture {
    static func main() async throws {
        try await TerminalReport.run(actions: FixtureActions()) { currentThresholds, _, receive in
            var tick = 0
            while !Task.isCancelled {
                tick += 1
                let rows = try [row(pid: 42, cpu: tick.isMultiple(of: 2) ? 40 : 90), row(pid: 84, cpu: 60)]
                let thresholds = await currentThresholds()
                let findings = rows.filter {
                    ($0.cpuPercent ?? 0) > thresholds.cpuPercent
                        || ($0.footprintBytes ?? 0) > thresholds.memoryBytes
                }
                try await receive(
                    MonitoringSnapshot(
                        timestamp: Date(), intervalSeconds: 1,
                        cpuThresholdPercent: thresholds.cpuPercent,
                        memoryThresholdBytes: thresholds.memoryBytes,
                        sampledProcessCount: 2, unreadableProcessCount: 0, findings: findings,
                        agentLoad: AgentLoadSummary(processes: rows)))
                try await Task.sleep(for: .seconds(1))
            }
        }
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
    func terminate(_ process: HeavyProcess) async throws {}
    func prepareMessage(for process: HeavyProcess) async throws -> MessageDraft {
        MessageDraft(
            process: process,
            recipients: MessageRecipients(
                root: AgentRecipient(id: "22222222-2222-4222-8222-222222222222", label: "Root agent"),
                selected: AgentRecipient(id: "11111111-1111-4111-8111-111111111111", label: "Selected agent"))
        )
    }
    func send(_ draft: MessageDraft, text: String, recipient: String) async throws {}
    func focusTerminal(of process: HeavyProcess) async throws -> FocusOutcome {
        .session(application: "Terminal", tty: "/dev/ttys001")
    }
}

import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitor
@testable import AgentMonitorCore

@Test func textReportDatesSamplesAndSummarizesAmbiguousThreadsWithoutLosingJSONEvidence() throws {
    let candidates = ["11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222"]
    let identity = ProcessIdentity(pid: 42, startMicroseconds: 1)
    let row = HeavyProcess(
        process: identity, executable: "/opt/bin/codex", name: "codex", cpuPercent: 1,
        footprintBytes: 2_000_000_000, cwd: nil, command: nil, metadataStatus: .notObserved,
        attribution: Attribution(
            provider: .codex, evidence: .ambiguous, context: .nonterminal, threadID: nil,
            rootSessionID: nil, runtime: identity, terminal: nil, runtimeDirectory: nil,
            candidateThreadIDs: candidates, ancestry: [identity]))
    let report = MonitoringSnapshot(
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1, cpuThresholdPercent: 25,
        memoryThresholdBytes: 1_000_000_000, sampledProcessCount: 1, unreadableProcessCount: 0,
        findings: [row])
    let text = TextReport.render(report)
    #expect(text.hasPrefix("\n" + String(repeating: "=", count: 72) + "\nAgent Monitor |"))
    #expect(text.contains("1970-01-01T00:00:00Z"))
    #expect(text.contains("Candidate threads: 2 (use --json for IDs)"))
    #expect(text.contains("unresolved [ambiguous, nonterminal]"))
    let json = String(decoding: try JSONEncoder().encode(JSONReport(report)), as: UTF8.self)
    for candidate in candidates {
        #expect(!text.contains(candidate))
        #expect(json.contains(candidate))
    }
}

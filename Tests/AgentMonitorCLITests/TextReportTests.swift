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

@Test(arguments: [
    (AgentProvider?.some(.codex), "Codex launch session"), (.claude, "Claude Code launch session"),
    (nil, "Agent launch session"),
])
func textReportNamesTheProvider(provider: AgentProvider?, label: String) {
    let identity = ProcessIdentity(pid: 42, startMicroseconds: 1)
    let row = HeavyProcess(
        process: identity, executable: "/opt/bin/worker", name: "worker", cpuPercent: 1,
        footprintBytes: 2_000_000_000, cwd: nil, command: nil, metadataStatus: .markerRead,
        attribution: Attribution(
            provider: provider, evidence: .marker, context: .terminal,
            threadID: "11111111-1111-4111-8111-111111111111", rootSessionID: nil, runtime: nil, terminal: nil,
            runtimeDirectory: nil, candidateThreadIDs: [], ancestry: [identity]))
    let report = MonitoringSnapshot(
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1, cpuThresholdPercent: 25,
        memoryThresholdBytes: 1_000_000_000, sampledProcessCount: 1, unreadableProcessCount: 0,
        findings: [row])
    #expect(TextReport.render(report).contains(label))
}

private func unresolvedReport() -> MonitoringSnapshot {
    let identity = ProcessIdentity(pid: 42, startMicroseconds: 1)
    let row = HeavyProcess(
        process: identity, executable: "/opt/bin/worker", name: "worker", cpuPercent: 1,
        footprintBytes: 2_000_000_000, cwd: "/work", command: nil, metadataStatus: .notObserved,
        attribution: Attribution(
            provider: .codex, evidence: .ambiguous, context: .terminal, threadID: nil, rootSessionID: nil,
            runtime: nil, terminal: nil, runtimeDirectory: nil, candidateThreadIDs: [], ancestry: [identity]))
    return MonitoringSnapshot(
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1, cpuThresholdPercent: 25,
        memoryThresholdBytes: 1_000_000_000, sampledProcessCount: 1, unreadableProcessCount: 0,
        findings: [row])
}

@Test(arguments: [ReportGrouping.none, .session])
func textReportLinesCarryRoles(grouping: ReportGrouping) {
    let lines = TextReport.lines(unresolvedReport(), grouping: grouping)
    #expect(lines.first { $0.text.hasPrefix("Agent Monitor |") }?.style == .title)
    #expect(lines.first { $0.text.hasPrefix("PID 42") }?.style == .heavy)
    #expect(lines.first { $0.text.contains(": unresolved [") }?.style == .warning)
    #expect(lines.first { $0.text.contains("Work directory") }?.style == .muted)
}

// Color only adds SGR sequences; removing them must give back the exact plain report.
@Test(arguments: [ReportGrouping.none, .session])
func coloredTextReportIsThePlainReportWithSGR(grouping: ReportGrouping) {
    let plain = TextReport.render(unresolvedReport(), grouping: grouping)
    #expect(!plain.contains("\u{1B}"))
    let colored = TextReport.render(unresolvedReport(), grouping: grouping, color: true)
    #expect(colored.contains("\u{1B}[1;34mAgent Monitor |"))
    #expect(colored.replacing(/\x{1B}\[[0-9;]*m/, with: "") == plain)
}

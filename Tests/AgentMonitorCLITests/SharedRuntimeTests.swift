import AgentMonitorPresentation
import Foundation
import Testing

@testable import AgentMonitorCore

private let sharedThreads = [
    "11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222",
]

private func runtimeRow(
    pid: Int32 = 42, runtimeStart: UInt64 = 1, provider: AgentProvider? = .codex,
    thread: String? = nil, candidates: [String] = sharedThreads, directory: String? = nil
) -> HeavyProcess {
    let identity = ProcessIdentity(pid: pid, startMicroseconds: 1)
    return HeavyProcess(
        process: identity, executable: "/opt/bin/codex", name: "codex", cpuPercent: 50,
        footprintBytes: 2_000_000_000, cwd: directory, command: nil, metadataStatus: .notObserved,
        attribution: Attribution(
            provider: provider, evidence: thread == nil ? .ambiguous : .marker, context: .nonterminal,
            threadID: thread, rootSessionID: nil,
            runtime: ProcessIdentity(pid: 42, startMicroseconds: runtimeStart), terminal: nil,
            runtimeDirectory: directory, candidateThreadIDs: candidates, ancestry: [identity]))
}

private func runtimeSnapshot(_ rows: [HeavyProcess]) -> MonitoringSnapshot {
    MonitoringSnapshot(
        timestamp: Date(timeIntervalSince1970: 0), intervalSeconds: 1, cpuThresholdPercent: 25,
        memoryThresholdBytes: 1_000_000_000, sampledProcessCount: rows.count, unreadableProcessCount: 0,
        findings: rows)
}

@Test(arguments: [ReportGrouping.none, .session], [60, 120])
func sharedRuntimeIsNamedInReportsDetailsAndActions(grouping: ReportGrouping, width: Int) throws {
    let row = runtimeRow()
    let report = runtimeSnapshot([row])
    let text = TextReport.render(report, grouping: grouping)
    #expect(text.contains("shared runtime"))
    #expect(!text.contains("unresolved"))
    #expect(ActionWording.target(row).joined(separator: "\n").contains("codex/shared runtime"))
    var state = LiveReportState(grouping: grouping)
    state.receive(report)
    let lines = LiveReportLayout.lines(state: state, width: width, height: 24)
    #expect(lines.contains { $0.text.contains("shared runtime") })
    #expect(lines.allSatisfy { $0.text.count <= width })
    if grouping == .session {
        state.toggleDisclosure()
        state.moveSelection(by: 1)
    }
    state.toggleDisclosure()
    let details = LiveReportLayout.lines(state: state, width: 120, height: 40).map(\.text).joined(
        separator: "\n")
    #expect(details.contains("Session: shared runtime"))
    #expect(!details.contains("Session: unresolved"))
    let json = String(decoding: try JSONEncoder().encode(JSONReport(report)), as: UTF8.self)
    #expect(json.contains("ambiguous"))
    #expect(!json.contains("shared runtime"))
    for thread in sharedThreads { #expect(json.contains(thread)) }
}

enum NonSharedRuntimeCase: CaseIterable {
    case descendant, singleWriter, duplicateWriter, unknownProvider, claude, exactSession, reusedPID
}

@Test(arguments: NonSharedRuntimeCase.allCases)
func sharedRuntimeLabelRequiresTheRuntimeItselfAndDistinctCodexThreads(_ scenario: NonSharedRuntimeCase) {
    let row: HeavyProcess
    switch scenario {
    case .descendant: row = runtimeRow(pid: 43)
    case .singleWriter: row = runtimeRow(candidates: [sharedThreads[0]])
    case .duplicateWriter: row = runtimeRow(candidates: [sharedThreads[0], sharedThreads[0]])
    case .unknownProvider: row = runtimeRow(provider: nil)
    case .claude: row = runtimeRow(provider: .claude)
    case .exactSession: row = runtimeRow(thread: sharedThreads[0])
    case .reusedPID: row = runtimeRow(runtimeStart: 2)
    }
    #expect(!TextReport.render(runtimeSnapshot([row]), grouping: .session).contains("shared runtime"))
    #expect(!ActionWording.target(row).joined(separator: "\n").contains("shared runtime"))
}

@Test func sharedRuntimeRemainsSeparateFromItsExactAndUnresolvedWorkloads() throws {
    let runtime = runtimeRow()
    let exact = runtimeRow(pid: 43, thread: sharedThreads[0])
    let unresolved = runtimeRow(pid: 44)
    let groups = SessionGrouping.groups([runtime, exact, unresolved])
    #expect(groups.count == 3)
    #expect(groups.first { $0.processes == [runtime] }?.label.contains("shared runtime") == true)
    #expect(groups.first { $0.processes == [exact] }?.sessionID == sharedThreads[0])
    #expect(groups.first { $0.processes == [unresolved] }?.label.contains("unresolved PID 44") == true)
}

@Test func sharedRuntimeProjectDoesNotClaimItsLaunchDirectory() throws {
    let row = runtimeRow(directory: "/launch/unrelated-project")
    #expect(row.isSharedRuntime)
    let group = try #require(SessionGrouping.groups([row]).first)
    #expect(group.project == "Shared runtime")
    #expect(!group.label.contains("unrelated-project"))
    var state = LiveReportState()
    state.receive(runtimeSnapshot([row]))
    let text = LiveReportLayout.lines(state: state, width: 160, height: 24).map(\.text).joined(
        separator: "\n")
    #expect(!text.contains("unrelated-project"))
    #expect(TextReport.render(runtimeSnapshot([row])).contains("/launch/unrelated-project"))
}

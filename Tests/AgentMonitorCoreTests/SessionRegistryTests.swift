import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private let claudeExecutable = "/Users/test/.local/share/claude/versions/2.1.301"

private func listing(_ entries: [[String: Any]]) throws -> Data {
    try JSONSerialization.data(withJSONObject: entries)
}

private func entry(pid: Int, session: String = sessionB, status: String = "busy") -> [String: Any] {
    ["pid": pid, "sessionId": session.uppercased(), "status": status, "kind": "interactive", "cwd": "/x"]
}

/// Runtime 10 hosts a session; its Bash-tool shell exposes no environment and a worker below it
/// still carries the marker of the session that launched it.
private func claudeSession() -> (Monitor, runtime: ProcessSample, shell: ProcessSample, worker: ProcessSample)
{
    let runtime = sample(10, executable: claudeExecutable, terminal: "ttys010")
    let shell = sample(15, parent: 10, executable: "/bin/zsh")
    let worker = sample(20, parent: 15)
    var monitor = Monitor()
    monitor.ingest([runtime, shell, worker])
    let metadata = [
        runtime.identity: ProcessArguments.parse(argumentBuffer(arguments: ["claude"], environment: [])),
        shell.identity: ProcessArguments.parse(argumentBuffer(arguments: ["/bin/zsh"], environment: [])),
        worker.identity: ProcessArguments.parse(
            argumentBuffer(environment: ["CLAUDE_CODE_SESSION_ID=\(sessionA)"])),
    ]
    monitor.enrich(for: [runtime.identity, shell.identity, worker.identity]) {
        metadata[$0.identity] ?? ProcessMetadata(status: .unavailable)
    }
    return (monitor, runtime, shell, worker)
}

@Test func claudeListingParsesRuntimeSessionsWithoutTrustingUnknownEntries() throws {
    let adapters = AttributionAdapters.builtIn
    let sessions = try adapters.runtimeSessions(
        .claude,
        fromRegistry: try listing([
            entry(pid: 10), entry(pid: 11, status: "future-status"), entry(pid: 12, session: "not-a-uuid"),
            ["sessionId": sessionA, "status": "idle"],
        ]))
    #expect(
        sessions == [
            RuntimeSession(runtimePID: 10, sessionID: sessionB, active: true),
            RuntimeSession(runtimePID: 11, sessionID: sessionB, active: false),
            RuntimeSession(runtimePID: 12, sessionID: nil, active: true),
        ])
    #expect(throws: (any Error).self) { try adapters.runtimeSessions(.claude, fromRegistry: Data("no".utf8)) }
    #expect(adapters.sessionRegistry(for: .claude)?.command == ["claude", "agents", "--json"])
    #expect(adapters.sessionRegistry(for: .codex) == nil)
}

@Test func listedSessionBindsTheRuntimeAndMarkerlessDescendantsButNeverOverridesMarkers() throws {
    var (monitor, runtime, shell, worker) = claudeSession()
    #expect(monitor.finding(for: runtime.identity)?.attribution.evidence == .runtimeOnly)
    let findings = monitor.findings()
    #expect(monitor.sessionRegistryRuntimes(in: findings) == [.claude: [runtime.identity]])

    monitor.bindSessions(try listing([entry(pid: 10), entry(pid: 99, session: sessionA)]), provider: .claude)
    for process in [runtime, shell] {
        let row = try #require(monitor.finding(for: process.identity))
        #expect(row.attribution.evidence == .sessionRegistry)
        #expect(row.attribution.threadID == sessionB)
        #expect(row.attribution.provider == .claude)
        #expect(row.attribution.runtime == runtime.identity)
    }
    let marked = try #require(monitor.finding(for: worker.identity))
    #expect(marked.attribution.evidence == .marker)
    #expect(marked.attribution.threadID == sessionA)

    monitor.bindSessions(nil, provider: .claude)
    #expect(monitor.finding(for: runtime.identity)?.attribution.evidence == .runtimeOnly)
}

@Test(arguments: ["duplicate", "inactive", "unlisted", "invalid"])
func listingThatDoesNotNameExactlyOneLiveSessionLeavesTheRuntimeUnbound(case name: String) throws {
    var (monitor, runtime, _, _) = claudeSession()
    let entries: [[String: Any]] =
        switch name {
        case "duplicate": [entry(pid: 10), entry(pid: 10, session: sessionA)]
        case "inactive": [entry(pid: 10, status: "completed")]
        case "unlisted": [entry(pid: 11)]
        default: [entry(pid: 10, session: "not-a-uuid")]
        }
    monitor.bindSessions(try listing(entries), provider: .claude)
    let row = try #require(monitor.finding(for: runtime.identity))
    #expect(row.attribution.evidence == .runtimeOnly)
    #expect(row.attribution.threadID == nil)
}

@Test func bindingBelongsToOneRuntimeLifetime() throws {
    var (monitor, runtime, _, _) = claudeSession()
    monitor.bindSessions(try listing([entry(pid: 10)]), provider: .claude)
    let reused = sample(10, start: 50, executable: claudeExecutable)
    monitor.ingest([reused])
    #expect(monitor.finding(for: reused.identity)?.attribution.evidence == .runtimeOnly)
    #expect(monitor.finding(for: runtime.identity) == nil)
}

@Test func malformedDescendantMetadataStaysAmbiguousDespiteABinding() throws {
    var (monitor, _, shell, _) = claudeSession()
    monitor.bindSessions(try listing([entry(pid: 10)]), provider: .claude)
    monitor.enrich(ProcessMetadata(status: .malformed), for: shell.identity)
    #expect(monitor.finding(for: shell.identity)?.attribution.evidence == .ambiguous)
}

private final class FakeRegistry: SessionRegistryReading, SamplingClock, ProcessReading, Sendable {
    let calls = Mutex(0)
    let times = Mutex<[Double]>([0])
    let fail: Bool
    let runtimes: [Int32]

    init(fail: Bool = false, runtimes: [Int32] = [10]) {
        self.fail = fail
        self.runtimes = runtimes
    }

    func output(of query: SessionRegistryQuery) throws -> Data {
        calls.withLock { $0 += 1 }
        if fail { throw BoundedCommandFailure("Claude Code command failed.") }
        return try listing(runtimes.map { entry(pid: Int($0)) })
    }

    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let count = calls.withLock { $0 }
        let at = times.withLock { times in
            defer { times.append((times.last ?? 0) + 20) }
            return times.last ?? 0
        }
        // A second Claude runtime appears once the first listing has run.
        let extra =
            count > 0 && runtimes.count > 1 ? [sample(11, executable: claudeExecutable, at: at, cpu: at)] : []
        return ProcessSnapshot(
            samples: [sample(10, executable: claudeExecutable, at: at, cpu: at)] + extra,
            enumeratedCount: 2, unreadableCount: 0)
    }

    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        ProcessArguments.parse(argumentBuffer(arguments: ["claude"], environment: []))
    }

    func wait(seconds: Double) async throws {}
    func now() -> Date { Date(timeIntervalSince1970: times.withLock { $0.last ?? 0 }) }
}

@Test func sessionListingRunsOnlyForUnboundRuntimesAndAtMostOncePerMinute() async throws {
    let fake = FakeRegistry()
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(samples: 5), reader: fake, clock: fake, registry: fake)
    let evidence = Mutex<[AttributionEvidence?]>([])
    try await session.run { snapshot in
        evidence.withLock {
            $0.append(snapshot.findings.first { $0.process.pid == 10 }?.attribution.evidence)
        }
    }
    // Samples are 20 s apart: the first and fourth samples list sessions; the others reuse the binding.
    #expect(fake.calls.withLock { $0 } == 2)
    #expect(evidence.withLock { $0 }.allSatisfy { $0 == .sessionRegistry })
}

@Test func newUnboundRuntimeTriggersAnEarlierListing() async throws {
    let fake = FakeRegistry(runtimes: [10, 11])
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(samples: 2), reader: fake, clock: fake, registry: fake)
    try await session.run { _ in }
    #expect(fake.calls.withLock { $0 } == 2)
}

@Test func failedListingKeepsRuntimeUnresolvedWithoutRetryingEverySample() async throws {
    let fake = FakeRegistry(fail: true)
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(samples: 3), reader: fake, clock: fake, registry: fake)
    let evidence = Mutex<[AttributionEvidence?]>([])
    try await session.run { snapshot in
        evidence.withLock { $0.append(snapshot.findings.first?.attribution.evidence) }
    }
    #expect(fake.calls.withLock { $0 } == 1)
    #expect(evidence.withLock { $0 }.allSatisfy { $0 == .runtimeOnly })
}

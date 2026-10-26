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
    let session = "abcdefab-cdef-4abc-8def-abcdefabcdef"
    let adapters = AttributionAdapters.builtIn
    let sessions = try adapters.runtimeSessions(
        .claude,
        fromRegistry: try listing([
            entry(pid: 10, session: session), entry(pid: 11, session: session, status: "future-status"),
            entry(pid: 12, session: "not-a-uuid"),
            ["sessionId": sessionA, "status": "idle"],
        ]))
    #expect(
        sessions == [
            RuntimeSession(runtimePID: 10, sessionID: session, active: true),
            RuntimeSession(runtimePID: 11, sessionID: session, active: false),
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

private final class FakeRegistry: SessionRegistryReading, AcquisitionClock, ProcessReading, Sendable {
    let calls = Mutex(0)
    let listingStarted = ClockGate()
    let reportRead = ClockGate()
    let marked: Bool
    let times = Mutex<[Double]>([0])
    let fail: Bool
    let identityCurrent: Bool
    let runtimes: [Int32]

    init(fail: Bool = false, runtimes: [Int32] = [10], identityCurrent: Bool = true, marked: Bool = false) {
        self.fail = fail
        self.marked = marked
        self.identityCurrent = identityCurrent
        self.runtimes = runtimes
    }

    func output(of query: SessionRegistryQuery) throws -> Data {
        calls.withLock { $0 += 1 }
        listingStarted.signal()
        if fail { throw BoundedCommandFailure("Claude Code command failed.") }
        return try listing(runtimes.map { entry(pid: Int($0)) })
    }

    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let at = monotonicNow()
        // The second runtime arrives at the third scan, independently of resolver progress.
        let extra =
            at >= 40 && runtimes.count > 1 ? [sample(11, executable: claudeExecutable, at: at, cpu: at)] : []
        return ProcessSnapshot(
            samples: [sample(10, executable: marked ? "/usr/bin/node" : claudeExecutable, at: at, cpu: at)]
                + extra,
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

    func isCurrent(_ sample: ProcessSample) -> Bool { identityCurrent }

    func wait(until deadline: Double, wake: AcquisitionWake) throws {
        let seconds = max(0, deadline - monotonicNow())
        if monotonicNow() == 0 {
            if !marked { guard listingStarted.wait(wake: wake) else { return } }
        } else {
            // These integration tests advance after inspecting each report. Backlog has its own
            // ungated fixtures; an instant clock must not race the asynchronous consumer here.
            guard reportRead.wait(wake: wake) else { return }
        }
        times.withLock { $0.append(($0.last ?? 0) + seconds) }
    }
    func monotonicNow() -> Double { times.withLock { $0.last ?? 0 } }
    // Periodic listing is tested with explicit dates in the cadence guard; this integration
    // isolates initial discovery from wall-clock progress while background workers finish.
    func now() -> Date { Date(timeIntervalSince1970: 0) }
}

@Test func sessionListingCadenceIsIndependentOfAccountingScans() {
    var cadence = SessionRegistryCadence()
    let first = Set([ProcessIdentity(pid: 10, startMicroseconds: 1)])
    let decisions = (0...60).map {
        cadence.due(.claude, runtimes: first, at: Date(timeIntervalSince1970: Double($0)))
    }
    #expect(decisions.enumerated().filter(\.element).map(\.offset) == [0, 60])
    let additional = first.union([ProcessIdentity(pid: 11, startMicroseconds: 2)])
    let changed = cadence.due(.claude, runtimes: additional, at: Date(timeIntervalSince1970: 61))
    let unchanged = cadence.due(.claude, runtimes: additional, at: Date(timeIntervalSince1970: 62))
    #expect(changed)
    #expect(!unchanged)
}

@Test func failedListingKeepsRuntimeUnresolvedWithoutRetryingEverySample() async throws {
    let fake = FakeRegistry(fail: true)
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(samples: 3), reader: fake, clock: fake, registry: fake)
    let evidence = Mutex<[AttributionEvidence?]>([])
    try await session.run { snapshot in
        defer { fake.reportRead.signal() }
        evidence.withLock { $0.append(snapshot.findings.first?.attribution.evidence) }
    }
    #expect(fake.calls.withLock { $0 } == 1)
    #expect(evidence.withLock { $0 } == [.runtimeOnly, .runtimeOnly, .runtimeOnly])
}

private enum RegistryTestCompletion: Error { case exactSession }

@Test(.timeLimit(.minutes(1))) func sessionListingAutomaticallyResolvesLaterReports() async throws {
    let fake = FakeRegistry()
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(samples: 0), reader: fake, clock: fake, registry: fake)
    await #expect(throws: RegistryTestCompletion.self) {
        try await session.run { snapshot in
            defer { fake.reportRead.signal() }
            if let row = snapshot.findings.first, row.attribution.evidence == .sessionRegistry {
                #expect(row.attribution.threadID == sessionB)
                #expect(row.attribution.runtime?.pid == 10)
                throw RegistryTestCompletion.exactSession
            }
        }
    }
    #expect(fake.calls.withLock { $0 } == 1)
}

@Test func sessionListingCannotBindAnUnverifiedRuntimeLifetime() async throws {
    let fake = FakeRegistry(identityCurrent: false)
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(samples: 1), reader: fake, clock: fake, registry: fake)
    let findings = Mutex<[HeavyProcess]>([])
    try await session.run { snapshot in
        defer { fake.reportRead.signal() }
        findings.withLock { $0 = snapshot.findings }
    }
    #expect(fake.calls.withLock { $0 } == 1)
    #expect(findings.withLock { $0.first?.attribution.evidence } == .runtimeOnly)
    #expect(findings.withLock { $0.first?.attribution.threadID } == nil)
}

@Test(arguments: [false, true])
func providerDiscoveryDoesNotRecursivelyListItsOwnHelpers(nested: Bool) throws {
    let ownPID: Int32 = 8000
    let launcher = sample(9, parent: ownPID)
    let helper = sample(10, parent: nested ? launcher.identity.pid : ownPID, executable: claudeExecutable)
    let runtime = sample(20, parent: 1, executable: claudeExecutable)
    var monitor = Monitor()
    monitor.ingest([launcher, helper, runtime])
    if nested { monitor.ingest([helper, runtime]) }
    let findings = monitor.findings(scope: .allProcesses)
    #expect(findings.contains { $0.process == helper.identity })
    #expect(
        monitor.sessionRegistryRuntimes(in: findings, excludingChildrenOf: ownPID) == [
            .claude: [runtime.identity]
        ])
}

@Test func markerResolvedWorkersDoNotStartProviderListing() async throws {
    let fake = FakeRegistry(marked: true)
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(samples: 3),
        reader: fake, clock: fake, registry: fake)
    let sessions = Mutex<[String?]>([])
    try await session.run { snapshot in
        defer { fake.reportRead.signal() }
        sessions.withLock { $0.append(snapshot.findings.first?.attribution.threadID) }
    }
    #expect(fake.calls.withLock { $0 } == 0)
    #expect(sessions.withLock { $0 } == [sessionA, sessionA, sessionA])
}

@Test func delayedRegistryCannotRebindAcrossDetectedExecButOtherRuntimesStillRefresh() throws {
    var runtime = sample(10, executable: claudeExecutable, at: 0)
    runtime.kernelPeakFootprintBytes = 100
    var other = sample(20, executable: claudeExecutable, at: 0)
    var monitor = Monitor()
    monitor.ingest([runtime, other])
    monitor.bindSessions(
        try listing([entry(pid: 10, session: sessionA), entry(pid: 20, session: sessionA)]),
        provider: .claude, observedAt: 0)
    runtime.sampledAt = 3
    runtime.kernelPeakFootprintBytes = 20
    other.sampledAt = 3
    monitor.ingest([runtime, other])
    #expect(monitor.finding(for: runtime.identity)?.attribution.threadID == nil)
    monitor.bindSessions(
        try listing([entry(pid: 10, session: sessionA), entry(pid: 20, session: sessionB)]),
        provider: .claude, observedAt: 4, requestedAt: [runtime.identity: 0, other.identity: 0])
    #expect(monitor.finding(for: runtime.identity)?.attribution.threadID == nil)
    #expect(monitor.finding(for: other.identity)?.attribution.threadID == sessionB)
    monitor.bindSessions(
        try listing([entry(pid: 10, session: sessionB), entry(pid: 20, session: sessionB)]),
        provider: .claude, observedAt: 5, requestedAt: [runtime.identity: 3, other.identity: 3])
    #expect(monitor.finding(for: runtime.identity)?.attribution.threadID == sessionB)
}

@Test func listedNamesFollowVerifiedSessionIdentityAndClearWithTheBinding() throws {
    var (monitor, runtime, shell, worker) = claudeSession()
    var named = entry(pid: 10)
    named["name"] = "Build the search index"
    monitor.bindSessions(try listing([named]), provider: .claude)
    #expect(monitor.finding(for: runtime.identity)?.sessionName == "Build the search index")
    #expect(monitor.finding(for: shell.identity)?.sessionName == "Build the search index")
    #expect(monitor.finding(for: worker.identity)?.sessionName == nil)
    let owner = monitor.finding(for: shell.identity)?.attribution
    named["name"] = "Index maintenance"
    monitor.bindSessions(try listing([named]), provider: .claude)
    #expect(monitor.finding(for: shell.identity)?.sessionName == "Index maintenance")
    #expect(monitor.finding(for: shell.identity)?.attribution == owner)
    monitor.bindSessions(nil, provider: .claude)
    #expect(monitor.finding(for: shell.identity)?.sessionName == nil)
    monitor.bindSessions(try listing([named, named]), provider: .claude)
    #expect(monitor.finding(for: runtime.identity)?.sessionName == nil)
    monitor.bindSessions(try listing([named]), provider: .claude, restrictingTo: [])
    #expect(monitor.finding(for: runtime.identity)?.sessionName == nil)
    monitor.bindSessions(try listing([named]), provider: .claude)
    var executed = runtime
    executed.executable = "/usr/bin/node"
    monitor.ingest([executed, shell, worker])
    #expect(monitor.finding(for: runtime.identity)?.sessionName == nil)
}

@Test func invalidOptionalNamesDoNotInvalidateSessionOwnership() throws {
    for name: Any in [17, "", "\nmisleading", String(repeating: "x", count: 161)] {
        var (monitor, runtime, _, _) = claudeSession()
        var named = entry(pid: 10)
        named["name"] = name
        monitor.bindSessions(try listing([named]), provider: .claude)
        let row = try #require(monitor.finding(for: runtime.identity))
        #expect(row.attribution.threadID == sessionB)
        #expect(row.sessionName == nil)
    }
}

@Test func registryProfileCountsInvocationEvidenceAndOnlyMatchedBindings() throws {
    let profile = PipelineProfile()
    var monitor = Monitor(profile: profile)
    let runtime = sample(10, executable: claudeExecutable)
    let provisional = sample(11, executable: claudeExecutable)
    monitor.ingest([runtime, provisional])
    monitor.enrich(ProcessMetadata(invocation: "claude"), for: runtime.identity)
    monitor.profileRegistryCandidates([runtime.identity, provisional.identity])
    monitor.bindSessions(try listing([entry(pid: 10)]), provider: .claude)
    let counters = profile.snapshot().counters
    #expect(counters["registryCandidatesWithInvocation"] == 1)
    #expect(counters["registryCandidatesWithoutInvocation"] == 1)
    #expect(counters["registryMatchedBindings"] == 1)
    monitor.bindSessions(try listing([entry(pid: 10), entry(pid: 10)]), provider: .claude)
    #expect(profile.snapshot().counters["registryMatchedBindings"] == 1)
}

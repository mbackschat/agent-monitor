import Foundation
import Testing

@testable import AgentMonitorCore

@Test func agentScopeHidesUnrelatedWorkButKeepsUnresolvedAndConflictingAgentEvidence() {
    let codex = sample(10, executable: "/bin/codex")
    let unresolved = sample(20, parent: 10)
    let conflicting = sample(30, parent: 10)
    let detached = sample(40)
    var monitor = Monitor()
    monitor.ingest([codex, unresolved, conflicting, detached, sample(50), sample(60, memory: 1)])
    monitor.enrich(ProcessMetadata(writerThreadIDs: [sessionA, sessionB]), for: codex.identity)
    monitor.enrich(
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .claude)]),
        for: conflicting.identity)
    monitor.enrich(
        ProcessMetadata(markers: [SessionMarker(threadID: sessionB, provider: .codex)]),
        for: detached.identity)
    let agents = monitor.findings(scope: .agentsOnly)
    #expect(Set(agents.map { $0.process.pid }) == [10, 20, 30, 40])
    #expect(agents.first { $0.process.pid == 30 }?.attribution.provider == nil)
    #expect(agents.first { $0.process.pid == 20 }?.attribution.evidence == .ambiguous)
    #expect(Set(monitor.findings(scope: .allProcesses).map { $0.process.pid }) == [10, 20, 30, 40, 50])
}

let sessionA = "11111111-1111-4111-8111-111111111111"
let sessionB = "22222222-2222-4222-8222-222222222222"

func sample(
    _ pid: Int32, parent: Int32 = 1, start: UInt64? = nil,
    executable: String = "/usr/bin/worker", terminal: String? = nil,
    at: Double = 1, cpu: Double? = 0, memory: UInt64? = 2_000_000_000
) -> ProcessSample {
    ProcessSample(
        identity: ProcessIdentity(pid: pid, startMicroseconds: start ?? UInt64(pid)),
        parentPID: parent, executable: executable, name: "worker", terminal: terminal,
        sampledAt: at, cpuSeconds: cpu, footprintBytes: memory
    )
}

@Test func heavyWorkersInSameDirectoryResolveToDifferentSessions() throws {
    let a = sample(20)
    let b = sample(30)
    var monitor = Monitor()
    monitor.ingest([a, b, sample(40, memory: 1)])
    monitor.enrich(
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)], cwd: "/same"),
        for: a.identity)
    monitor.enrich(
        ProcessMetadata(markers: [SessionMarker(threadID: sessionB, provider: .codex)], cwd: "/same"),
        for: b.identity)
    let rows = monitor.findings()
    #expect(rows.count == 2)
    #expect(rows.first { $0.process == a.identity }?.attribution.threadID == sessionA)
    #expect(rows.first { $0.process == b.identity }?.attribution.threadID == sessionB)
}

@Test func lineageSurvivesParentExitAndUnavailableMetadata() throws {
    let parent = sample(10, memory: 1)
    var child = sample(20, parent: 10)
    var monitor = Monitor()
    monitor.ingest([parent, child])
    monitor.enrich(
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]), for: parent.identity)
    child.parentPID = 1
    monitor.ingest([child])
    monitor.enrich(ProcessMetadata(status: .unavailable), for: parent.identity)
    let row = try #require(monitor.findings().first)
    #expect(row.attribution.threadID == sessionA)
    #expect(row.attribution.evidence == .inheritedMarker)
}

@Test func reusedPIDDoesNotInheritEvidenceOrCPU() throws {
    let old = sample(20)
    var monitor = Monitor()
    monitor.ingest([old])
    monitor.enrich(
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]), for: old.identity)
    monitor.ingest([sample(20, start: 200, at: 2, cpu: 500)])
    let row = try #require(monitor.findings().first)
    #expect(row.attribution.threadID == nil)
    #expect(row.cpuPercent == nil)
}

@Test func newerParentPIDCannotExplainOlderChild() throws {
    let parent = sample(10, start: 100, memory: 1)
    let child = sample(20, parent: 10, start: 50)
    var monitor = Monitor()
    monitor.ingest([parent, child])
    monitor.enrich(
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]), for: parent.identity)
    #expect(try #require(monitor.findings().first).attribution.threadID == nil)
}

@Test func nestedCodexRuntimeDoesNotBorrowOuterSession() throws {
    let outer = sample(10, executable: "/opt/bin/codex", terminal: "ttys001", memory: 1)
    let nested = sample(20, parent: 10, executable: "/opt/bin/codex", memory: 1)
    let worker = sample(30, parent: 20)
    var monitor = Monitor()
    monitor.ingest([outer, nested, worker])
    monitor.enrich(ProcessMetadata(writerThreadIDs: [sessionA]), for: outer.identity)
    monitor.enrich(
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]), for: nested.identity)
    let result = try #require(monitor.findings().first)
    #expect(result.attribution.runtime == nested.identity)
    #expect(result.attribution.threadID == nil)
}

@Test(arguments: [1, 2]) func runtimeLockEvidenceNeverGuessesAmongThreads(count: Int) throws {
    let runtime = sample(10, executable: "/opt/bin/codex", terminal: "ttys002", memory: 1)
    let worker = sample(20, parent: 10)
    var monitor = Monitor()
    monitor.ingest([runtime, worker])
    monitor.enrich(
        ProcessMetadata(writerThreadIDs: Array([sessionA, sessionB].prefix(count))), for: runtime.identity)
    let result = try #require(monitor.findings().first)
    #expect(result.attribution.terminal == "ttys002")
    #expect(result.attribution.threadID == (count == 1 ? sessionA : nil))
    #expect(result.attribution.evidence == (count == 1 ? .writerLock : .ambiguous))
}

@Test func childThreadOverridesAncestorButKeepsRootSession() throws {
    let parent = sample(10, memory: 1)
    let child = sample(20, parent: 10)
    var monitor = Monitor()
    monitor.ingest([parent, child])
    monitor.enrich(
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]), for: parent.identity)
    monitor.enrich(
        ProcessMetadata(markers: [
            SessionMarker(threadID: sessionB, rootSessionID: sessionA, provider: .codex)
        ]),
        for: child.identity)
    let result = try #require(monitor.findings().first)
    #expect(result.attribution.threadID == sessionB)
    #expect(result.attribution.rootSessionID == sessionA)
}

@Test func cpuUsesIntervalDeltaAndStrictThreshold() throws {
    var monitor = Monitor()
    monitor.ingest([sample(20, cpu: 3, memory: nil)])
    #expect(monitor.findings().isEmpty)
    monitor.ingest([sample(20, at: 3, cpu: 4, memory: nil)])
    let row = try #require(monitor.findings().first)
    #expect(row.cpuPercent == 50)
    #expect(row.footprintBytes == nil)
    #expect(monitor.findings(thresholds: Thresholds(cpuPercent: 50)).isEmpty)
}

@Test func machTicksConvertToSecondsOnAppleSilicon() {
    #expect(ResourceMath.seconds(ticks: 24_000_000, numerator: 125, denominator: 3) == 1)
}

@Test func claudeNativeRuntimeAndDescendantMarkerIdentifyExactSession() throws {
    let runtime = sample(
        10, executable: "/Users/test/.local/share/claude/versions/2.1.296", terminal: "ttys016", memory: 1)
    let worker = sample(20, parent: 10)
    var monitor = Monitor()
    monitor.ingest([runtime, worker])
    monitor.enrich(
        ProcessArguments.parse(argumentBuffer(environment: ["CLAUDE_CODE_SESSION_ID=\(sessionA)"])),
        for: worker.identity)
    let row = try #require(monitor.findings().first)
    #expect(row.attribution.provider == .claude)
    #expect(row.attribution.threadID == sessionA)
    #expect(row.attribution.runtime == runtime.identity)
    #expect(row.attribution.terminal == "ttys016")
}

@Test func conflictingProviderAndRuntimeEvidenceRemainsAmbiguous() throws {
    let runtime = sample(10, executable: "/usr/local/bin/claude", memory: 1)
    let worker = sample(20, parent: 10)
    var monitor = Monitor()
    monitor.ingest([runtime, worker])
    monitor.enrich(
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]), for: worker.identity)
    let row = try #require(monitor.findings().first)
    #expect(row.attribution.evidence == .ambiguous)
    #expect(row.attribution.threadID == nil)
}

@Test func malformedOwnMarkersCannotFallBackToAnotherSession() throws {
    let runtime = sample(10, executable: "/usr/local/bin/codex", memory: 1)
    let worker = sample(20, parent: 10)
    var monitor = Monitor()
    monitor.ingest([runtime, worker])
    monitor.enrich(ProcessMetadata(writerThreadIDs: [sessionA]), for: runtime.identity)
    monitor.enrich(ProcessMetadata(status: .malformed), for: worker.identity)
    let row = try #require(monitor.findings().first)
    #expect(row.attribution.evidence == .ambiguous)
    #expect(row.attribution.threadID == nil)
}

@Test func changedExecutableInvalidatesCachedMarkers() throws {
    var worker = sample(20)
    var monitor = Monitor()
    monitor.ingest([worker])
    monitor.enrich(
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]), for: worker.identity)
    worker.executable = "/different/program"
    monitor.ingest([worker])
    #expect(try #require(monitor.findings().first).attribution.threadID == nil)
}

@Test func readableOwnMarkerDoesNotDependOnParentEnvironmentCoverage() throws {
    let parent = sample(10, memory: 1)
    let worker = sample(20, parent: 10)
    var monitor = Monitor()
    monitor.ingest([parent, worker])
    monitor.enrich(ProcessMetadata(status: .malformed), for: parent.identity)
    monitor.enrich(
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]), for: worker.identity)
    let row = try #require(monitor.findings().first)
    #expect(row.attribution.threadID == sessionA)
    #expect(row.attribution.evidence == .marker)
}

@Test func terminalPresentationIsResolvedOnlyDuringEnrichment() throws {
    var runtime = sample(10, executable: "/usr/local/bin/codex", memory: 1)
    runtime.terminalDevice = 123
    let worker = sample(20, parent: 10)
    var monitor = Monitor()
    monitor.ingest([runtime, worker])
    monitor.enrich(ProcessMetadata(terminal: "ttys016", writerThreadIDs: [sessionA]), for: runtime.identity)
    let row = try #require(monitor.findings().first)
    #expect(row.attribution.context == .terminal)
    #expect(row.attribution.terminal == "ttys016")
}

@Test func attributingMarkerExposesClaudeInboxOnlyOutsideSnapshots() throws {
    let socket = "/tmp/cc-socks/10.sock"
    let runtime = sample(10, executable: "/Users/test/.local/share/claude/versions/2.1.300", memory: 1)
    let shell = sample(20, parent: 10, memory: 1)
    let worker = sample(30, parent: 20)
    var monitor = Monitor()
    monitor.ingest([runtime, shell, worker])
    monitor.enrich(
        ProcessArguments.parse(
            argumentBuffer(environment: [
                "CLAUDE_CODE_SESSION_ID=\(sessionA)", "CLAUDE_CODE_MESSAGING_SOCKET=\(socket)",
            ])), for: shell.identity)
    #expect(monitor.attributingMarker(for: worker.identity)?.inboxSocket == socket)
    #expect(monitor.attributingMarker(for: runtime.identity) == nil)
    let json = try JSONEncoder().encode(monitor.findings())
    #expect(!String(decoding: json, as: UTF8.self).contains("cc-socks"))
}

@Test func unresolvedAttributionHasNoAttributingMarker() {
    let runtime = sample(10, executable: "/usr/local/bin/claude", memory: 1)
    let worker = sample(20, parent: 10)
    var monitor = Monitor()
    monitor.ingest([runtime, worker])
    monitor.enrich(
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]), for: worker.identity)
    #expect(monitor.attributingMarker(for: worker.identity) == nil)
}

// A shell that exits after starting a background job reparents the job to launchd; its marker
// still names the inbox of the runtime that launched it.
@Test func detachedClaudeWorkloadRejoinsTheRuntimeOwningItsInbox() throws {
    let inbox = "/tmp/cc-socks/10.sock"
    let runtime = sample(10, executable: "/usr/local/bin/claude", terminal: "ttys010", memory: 1)
    let other = sample(15, executable: "/usr/local/bin/claude", terminal: "ttys011", memory: 1)
    let workload = sample(20)
    var monitor = Monitor()
    monitor.ingest([runtime, other, workload])
    monitor.enrich(
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .claude, inboxSocket: inbox)]),
        for: workload.identity)
    #expect(Set(monitor.enrichmentTargets().map(\.identity.pid)) == [10, 15, 20])
    monitor.enrich(ProcessMetadata(listeningSockets: [inbox]), for: runtime.identity)
    monitor.enrich(ProcessMetadata(listeningSockets: ["/tmp/cc-socks/15.sock"]), for: other.identity)
    let row = try #require(monitor.finding(for: workload.identity))
    #expect(row.attribution.runtime == runtime.identity)
    #expect(row.attribution.context == .terminal)
    #expect(row.attribution.terminal == "ttys010")
    #expect(row.attribution.threadID == sessionA)
    #expect(row.attribution.evidence == .marker)
}

@Test(arguments: ["later runtime", "not listening", "two owners", "codex marker"])
func detachedWorkloadDoesNotGuessItsRuntime(case name: String) throws {
    let inbox = "/tmp/cc-socks/10.sock"
    // A runtime started after the workload reuses a PID and therefore a socket name.
    let runtime = sample(
        10, start: name == "later runtime" ? 30 : 10, executable: "/usr/local/bin/claude",
        terminal: "ttys010", memory: 1)
    let twin = sample(15, executable: "/usr/local/bin/claude", memory: 1)
    let workload = sample(20)
    var monitor = Monitor()
    monitor.ingest([runtime, twin, workload])
    monitor.enrich(
        ProcessMetadata(
            markers: [
                SessionMarker(
                    threadID: sessionA, provider: name == "codex marker" ? .codex : .claude,
                    inboxSocket: inbox)
            ]),
        for: workload.identity)
    monitor.enrich(
        ProcessMetadata(listeningSockets: name == "not listening" ? [] : [inbox]), for: runtime.identity)
    monitor.enrich(ProcessMetadata(listeningSockets: name == "two owners" ? [inbox] : []), for: twin.identity)
    let row = try #require(monitor.finding(for: workload.identity))
    #expect(row.attribution.runtime == nil)
    #expect(row.attribution.context == .unverified)
}

@Test func runtimeAncestorNeedsNoInboxCandidates() {
    let runtime = sample(10, executable: "/usr/local/bin/claude", memory: 1)
    let other = sample(15, executable: "/usr/local/bin/claude", memory: 1)
    let workload = sample(20, parent: 10)
    var monitor = Monitor()
    monitor.ingest([runtime, other, workload])
    monitor.enrich(
        ProcessMetadata(
            markers: [
                SessionMarker(threadID: sessionA, provider: .claude, inboxSocket: "/tmp/cc-socks/10.sock")
            ]),
        for: workload.identity)
    #expect(Set(monitor.enrichmentTargets().map(\.identity.pid)) == [10, 20])
}

// Codex → claude → worker and Claude → codex → worker both leave both markers in the worker's
// environment; the inner agent is the nearest runtime, and it set its own marker last.
@Test(arguments: [
    ("/usr/local/bin/claude", AgentProvider.claude, sessionA), ("/opt/homebrew/bin/codex", .codex, sessionB),
])
func nestedAgentWorkloadBelongsToTheNearestRuntime(inner: String, provider: AgentProvider, session: String)
    throws
{
    let outer = sample(
        5, executable: inner.hasSuffix("codex") ? "/usr/local/bin/claude" : "/opt/homebrew/bin/codex",
        memory: 1)
    let runtime = sample(10, parent: 5, executable: inner, terminal: "ttys010", memory: 1)
    let worker = sample(20, parent: 10)
    var monitor = Monitor()
    monitor.ingest([outer, runtime, worker])
    monitor.enrich(
        ProcessArguments.parse(
            argumentBuffer(environment: ["CLAUDE_CODE_SESSION_ID=\(sessionA)", "CODEX_THREAD_ID=\(sessionB)"])
        ),
        for: worker.identity)
    let row = try #require(monitor.finding(for: worker.identity))
    #expect(row.attribution.provider == provider)
    #expect(row.attribution.threadID == session)
    #expect(row.attribution.runtime == runtime.identity)
    #expect(row.attribution.evidence == .marker)
}

@Test func detachedWorkloadWithNestedMarkersStaysAmbiguous() throws {
    let worker = sample(20)
    var monitor = Monitor()
    monitor.ingest([worker])
    monitor.enrich(
        ProcessArguments.parse(
            argumentBuffer(environment: ["CLAUDE_CODE_SESSION_ID=\(sessionA)", "CODEX_THREAD_ID=\(sessionB)"])
        ),
        for: worker.identity)
    let row = try #require(monitor.finding(for: worker.identity))
    #expect(row.attribution.evidence == .ambiguous)
    #expect(row.attribution.threadID == nil)
    #expect(row.attribution.provider == nil)
}

// One call reads the workload and then the runtimes its marker points to; sampling and actions
// share it so they cannot attribute differently.
@Test func enrichmentReadsDetachedInboxRuntimesInOneCall() throws {
    let inbox = "/tmp/cc-socks/10.sock"
    let runtime = sample(10, executable: "/usr/local/bin/claude", terminal: "ttys010", memory: 1)
    let workload = sample(20)
    var monitor = Monitor()
    monitor.ingest([runtime, workload])
    var reads: [Int32] = []
    monitor.enrich(for: [workload.identity]) { target in
        reads.append(target.identity.pid)
        return target.identity == workload.identity
            ? ProcessMetadata(markers: [
                SessionMarker(threadID: sessionA, provider: .claude, inboxSocket: inbox)
            ])
            : ProcessMetadata(listeningSockets: [inbox])
    }
    #expect(reads == [20, 10])
    #expect(monitor.finding(for: workload.identity)?.attribution.runtime == runtime.identity)
}

@Test(arguments: [false, true])
func detachedCodexWorkloadRejoinsItsExactThreadWriter(inherited: Bool) throws {
    let runtime = sample(10, executable: "/opt/bin/codex", terminal: "ttys010", memory: 1)
    let other = sample(15, executable: "/opt/bin/codex", terminal: "ttys011", memory: 1)
    let marked = sample(20, memory: 1)
    let workload = inherited ? sample(30, parent: 20) : marked
    var monitor = Monitor()
    monitor.ingest(inherited ? [runtime, other, marked, workload] : [runtime, other, workload])
    var reads: [ProcessIdentity] = []
    monitor.enrich(for: [workload.identity]) { target in
        reads.append(target.identity)
        return switch target.identity {
        case marked.identity:
            ProcessMetadata(
                markers: [SessionMarker(threadID: sessionB, rootSessionID: sessionA, provider: .codex)],
                cwd: "/same")
        case runtime.identity:
            ProcessMetadata(cwd: "/same", writerThreadIDs: [sessionA, sessionB])
        case other.identity:
            ProcessMetadata(cwd: "/same", writerThreadIDs: [sessionA])
        default: ProcessMetadata(status: .unavailable)
        }
    }
    let row = try #require(monitor.finding(for: workload.identity))
    #expect(row.attribution.runtime == runtime.identity)
    #expect(row.attribution.terminal == "ttys010")
    #expect(row.attribution.context == .terminal)
    #expect(row.attribution.threadID == sessionB)
    #expect(row.attribution.rootSessionID == sessionA)
    #expect(row.attribution.evidence == (inherited ? .inheritedMarker : .marker))
    #expect(Set(reads) == Set([runtime, other, marked, workload].map(\.identity)))
    #expect(reads.count == Set(reads).count)
}

enum DetachedCodexMismatch: CaseIterable {
    case laterRuntime, rootOnly, duplicateWriters, wrongProvider, missingLock
}

@Test(arguments: DetachedCodexMismatch.allCases)
func detachedCodexWorkloadRequiresOneExistingExactThreadWriter(mismatch: DetachedCodexMismatch) throws {
    let runtime = sample(
        10, start: mismatch == .laterRuntime ? 25 : 10,
        executable: mismatch == .wrongProvider ? "/opt/bin/claude" : "/opt/bin/codex", memory: 1)
    let other = sample(15, executable: "/opt/bin/codex", memory: 1)
    let marked = sample(20, memory: 1)
    let workload = sample(30, parent: 20)
    var monitor = Monitor()
    monitor.ingest([runtime, other, marked, workload])
    monitor.enrich(
        ProcessMetadata(markers: [
            SessionMarker(threadID: sessionB, rootSessionID: sessionA, provider: .codex)
        ]),
        for: marked.identity)
    let locks: [String]
    switch mismatch {
    case .missingLock: locks = []
    case .rootOnly: locks = [sessionA]
    default: locks = [sessionB]
    }
    monitor.enrich(ProcessMetadata(writerThreadIDs: locks), for: runtime.identity)
    monitor.enrich(
        ProcessMetadata(writerThreadIDs: mismatch == .duplicateWriters ? [sessionB] : []), for: other.identity
    )
    let row = try #require(monitor.finding(for: workload.identity))
    #expect(row.attribution.runtime == nil)
    #expect(row.attribution.context == .unverified)
    #expect(row.attribution.threadID == sessionB)
    #expect(row.attribution.evidence == .inheritedMarker)
}

@Test func detachedRuntimeCandidatesAreRefreshedEvenAfterAMatch() throws {
    let runtime = sample(10, executable: "/opt/bin/codex", memory: 1)
    let other = sample(15, executable: "/opt/bin/codex", memory: 1)
    let workload = sample(20)
    var monitor = Monitor()
    monitor.ingest([runtime, other, workload])
    let marker = ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)])
    monitor.enrich(for: [workload.identity]) { target in
        switch target.identity {
        case workload.identity: marker
        case runtime.identity: ProcessMetadata(writerThreadIDs: [sessionA])
        default: ProcessMetadata()
        }
    }
    #expect(monitor.finding(for: workload.identity)?.attribution.runtime == runtime.identity)
    var reads: Set<ProcessIdentity> = []
    monitor.enrich(for: [workload.identity]) { target in
        reads.insert(target.identity)
        return target.identity == workload.identity ? marker : ProcessMetadata(writerThreadIDs: [sessionA])
    }
    #expect(reads == Set([runtime, other, workload].map(\.identity)))
    #expect(monitor.finding(for: workload.identity)?.attribution.runtime == nil)
}

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
        ProcessMetadata(marker: SessionMarker(threadID: sessionA, provider: .claude)),
        for: conflicting.identity)
    monitor.enrich(ProcessMetadata(marker: SessionMarker(threadID: sessionB)), for: detached.identity)
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
    monitor.enrich(ProcessMetadata(marker: SessionMarker(threadID: sessionA), cwd: "/same"), for: a.identity)
    monitor.enrich(ProcessMetadata(marker: SessionMarker(threadID: sessionB), cwd: "/same"), for: b.identity)
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
    monitor.enrich(ProcessMetadata(marker: SessionMarker(threadID: sessionA)), for: parent.identity)
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
    monitor.enrich(ProcessMetadata(marker: SessionMarker(threadID: sessionA)), for: old.identity)
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
    monitor.enrich(ProcessMetadata(marker: SessionMarker(threadID: sessionA)), for: parent.identity)
    #expect(try #require(monitor.findings().first).attribution.threadID == nil)
}

@Test func nestedCodexRuntimeDoesNotBorrowOuterSession() throws {
    let outer = sample(10, executable: "/opt/bin/codex", terminal: "ttys001", memory: 1)
    let nested = sample(20, parent: 10, executable: "/opt/bin/codex", memory: 1)
    let worker = sample(30, parent: 20)
    var monitor = Monitor()
    monitor.ingest([outer, nested, worker])
    monitor.enrich(ProcessMetadata(writerThreadIDs: [sessionA]), for: outer.identity)
    monitor.enrich(ProcessMetadata(marker: SessionMarker(threadID: sessionA)), for: nested.identity)
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
    monitor.enrich(ProcessMetadata(marker: SessionMarker(threadID: sessionA)), for: parent.identity)
    monitor.enrich(
        ProcessMetadata(marker: SessionMarker(threadID: sessionB, rootSessionID: sessionA)),
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
    monitor.enrich(ProcessMetadata(marker: SessionMarker(threadID: sessionA)), for: worker.identity)
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
    monitor.enrich(ProcessMetadata(marker: SessionMarker(threadID: sessionA)), for: worker.identity)
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
    monitor.enrich(ProcessMetadata(marker: SessionMarker(threadID: sessionA)), for: worker.identity)
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

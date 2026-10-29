import Foundation
import Testing

@testable import AgentMonitorCore

private func sharesAncestry(_ left: HeavyProcess, _ right: HeavyProcess) -> Bool {
    left.attribution.ancestry.withUnsafeBufferPointer { a in
        right.attribution.ancestry.withUnsafeBufferPointer { b in a.baseAddress == b.baseAddress }
    }
}

@Test func unchangedAttributionReusesContextWhileCountersMemoryAndEvidenceAdvance() throws {
    var monitor = Monitor()
    let parent = sample(10)
    var worker = sample(20, parent: 10)
    monitor.ingest([parent, worker])
    let marker = ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)])
    monitor.enrich(marker, for: parent.identity, observedAt: 1)
    let initial = try #require(monitor.accountingFindings().first { $0.process == worker.identity })
    worker.sampledAt = 2
    worker.cpuSeconds = 0.5
    worker.footprintBytes = 123
    monitor.ingest([parent, worker, sample(99)])
    monitor.enrich(marker, for: parent.identity, observedAt: 2)
    let current = try #require(monitor.accountingFindings().first { $0.process == worker.identity })
    #expect(sharesAncestry(initial, current))
    #expect(current.cpuPercent == 50)
    #expect(current.footprintBytes == 123)
    #expect(monitor.attributionObservationTimes()[worker.identity] == 2)
    #expect(current.attribution.threadID == sessionA)
    var copy = monitor
    copy.enrich(
        ProcessMetadata(markers: [SessionMarker(threadID: sessionB, provider: .codex)]), for: parent.identity)
    #expect(
        copy.accountingFindings().first { $0.process == worker.identity }?.attribution.threadID == sessionB)
    #expect(monitor.finding(for: worker.identity)?.attribution.threadID == sessionA)
}

@Test func cachedAttributionMatchesUncachedResolutionAcrossGraphAndRuntimeChanges() throws {
    var cached = Monitor()
    var oracle = Monitor()
    func verify() {
        let rows = cached.accountingFindings(sorted: true)
        #expect(rows == oracle.findings())
        #expect(cached.attributionObservationTimes(for: rows) == oracle.attributionObservationTimes())
    }
    func ingest(_ samples: [ProcessSample]) {
        cached.ingest(samples)
        oracle.ingest(samples)
        verify()
    }
    func enrich(_ identity: ProcessIdentity, _ metadata: ProcessMetadata, at: Double = 1) {
        cached.enrich(metadata, for: identity, observedAt: at)
        oracle.enrich(metadata, for: identity, observedAt: at)
        verify()
    }
    var runtime = sample(10, executable: "/usr/local/bin/claude", terminal: "ttys010")
    var parent = sample(20, parent: 10)
    var worker = sample(30, parent: 20)
    let other = sample(15, executable: "/usr/local/bin/claude")
    let inbox = "/fake/inbox"
    ingest([runtime, parent, worker])
    enrich(parent.identity, ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .claude)]))
    #expect(cached.finding(for: worker.identity)?.attribution.threadID == sessionA)
    enrich(
        parent.identity, ProcessMetadata(markers: [SessionMarker(threadID: sessionB, provider: .claude)]),
        at: 2)
    ingest([runtime, worker])
    enrich(parent.identity, ProcessMetadata(status: .malformed), at: 3)
    parent = sample(20, parent: 10, start: 200, at: 4)
    ingest([runtime, parent, worker])
    worker = sample(30, parent: 1, start: 300, at: 5)
    ingest([runtime, parent, worker])
    enrich(
        worker.identity,
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .claude, inboxSocket: inbox)]),
        at: 5)
    enrich(runtime.identity, ProcessMetadata(listeningSockets: [inbox]), at: 5)
    #expect(cached.finding(for: worker.identity)?.attribution.runtime == runtime.identity)
    ingest([runtime, other, worker])
    enrich(other.identity, ProcessMetadata(listeningSockets: [inbox]), at: 6)
    #expect(cached.finding(for: worker.identity)?.attribution.runtime == nil)
    ingest([runtime, worker])
    runtime.terminal = nil
    runtime.terminalDevice = 5
    ingest([runtime, worker])
    runtime.terminalDevice = nil
    ingest([runtime, worker])
    enrich(
        worker.identity,
        ProcessMetadata(markers: [
            SessionMarker(threadID: sessionA, provider: .claude, inboxSocket: "/fake/new-inbox")
        ]), at: 7)
    enrich(runtime.identity, ProcessMetadata(listeningSockets: ["/fake/new-inbox"]), at: 7)
    runtime.kernelPeakFootprintBytes = 100
    ingest([runtime, worker])
    runtime.kernelPeakFootprintBytes = 10
    runtime.sampledAt = 8
    ingest([runtime, worker])
    #expect(cached.finding(for: worker.identity)?.attribution.runtime == nil)
    runtime.executable = "/bin/codex"
    ingest([runtime, worker])
    enrich(runtime.identity, ProcessMetadata(writerThreadIDs: [sessionA]), at: 8)
    worker.parentPID = 10
    ingest([runtime, worker])
    enrich(runtime.identity, ProcessMetadata(invocation: "not-an-agent"), at: 9)
    ingest([worker])
}

@Test func cachedRegistryBindingsRefreshAndDisappearWithoutReusingOldEvidence() throws {
    var cached = Monitor()
    var oracle = Monitor()
    let runtime = sample(10, executable: "/usr/local/bin/claude")
    let worker = sample(20, parent: 10)
    cached.ingest([runtime, worker])
    oracle.ingest([runtime, worker])
    for (index, session) in [sessionA, sessionA, sessionB].enumerated() {
        let data = try JSONSerialization.data(withJSONObject: [
            ["pid": 10, "sessionId": session, "status": "busy", "kind": "interactive"]
        ])
        cached.bindSessions(data, provider: .claude, observedAt: Double(index + 1))
        oracle.bindSessions(data, provider: .claude, observedAt: Double(index + 1))
        #expect(cached.accountingFindings(sorted: true) == oracle.findings())
        #expect(cached.attributionObservationTimes()[worker.identity] == Double(index + 1))
    }
    cached.ingest([worker])
    oracle.ingest([worker])
    #expect(cached.accountingFindings(sorted: true) == oracle.findings())
    #expect(cached.finding(for: worker.identity)?.attribution.evidence == .runtimeOnly)
}

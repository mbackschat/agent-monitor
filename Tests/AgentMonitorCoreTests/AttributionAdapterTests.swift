import Foundation
import Testing

@testable import AgentMonitorCore

private struct FixtureAttributionAdapter: AgentAttributionAdapter {
    let provider: AgentProvider
    var environmentKeys: Set<String> { ["FIXTURE_SESSION"] }
    var runtimeObservations: Set<RuntimeObservation> { [.openFilePaths] }

    func recognizesRuntime(_ executable: String) -> Bool { executable == "/fixture/agent" }

    func marker(in environment: [String: Set<String>]) throws -> SessionMarker? {
        #expect(Set(environment.keys).isSubset(of: environmentKeys))
        return try MarkerEnvironment.uuid("FIXTURE_SESSION", in: environment).map {
            SessionMarker(threadID: $0, provider: provider)
        }
    }

    func runtimeEvidence(from observations: RuntimeObservations) -> RuntimeEvidence {
        RuntimeEvidence(writerThreadIDs: observations.openFilePaths == ["fixture-writer"] ? [sessionA] : [])
    }

    func runtimeLink(for marker: SessionMarker) -> RuntimeLink? { .writerThread(marker.threadID) }
    func isSharedRuntime(_ attribution: Attribution) -> Bool { false }
}

@Test func attributionRegistryRejectsDuplicateProviders() {
    #expect(throws: AttributionAdapterError.duplicateProvider(.codex)) {
        try AttributionAdapters([
            FixtureAttributionAdapter(provider: .codex), FixtureAttributionAdapter(provider: .codex),
        ])
    }
}

@Test(arguments: [false, true])
func overlappingRuntimeRecognitionNeverChoosesByRegistrationOrder(reversed: Bool) throws {
    let first = FixtureAttributionAdapter(provider: .codex)
    let second = FixtureAttributionAdapter(provider: .claude)
    let adapters = try AttributionAdapters(reversed ? [second, first] : [first, second])
    let runtime = sample(10, executable: "/fixture/agent", memory: 1)
    let child = sample(20, parent: 10)
    var monitor = Monitor(adapters: adapters)
    monitor.ingest([runtime, child])
    monitor.enrich(ProcessMetadata(writerThreadIDs: [sessionA]), for: runtime.identity)
    monitor.enrich(
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]), for: child.identity)
    let row = try #require(monitor.finding(for: child.identity))
    #expect(row.attribution.runtime == runtime.identity)
    #expect(row.attribution.provider == nil)
    #expect(row.attribution.threadID == nil)
    #expect(row.attribution.evidence == .ambiguous)
    #expect(monitor.attributingMarker(for: child.identity) == nil)
}

@Test func sharedPipelineUsesAdapterRecognitionMarkersAndDetachedEvidence() throws {
    let adapters = try AttributionAdapters([FixtureAttributionAdapter(provider: .codex)])
    let runtime = sample(10, executable: "/fixture/agent", terminal: "ttys001", memory: 1)
    let worker = sample(20)
    let marker = ProcessArguments.parse(
        argumentBuffer(environment: [
            "FIXTURE_SESSION=\(sessionA)", "CODEX_THREAD_ID=\(sessionB)",
            "CLAUDE_CODE_MESSAGING_TOKEN=never-retained", "PRIVATE_TOKEN=never-retained",
        ]), adapters: adapters)
    #expect(marker.markers == [SessionMarker(threadID: sessionA, provider: .codex)])
    var monitor = Monitor(adapters: adapters)
    monitor.ingest([runtime, worker])
    var observationReads = 0
    monitor.enrich(for: [worker.identity]) { target in
        if target.identity == worker.identity { return marker }
        let evidence = adapters.runtimeEvidence(for: target.executable) { requests in
            observationReads += 1
            #expect(requests == [.openFilePaths])
            return RuntimeObservations(openFilePaths: ["fixture-writer"])
        }
        return ProcessMetadata(writerThreadIDs: evidence.writerThreadIDs)
    }
    let row = try #require(monitor.finding(for: worker.identity))
    #expect(observationReads == 1)
    #expect(row.attribution.provider == .codex)
    #expect(row.attribution.threadID == sessionA)
    #expect(row.attribution.runtime == runtime.identity)
    #expect(row.attribution.terminal == "ttys001")
}

@Test func runtimeObservationsAreRequestedOnlyByRecognizingAdapters() {
    let adapters = AttributionAdapters.builtIn
    for (executable, expected) in [
        ("/opt/bin/codex", Set([RuntimeObservation.openFilePaths])),
        ("/Users/test/.local/share/claude/versions/2.1.300", [.listeningSockets]),
    ] {
        var reads = 0
        _ = adapters.runtimeEvidence(for: executable) { requests in
            reads += 1
            #expect(requests == expected)
            return RuntimeObservations()
        }
        #expect(reads == 1)
    }
    _ = adapters.runtimeEvidence(for: "/opt/bin/node") { _ in
        Issue.record("An unrelated executable must not trigger runtime descriptor inspection")
        return RuntimeObservations()
    }
}

@Test func codexAdapterDecodesOnlyValidWriterDescriptorPaths() {
    let evidence = CodexAttributionAdapter().runtimeEvidence(
        from: RuntimeObservations(openFilePaths: [
            "/fixture/thread-writer-locks/\(sessionA).lock",
            "/fixture/thread-writer-locks/\(sessionA.uppercased()).lock",
            "/fixture/other/\(sessionB).lock", "/fixture/thread-writer-locks/\(sessionB).jsonl",
            "/fixture/thread-writer-locks/not-a-uuid.lock",
        ]))
    #expect(evidence.writerThreadIDs == [sessionA])
}

@Test(arguments: [
    ["CODEX_SESSION_ID=invalid"],
    ["CODEX_THREAD_ID=\(sessionA)", "CLAUDE_CODE_SESSION_ID=invalid"],
    ["CODEX_THREAD_ID=\(sessionA)", "CODEX_THREAD_ID=\(sessionB)"],
])
func malformedAdapterMarkersCannotFallBackToAnotherProvider(environment: [String]) {
    let metadata = ProcessArguments.parse(argumentBuffer(environment: environment))
    #expect(metadata.status == .malformed)
    #expect(metadata.markers.isEmpty)
}

@Test func builtInRecognitionKeepsNativeProviderBoundaries() {
    #expect(sample(10, executable: "/opt/bin/codex").runtimeProvider == .codex)
    #expect(sample(10, executable: "/opt/bin/claude").runtimeProvider == .claude)
    #expect(
        sample(10, executable: "/Users/test/.local/share/claude/versions/2.1.300").runtimeProvider == .claude)
    #expect(sample(10, executable: "/opt/bin/node").runtimeProvider == nil)
    #expect(sample(10, executable: "/fixture/versions/2.1.300").runtimeProvider == nil)
}

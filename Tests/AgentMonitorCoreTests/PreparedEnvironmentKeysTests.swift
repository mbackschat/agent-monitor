import Synchronization
import Testing

@testable import AgentMonitorCore

private final class EnvironmentDeclarationReads: Sendable {
    let count = Mutex(0)
    let receivedKeys = Mutex<[Set<String>]>([])
}

private struct EnvironmentDeclarationAdapter: AgentAttributionAdapter {
    let provider: AgentProvider
    let declaredKeys: Set<String>
    let markerKey: String
    let reads: EnvironmentDeclarationReads
    let runtimeObservations: Set<RuntimeObservation> = []

    var environmentKeys: Set<String> {
        reads.count.withLock { $0 += 1 }
        return declaredKeys
    }
    func recognizesRuntime(_ executable: String) -> Bool { false }
    func marker(in environment: [String: Set<String>]) throws -> SessionMarker? {
        let keys = Set(environment.keys)
        reads.receivedKeys.withLock { $0.append(keys) }
        #expect(keys.isSubset(of: declaredKeys))
        return try MarkerEnvironment.uuid(markerKey, in: environment).map {
            SessionMarker(threadID: $0, provider: provider)
        }
    }
    func runtimeEvidence(from observations: RuntimeObservations) -> RuntimeEvidence { RuntimeEvidence() }
    func runtimeLink(for marker: SessionMarker) -> RuntimeLink? { nil }
    func isSharedRuntime(_ attribution: Attribution) -> Bool { false }
}

@Suite struct PreparedEnvironmentKeysTests {
    @Test func immutableDeclarationsArePreparedOnceAcrossFreshArgumentObservations() throws {
        let codex = EnvironmentDeclarationReads()
        let claude = EnvironmentDeclarationReads()
        let adapters = try AttributionAdapters([
            EnvironmentDeclarationAdapter(
                provider: .codex, declaredKeys: ["SHARED_SESSION"], markerKey: "SHARED_SESSION", reads: codex),
            EnvironmentDeclarationAdapter(
                provider: .claude, declaredKeys: ["SHARED_SESSION", "CLAUDE_ONLY"],
                markerKey: "SHARED_SESSION", reads: claude),
        ])
        let bytes = argumentBuffer(arguments: ["worker", "private argument"], environment: [])
        for _ in 0..<6 {
            let result = ProcessArguments.parse(bytes, adapters: adapters)
            #expect(result.status == .notObserved)
            #expect(result.invocation == "worker")
            #expect(result.command == nil)
        }
        #expect(codex.count.withLock { $0 } == 1)
        #expect(claude.count.withLock { $0 } == 1)
    }

    @Test(arguments: [false, true])
    func overlappingDeclarationsKeepTheirUnionAndEachAdaptersExactInputs(includeCommand: Bool) throws {
        let session = "abcdefab-cdef-4abc-8def-abcdefabcdef"
        let codex = EnvironmentDeclarationReads()
        let claude = EnvironmentDeclarationReads()
        let adapters = try AttributionAdapters([
            EnvironmentDeclarationAdapter(
                provider: .codex, declaredKeys: ["SHARED_SESSION", "CODEX_ONLY"],
                markerKey: "CODEX_ONLY", reads: codex),
            EnvironmentDeclarationAdapter(
                provider: .claude, declaredKeys: ["SHARED_SESSION", "CLAUDE_ONLY"],
                markerKey: "SHARED_SESSION", reads: claude),
        ])
        let result = ProcessArguments.parse(
            argumentBuffer(
                arguments: ["worker", ""],
                environment: [
                    "SHARED_SESSION=\(session)", "SHARED_SESSION=\(session.uppercased())",
                    "CODEX_ONLY=\(sessionB)", "CLAUDE_ONLY=declared-extra", "SHARED_SESSION_EXTRA=invalid",
                    "PRIVATE_TOKEN=never-retained", "CLAUDE_CODE_MESSAGING_TOKEN=never-retained",
                ]), includeCommand: includeCommand, adapters: adapters)
        #expect(adapters.environmentKeys == ["SHARED_SESSION", "CODEX_ONLY", "CLAUDE_ONLY"])
        #expect(result.status == .markerRead)
        #expect(
            result.markers == [
                SessionMarker(threadID: sessionB, provider: .codex),
                SessionMarker(threadID: session, provider: .claude),
            ])
        #expect(codex.receivedKeys.withLock { $0 } == [["SHARED_SESSION", "CODEX_ONLY"]])
        #expect(claude.receivedKeys.withLock { $0 } == [["SHARED_SESSION", "CLAUDE_ONLY"]])
        #expect(codex.count.withLock { $0 } == 1)
        #expect(claude.count.withLock { $0 } == 1)
        #expect(result.command == (includeCommand ? ["worker", ""] : nil))
    }

    @Test(arguments: [["invalid"], [sessionA, sessionB]])
    func preparedKeysDoNotHideInvalidOrConflictingSharedMarkers(values: [String]) throws {
        let adapters = try AttributionAdapters([
            EnvironmentDeclarationAdapter(
                provider: .codex, declaredKeys: ["CODEX_ONLY"], markerKey: "CODEX_ONLY",
                reads: EnvironmentDeclarationReads()),
            EnvironmentDeclarationAdapter(
                provider: .claude, declaredKeys: ["SHARED_SESSION"], markerKey: "SHARED_SESSION",
                reads: EnvironmentDeclarationReads()),
        ])
        let result = ProcessArguments.parse(
            argumentBuffer(
                arguments: ["worker", "private argument"],
                environment: ["CODEX_ONLY=\(sessionB)"] + values.map { "SHARED_SESSION=\($0)" }),
            adapters: adapters)
        #expect(result.status == .malformed)
        #expect(result.markers.isEmpty)
        #expect(result.invocation == "worker")
        #expect(result.command == nil)
    }
}

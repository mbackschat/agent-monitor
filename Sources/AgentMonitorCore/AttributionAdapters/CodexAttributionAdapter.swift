import Foundation

struct CodexAttributionAdapter: AgentAttributionAdapter {
    let provider = AgentProvider.codex
    let environmentKeys: Set<String> = ["CODEX_THREAD_ID", "CODEX_SESSION_ID"]
    let runtimeObservations: Set<RuntimeObservation> = [.openFilePaths]

    func recognizesRuntime(_ executable: String) -> Bool {
        URL(filePath: executable, directoryHint: .notDirectory).lastPathComponent == "codex"
    }

    func marker(in environment: [String: Set<String>]) throws -> SessionMarker? {
        let thread = try MarkerEnvironment.uuid("CODEX_THREAD_ID", in: environment)
        let root = try MarkerEnvironment.uuid("CODEX_SESSION_ID", in: environment)
        return thread.map { SessionMarker(threadID: $0, rootSessionID: root, provider: provider) }
    }

    /// Codex keeps open per-thread writer files; existence alone is insufficient. See
    /// docs/research/codex-terminal-attribution.md, recovering identity for sessions already running.
    func runtimeEvidence(from observations: RuntimeObservations) -> RuntimeEvidence {
        let threads = observations.openFilePaths.compactMap { value -> String? in
            let path = URL(filePath: value, directoryHint: .notDirectory)
            guard path.deletingLastPathComponent().lastPathComponent == "thread-writer-locks",
                path.pathExtension == "lock",
                let uuid = UUID(uuidString: path.deletingPathExtension().lastPathComponent)
            else { return nil }
            return uuid.uuidString.lowercased()
        }
        return RuntimeEvidence(writerThreadIDs: Set(threads).sorted())
    }

    func runtimeLink(for marker: SessionMarker) -> RuntimeLink? { .writerThread(marker.threadID) }

    func isSharedRuntime(_ attribution: Attribution) -> Bool {
        attribution.threadID == nil && attribution.evidence == .ambiguous
            && Set(attribution.candidateThreadIDs).count > 1
    }
}

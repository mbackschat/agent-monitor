import Foundation

struct ClaudeAttributionAdapter: AgentAttributionAdapter {
    let provider = AgentProvider.claude
    let environmentKeys: Set<String> = ["CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_MESSAGING_SOCKET"]
    let runtimeObservations: Set<RuntimeObservation> = [.listeningSockets]

    func recognizesRuntime(_ executable: String) -> Bool {
        let path = URL(filePath: executable, directoryHint: .notDirectory)
        if path.lastPathComponent == "claude" { return true }
        let directory = path.deletingLastPathComponent()
        return directory.lastPathComponent == "versions"
            && directory.deletingLastPathComponent().lastPathComponent == "claude"
    }

    func marker(in environment: [String: Set<String>]) throws -> SessionMarker? {
        try MarkerEnvironment.uuid("CLAUDE_CODE_SESSION_ID", in: environment).map {
            SessionMarker(
                threadID: $0, provider: provider,
                inboxSocket: inbox(environment["CLAUDE_CODE_MESSAGING_SOCKET"] ?? []))
        }
    }

    func runtimeEvidence(from observations: RuntimeObservations) -> RuntimeEvidence {
        RuntimeEvidence(listeningSockets: observations.listeningSockets)
    }

    func runtimeLink(for marker: SessionMarker) -> RuntimeLink? {
        marker.inboxSocket.map(RuntimeLink.listeningSocket)
    }

    func isSharedRuntime(_ attribution: Attribution) -> Bool { false }

    /// An unusable inbox leaves the session marker valid. sun_path holds 104 bytes including
    /// the terminator (sys/un.h); see docs/research/claude-session-messaging.md.
    private func inbox(_ values: Set<String>) -> String? {
        guard values.count == 1, let path = values.first, path.hasPrefix("/"), path.utf8.count < 104,
            path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return path
    }
}

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

    /// The native executable also runs embedded tools selected by `argv[0]` (observed: `ugrep` in
    /// Bash-tool pipelines); only invocation as itself or through the `claude` launcher is a runtime.
    /// See docs/research/claude-runtime-attribution.md.
    func acceptsRuntimeInvocation(_ invocation: String, executable: String) -> Bool {
        let name = URL(filePath: invocation, directoryHint: .notDirectory).lastPathComponent
        return name == "claude"
            || name == URL(filePath: executable, directoryHint: .notDirectory).lastPathComponent
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

    /// `claude agents --json` is the documented way to read live session state from outside
    /// Claude Code (https://code.claude.com/docs/en/agent-view). Nonessential traffic is disabled
    /// because some listings otherwise opened HTTPS connections; see
    /// docs/research/claude-runtime-attribution.md.
    let sessionRegistry: SessionRegistryQuery? = SessionRegistryQuery(
        tool: "Claude Code", command: ["claude", "agents", "--json"],
        environment: ["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"])

    /// Entries without a PID describe no live runtime and are skipped; unknown statuses are kept
    /// inactive so they still count when deciding whether a PID is listed exactly once.
    func runtimeSessions(fromRegistry output: Data) throws -> [RuntimeSession] {
        try JSONDecoder().decode([ListedSession].self, from: output).compactMap { entry in
            guard let pid = entry.pid, let runtimePID = Int32(exactly: pid), runtimePID > 0 else {
                return nil
            }
            return RuntimeSession(
                runtimePID: runtimePID,
                sessionID: entry.sessionId.flatMap(UUID.init(uuidString:))?.uuidString.lowercased(),
                active: entry.status.flatMap(ListedStatus.init(rawValue:)) != nil)
        }
    }

    /// Fields are optional so one incomplete entry does not reject the whole listing.
    private struct ListedSession: Decodable {
        let pid: Int?
        let sessionId: String?
        let status: String?
    }

    private enum ListedStatus: String {
        case busy, waiting, idle
    }

    /// An unusable inbox leaves the session marker valid. sun_path holds 104 bytes including
    /// the terminator (sys/un.h); see docs/research/claude-session-messaging.md.
    private func inbox(_ values: Set<String>) -> String? {
        guard values.count == 1, let path = values.first, path.hasPrefix("/"), path.utf8.count < 104,
            path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return path
    }
}

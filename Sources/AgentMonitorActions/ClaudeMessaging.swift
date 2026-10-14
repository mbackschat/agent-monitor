import AgentMonitorCore
import Darwin
import Foundation

/// Claude Code has no documented command that sends into a running session; each session's inbox
/// socket is the documented local delivery path. See docs/research/claude-session-messaging.md.
public struct ClaudeMessaging: AgentMessaging {
    private let executable: URL
    private let prefix: [String]
    private let timeout: TimeInterval
    private let locateInbox: @Sendable (HeavyProcess) throws -> String

    public init() {
        self.init(
            executable: URL(fileURLWithPath: "/usr/bin/env"), prefix: ["claude"],
            locateInbox: NativeActions.claudeInbox)
    }

    init(
        executable: URL, prefix: [String] = [], timeout: TimeInterval = 10,
        locateInbox: @escaping @Sendable (HeavyProcess) throws -> String
    ) {
        self.executable = executable
        self.prefix = prefix
        self.timeout = timeout
        self.locateInbox = locateInbox
    }

    public func recipients(for target: MessageTarget) throws -> MessageRecipients {
        // `/clear` or `/resume` can rebind a runtime to another session after its children inherited
        // the old marker. `claude agents --json` is the documented way to read live session state
        // from outside Claude Code: https://code.claude.com/docs/en/agent-view
        let command = try BoundedCommand(
            executable: executable, arguments: prefix + ["agents", "--json"], timeout: timeout,
            tool: "Claude Code")
        defer { command.close() }
        let listing = try command.readOutput()
        guard let sessions = (try? JSONSerialization.jsonObject(with: listing)) as? [[String: Any]] else {
            throw ActionFailure("Claude Code returned an unsupported session listing. Update Claude Code.")
        }
        let hosted = sessions.filter { ($0["pid"] as? Int) == Int(target.runtime.pid) }
        guard hosted.count == 1, let session = hosted.first else {
            throw ActionFailure("Claude Code does not list the runtime as one live session.")
        }
        guard (session["sessionId"] as? String)?.lowercased() == target.session else {
            throw ActionFailure("The Claude runtime now hosts another session. Select the process again.")
        }
        switch session["status"] as? String {
        case "busy", "waiting", "idle": break
        default: throw ActionFailure("Claude Code returned an unknown session status.")
        }
        _ = try inbox(for: target)
        let recipient = AgentRecipient(id: target.session, label: "Claude session")
        return MessageRecipients(root: recipient, selected: recipient)
    }

    public func send(_ message: String, to recipient: String, for target: MessageTarget) throws {
        guard recipient == target.session else { throw ActionFailure("Choose the verified Claude session.") }
        let path = try inbox(for: target)
        // Claude Code 2.1.300 prints this stream-json user line as its own inbox usage hint. The auth
        // line is omitted deliberately: the session token identifies the session's own children,
        // whose messages bypass the peer controls that should apply to an external monitor.
        // https://code.claude.com/docs/en/cross-session-messaging#the-sessions-inbox-socket
        var line = try JSONSerialization.data(
            withJSONObject: ["type": "user", "message": ["role": "user", "content": message]],
            options: [.sortedKeys, .withoutEscapingSlashes])
        line.append(10)
        try InboxSocket.post(line, to: path, timeout: timeout)
    }

    private func inbox(for target: MessageTarget) throws -> String {
        let path = try locateInbox(target.process)
        // Claude refuses symlinked reply targets; require the user's own socket, not a link to one.
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK, info.st_uid == getuid() else {
            throw InboxSocket.notSent
        }
        return path
    }
}

import AgentMonitorCore
import Foundation

public struct CodexMessaging: AgentMessaging {
    private let executable: URL
    private let prefix: [String]
    private let timeout: TimeInterval

    public init() {
        executable = URL(fileURLWithPath: "/usr/bin/env")
        prefix = ["codex"]
        timeout = 10
    }

    init(executable: URL, prefix: [String] = [], timeout: TimeInterval = 10) {
        self.executable = executable
        self.prefix = prefix
        self.timeout = timeout
    }

    public func recipients(for target: MessageTarget) throws -> MessageRecipients {
        let thread = target.session
        guard UUID(uuidString: thread) != nil else { throw ActionFailure("Invalid session identifier.") }
        let process = try BoundedCommand(
            executable: executable,
            arguments: prefix + ["app-server", "proxy"], timeout: timeout, tool: "Codex")
        defer { process.close() }
        let socket = try ProxyWebSocket(process)
        _ = try socket.request(
            "initialize",
            params: Initialize(
                clientInfo: .init(name: "agent_monitor", version: AgentMonitorVersion.current)),
            as: Empty.self)
        try socket.notify("initialized")
        let selected = try read(thread, using: socket)
        guard selected.available, UUID(uuidString: selected.root) != nil else {
            throw ActionFailure("Selected Codex session is not live on the local app server.")
        }
        let root: AgentRecipient
        if selected.root == thread {
            root = AgentRecipient(id: thread, label: "Root agent")
        } else {
            let reason: String?
            do {
                let info = try read(selected.root, using: socket)
                reason =
                    info.root == selected.root && info.available
                    ? nil : "Root session is not live or verified"
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                reason = "Root session could not be verified"
            }
            root = AgentRecipient(id: selected.root, label: "Root agent", unavailableReason: reason)
        }
        return MessageRecipients(root: root, selected: AgentRecipient(id: thread, label: "Selected agent"))
    }

    public func send(_ message: String, to recipient: String, for target: MessageTarget) throws {
        guard UUID(uuidString: recipient) != nil else { throw ActionFailure("Invalid session identifier.") }
        // Both proxy and unix:// address the default local control socket; never let
        // configured remote routing send a message to a server we did not inspect.
        // https://learn.chatgpt.com/docs/cli/reference#codex-queue
        let process = try BoundedCommand(
            executable: executable,
            arguments: prefix + [
                "queue", "--remote", "unix://", "--thread", recipient, "--message", message,
            ],
            timeout: timeout, tool: "Codex")
        defer { process.close() }
        do {
            try process.finish()
        } catch {
            throw ActionFailure.uncertain(
                "Queue acceptance could not be confirmed. Check Codex before retrying; the message may have been accepted."
            )
        }
    }

    private func read(_ id: String, using process: ProxyWebSocket) throws -> (root: String, available: Bool) {
        let thread = try process.request(
            "thread/read", params: ThreadRead(threadId: id, includeTurns: false), as: ThreadReply.self
        ).thread
        guard thread.id == id else {
            throw ActionFailure("Codex returned an unsupported session response. Update Codex CLI.")
        }
        switch ThreadStatus(rawValue: thread.status.type) {
        case .idle, .active: return (thread.sessionId, true)
        case .notLoaded, .systemError: return (thread.sessionId, false)
        case nil: throw ActionFailure("Codex returned an unknown session status.")
        }
    }
}

// Only the app-server fields this client reads; decoding ignores the rest.
private struct Initialize: Encodable {
    struct ClientInfo: Encodable {
        let name: String
        let version: String
    }
    let clientInfo: ClientInfo
}

private struct Empty: Decodable {}

private struct ThreadRead: Encodable {
    let threadId: String
    let includeTurns: Bool
}

private struct ThreadReply: Decodable {
    struct Thread: Decodable {
        struct Status: Decodable { let type: String }
        let id: String
        let sessionId: String
        let status: Status
    }
    let thread: Thread
}

private enum ThreadStatus: String {
    case idle, active, notLoaded, systemError
}

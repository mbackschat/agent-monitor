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
            params: [
                "clientInfo": ["name": "agent_monitor", "version": "0.1.0"]
            ])
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
            throw ActionFailure(
                "Queue acceptance could not be confirmed. Check Codex before retrying; the message may have been accepted."
            )
        }
    }

    private func read(_ id: String, using process: ProxyWebSocket) throws -> (root: String, available: Bool) {
        let result = try process.request("thread/read", params: ["threadId": id, "includeTurns": false])
        guard let thread = result["thread"] as? [String: Any], thread["id"] as? String == id,
            let root = thread["sessionId"] as? String,
            let status = thread["status"] as? [String: Any], let type = status["type"] as? String
        else { throw ActionFailure("Codex returned an unsupported session response. Update Codex CLI.") }
        switch type {
        case "idle", "active": return (root, true)
        case "notLoaded", "systemError": return (root, false)
        default: throw ActionFailure("Codex returned an unknown session status.")
        }
    }
}

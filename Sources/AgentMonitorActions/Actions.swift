import AgentMonitorCore
import Foundation

public struct ActionFailure: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct AgentRecipient: Equatable, Sendable {
    public let id: String
    public let label: String
    public let unavailableReason: String?
    public init(id: String, label: String, unavailableReason: String? = nil) {
        self.id = id
        self.label = label
        self.unavailableReason = unavailableReason
    }
}

public struct MessageRecipients: Equatable, Sendable {
    public let root: AgentRecipient
    public let selected: AgentRecipient
    public init(root: AgentRecipient, selected: AgentRecipient) {
        self.root = root
        self.selected = selected
    }
    public var choices: [AgentRecipient] { root.id == selected.id ? [root] : [root, selected] }
}

public struct MessageDraft: Equatable, Sendable {
    public let process: HeavyProcess
    public let recipients: MessageRecipients
    public init(process: HeavyProcess, recipients: MessageRecipients) {
        self.process = process
        self.recipients = recipients
    }
    public func message(_ text: String) -> String {
        let name = process.name.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? "�" : String($0)
        }.joined()
        return "[Agent Monitor: selected process PID \(process.process.pid) (\(name))]\n" + text
    }
}

/// A provider verifies live recipients separately from accepting a queued message.
public protocol AgentMessaging: Sendable {
    func recipients(for thread: String) throws -> MessageRecipients
    func queue(_ message: String, to recipient: String) throws
}

public protocol ProcessActions: Sendable {
    func terminate(_ process: HeavyProcess) async throws
    func prepareMessage(for process: HeavyProcess) async throws -> MessageDraft
    func send(_ draft: MessageDraft, text: String, recipient: String) async throws
}

public struct SessionActions: ProcessActions {
    private let inspect: @Sendable (HeavyProcess) throws -> HeavyProcess
    private let signal: @Sendable (HeavyProcess) throws -> Void
    private let messaging: any AgentMessaging

    public init(
        inspect: @escaping @Sendable (HeavyProcess) throws -> HeavyProcess,
        terminate: @escaping @Sendable (HeavyProcess) throws -> Void,
        messaging: any AgentMessaging
    ) {
        self.inspect = inspect
        self.signal = terminate
        self.messaging = messaging
    }

    public static func local() -> Self {
        Self(inspect: NativeActions.inspect, terminate: NativeActions.terminate, messaging: CodexMessaging())
    }

    @concurrent public func terminate(_ process: HeavyProcess) async throws {
        try Task.checkCancellation()
        let current = try inspect(process)
        try validateProcess(process, current)
        try Task.checkCancellation()
        try signal(process)
    }

    @concurrent public func prepareMessage(for process: HeavyProcess) async throws -> MessageDraft {
        try Task.checkCancellation()
        let thread = try validateMessaging(process)
        let current = try inspect(process)
        try validateAttribution(process, current)
        let recipients = try messaging.recipients(for: thread)
        try validateRootHint(process, recipients)
        return MessageDraft(process: process, recipients: recipients)
    }

    @concurrent public func send(_ draft: MessageDraft, text: String, recipient: String) async throws {
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            text.count <= 4000,
            text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) || $0 == "\n" })
        else { throw ActionFailure("Use 1–4000 characters without terminal control codes.") }
        guard let chosen = draft.recipients.choices.first(where: { $0.id == recipient }),
            chosen.unavailableReason == nil
        else { throw ActionFailure("Choose an available, verified recipient.") }
        let thread = try validateMessaging(draft.process)
        let recipients = try messaging.recipients(for: thread)
        guard recipients == draft.recipients else {
            throw ActionFailure("Recipient availability changed. Close and reopen the composer.")
        }
        try validateRootHint(draft.process, recipients)
        try validateAttribution(draft.process, inspect(draft.process))
        try Task.checkCancellation()
        try messaging.queue(draft.message(text), to: recipient)
    }

    private func validateProcess(_ expected: HeavyProcess, _ current: HeavyProcess) throws {
        guard current.process == expected.process, current.executable == expected.executable else {
            throw ActionFailure("Process exited, changed executable, or PID was reused. Select it again.")
        }
    }

    private func validateAttribution(_ expected: HeavyProcess, _ current: HeavyProcess) throws {
        try validateProcess(expected, current)
        _ = try validateMessaging(current)
        let a = expected.attribution
        let b = current.attribution
        guard a.provider == b.provider, a.threadID == b.threadID,
            a.rootSessionID == b.rootSessionID, a.runtime == b.runtime, a.evidence == b.evidence
        else { throw ActionFailure("Process attribution changed. Select it again.") }
    }

    private func validateRootHint(_ process: HeavyProcess, _ recipients: MessageRecipients) throws {
        if let hint = process.attribution.rootSessionID, hint != recipients.root.id {
            throw ActionFailure("Live root disagrees with process attribution. Select it again.")
        }
    }

    private func validateMessaging(_ process: HeavyProcess) throws -> String {
        guard process.attribution.provider == .codex else {
            throw ActionFailure("Inline messaging supports Codex only; Claude requires its own session UI.")
        }
        guard let thread = process.attribution.threadID, UUID(uuidString: thread) != nil,
            process.attribution.runtime != nil, process.attribution.context != .unverified
        else { throw ActionFailure("Messaging needs an exact session and a live, verified runtime.") }
        switch process.attribution.evidence {
        case .marker, .inheritedMarker, .writerLock: return thread
        case .runtimeOnly, .ambiguous, .unknown:
            throw ActionFailure("Ambiguous or unresolved attribution cannot receive messages.")
        }
    }
}

import AgentMonitorCore
import Foundation

public struct ActionFailure: Error, LocalizedError, Sendable {
    public let message: String
    /// The request may have been accepted although that could not be confirmed; never retry blindly.
    public let uncertain: Bool
    public init(_ message: String) { self.init(message, uncertain: false) }
    private init(_ message: String, uncertain: Bool) {
        self.message = message
        self.uncertain = uncertain
    }
    public static func uncertain(_ message: String) -> Self { Self(message, uncertain: true) }
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
    /// Characters a user may write; the PID prefix is added on top.
    public static let maximumLength = 4000

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

/// A message request checked against fresh attribution: an exact session under a live runtime.
public struct MessageTarget: Equatable, Sendable {
    public let process: HeavyProcess
    public let session: String
    public let runtime: ProcessIdentity
    public init(process: HeavyProcess, session: String, runtime: ProcessIdentity) {
        self.process = process
        self.session = session
        self.runtime = runtime
    }
}

/// A provider verifies live recipients separately from accepting a message for delivery.
public protocol AgentMessaging: Sendable {
    func recipients(for target: MessageTarget) throws -> MessageRecipients
    func send(_ message: String, to recipient: String, for target: MessageTarget) throws
}

public protocol ProcessActions: Sendable {
    func terminate(_ process: HeavyProcess) async throws
    func prepareMessage(for process: HeavyProcess) async throws -> MessageDraft
    func send(_ draft: MessageDraft, text: String, recipient: String) async throws
    func focusTerminal(of process: HeavyProcess) async throws -> FocusOutcome
}

public struct SessionActions: ProcessActions {
    private let inspect: @Sendable (HeavyProcess) throws -> HeavyProcess
    private let signal: @Sendable (HeavyProcess) throws -> Void
    private let codex: any AgentMessaging
    private let claude: any AgentMessaging
    private let focus: TerminalFocus

    public init(
        inspect: @escaping @Sendable (HeavyProcess) throws -> HeavyProcess,
        terminate: @escaping @Sendable (HeavyProcess) throws -> Void,
        codex: any AgentMessaging, claude: any AgentMessaging, focus: TerminalFocus
    ) {
        self.inspect = inspect
        self.signal = terminate
        self.codex = codex
        self.claude = claude
        self.focus = focus
    }

    public static func local() -> Self {
        Self(
            inspect: NativeActions.inspect, terminate: NativeActions.terminate, codex: CodexMessaging(),
            claude: ClaudeMessaging(), focus: .local())
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
        let target = try validateMessaging(process)
        let current = try inspect(process)
        try validateAttribution(process, current)
        let recipients = try messaging(for: process).recipients(for: target)
        try validateRootHint(process, recipients)
        return MessageDraft(process: process, recipients: recipients)
    }

    @concurrent public func send(_ draft: MessageDraft, text: String, recipient: String) async throws {
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            text.count <= MessageDraft.maximumLength,
            text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) || $0 == "\n" })
        else {
            throw ActionFailure(
                "Use 1–\(MessageDraft.maximumLength) characters without terminal control codes.")
        }
        guard let chosen = draft.recipients.choices.first(where: { $0.id == recipient }),
            chosen.unavailableReason == nil
        else { throw ActionFailure("Choose an available, verified recipient.") }
        let target = try validateMessaging(draft.process)
        let messaging = try messaging(for: draft.process)
        let recipients = try messaging.recipients(for: target)
        guard recipients == draft.recipients else {
            throw ActionFailure("Recipient availability changed. Close and reopen the composer.")
        }
        try validateRootHint(draft.process, recipients)
        try validateAttribution(draft.process, inspect(draft.process))
        try Task.checkCancellation()
        try messaging.send(draft.message(text), to: recipient, for: target)
    }

    /// Focus follows the runtime rather than the workload, which may have exited or have no terminal.
    @concurrent public func focusTerminal(of process: HeavyProcess) async throws -> FocusOutcome {
        try Task.checkCancellation()
        switch process.attribution.context {
        case .terminal:
            guard let runtime = process.attribution.runtime else { break }
            return try focus.focus(runtime: runtime)
        case .nonterminal: throw ActionFailure("The agent runtime has no terminal.")
        case .unverified: break
        }
        throw ActionFailure("Focus needs the session's live agent runtime.")
    }

    private func messaging(for process: HeavyProcess) throws -> any AgentMessaging {
        switch process.attribution.provider {
        case .codex: return codex
        case .claude: return claude
        case nil: throw ActionFailure("Messaging needs an exact session and a live, verified runtime.")
        }
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

    private func validateMessaging(_ process: HeavyProcess) throws -> MessageTarget {
        guard process.attribution.provider != nil, let thread = process.attribution.threadID,
            UUID(uuidString: thread) != nil, let runtime = process.attribution.runtime,
            process.attribution.context != .unverified
        else { throw ActionFailure("Messaging needs an exact session and a live, verified runtime.") }
        switch process.attribution.evidence {
        case .marker, .inheritedMarker, .writerLock:
            return MessageTarget(process: process, session: thread, runtime: runtime)
        case .runtimeOnly, .ambiguous, .unknown:
            throw ActionFailure("Ambiguous or unresolved attribution cannot receive messages.")
        }
    }
}

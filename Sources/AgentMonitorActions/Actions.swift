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

public protocol ProcessActions: Sendable {
    func terminate(_ process: HeavyProcess) async throws
    func focusTerminal(of process: HeavyProcess) async throws -> FocusOutcome
}

public struct SessionActions: ProcessActions {
    private let inspect: @Sendable (HeavyProcess) throws -> HeavyProcess
    private let signal: @Sendable (HeavyProcess) throws -> Void
    private let focus: TerminalFocus

    public init(
        inspect: @escaping @Sendable (HeavyProcess) throws -> HeavyProcess,
        terminate: @escaping @Sendable (HeavyProcess) throws -> Void,
        focus: TerminalFocus
    ) {
        self.inspect = inspect
        self.signal = terminate
        self.focus = focus
    }

    public static func local() -> Self {
        Self(
            inspect: NativeActions.inspect, terminate: NativeActions.terminate, focus: .local())
    }

    @concurrent public func terminate(_ process: HeavyProcess) async throws {
        try Task.checkCancellation()
        guard !process.isHistorical else {
            throw ActionFailure("Historical contributors cannot initiate actions.")
        }
        let current = try inspect(process)
        try validateProcess(process, current)
        try Task.checkCancellation()
        try signal(process)
    }

    /// Focus follows the runtime rather than the workload, which may have exited or have no terminal.
    @concurrent public func focusTerminal(of process: HeavyProcess) async throws -> FocusOutcome {
        try Task.checkCancellation()
        guard !process.isHistorical else {
            throw ActionFailure("Historical contributors cannot initiate actions.")
        }
        return try focus.focus(runtime: Self.focusRuntime(for: process))
    }

    /// Snapshot eligibility only; the focus adapter still verifies the runtime.
    public static func canFocusTerminal(_ process: HeavyProcess) -> Bool {
        (try? focusRuntime(for: process)) != nil
    }

    private static func focusRuntime(for process: HeavyProcess) throws -> ProcessIdentity {
        guard !process.isHistorical else {
            throw ActionFailure("Historical contributors cannot initiate actions.")
        }
        switch process.attribution.context {
        case .terminal:
            if let runtime = process.attribution.runtime { return runtime }
        case .nonterminal: throw ActionFailure("The agent runtime has no terminal.")
        case .unverified: break
        }
        throw ActionFailure("Focus needs the session's live agent runtime.")
    }

    private func validateProcess(_ expected: HeavyProcess, _ current: HeavyProcess) throws {
        guard current.process == expected.process, current.executable == expected.executable else {
            throw ActionFailure("Process exited, changed executable, or PID was reused. Select it again.")
        }
    }

}

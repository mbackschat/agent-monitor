import AgentMonitorCore
import Foundation

/// The regular GUI application whose process tree hosts an agent runtime's terminal.
public struct HostApplication: Equatable, Sendable {
    public let pid: Int32
    public let bundleIdentifier: String?
    public let name: String
    public init(pid: Int32, bundleIdentifier: String?, name: String) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}

/// A runtime's controlling terminal, read fresh when the user asks for focus.
public struct TerminalHost: Equatable, Sendable {
    /// Device path such as `/dev/ttys019`; terminals report their sessions' devices in this form.
    public let tty: String
    public let application: HostApplication
    public init(tty: String, application: HostApplication) {
        self.tty = tty
        self.application = application
    }

    static func isDevicePath(_ path: String) -> Bool {
        path.wholeMatch(of: /\/dev\/ttys[0-9]+/) != nil
    }
}

public enum FocusOutcome: Equatable, Sendable {
    /// An adapter selected the session that owns the TTY and asked its window to the front.
    case session(application: String, tty: String)
    /// No adapter knows the host, so only the application was asked to the front.
    case application(String)
}

/// One terminal application's way to bring the session that owns a TTY to the front.
///
/// Adapters may only read session identities and select, unminimize, order, or activate. They
/// must never type, run commands, or read screen contents, although the same Automation consent
/// would allow it (docs/research/terminal-focus.md#5-safety).
public protocol TerminalFocusAdapter: Sendable {
    var bundleIdentifiers: Set<String> { get }
    /// Returns false when the application lists no session on `tty`.
    func focus(tty: String, in application: HostApplication) throws -> Bool
}

public struct TerminalFocus: Sendable {
    private let locate: @Sendable (ProcessIdentity) throws -> TerminalHost
    private let adapters: [any TerminalFocusAdapter]
    private let activate: @Sendable (HostApplication) -> Bool

    public init(
        locate: @escaping @Sendable (ProcessIdentity) throws -> TerminalHost,
        adapters: [any TerminalFocusAdapter], activate: @escaping @Sendable (HostApplication) -> Bool
    ) {
        self.locate = locate
        self.adapters = adapters
        self.activate = activate
    }

    public static func local() -> Self {
        Self(
            locate: NativeActions.terminalHost, adapters: [TerminalAppFocus()],
            activate: NativeActions.activate)
    }

    public func focus(runtime: ProcessIdentity) throws -> FocusOutcome {
        let host = try locate(runtime)
        let application = host.application
        guard let identifier = application.bundleIdentifier,
            let adapter = adapters.first(where: { $0.bundleIdentifiers.contains(identifier) })
        else {
            guard activate(application) else {
                throw ActionFailure("macOS did not accept the request to bring \(application.name) forward.")
            }
            return .application(application.name)
        }
        // No fallback to activation: another window of the same app could show a different session.
        guard try adapter.focus(tty: host.tty, in: application) else {
            throw ActionFailure("\(application.name) lists no session on \(host.tty). Nothing was focused.")
        }
        return .session(application: application.name, tty: host.tty)
    }
}

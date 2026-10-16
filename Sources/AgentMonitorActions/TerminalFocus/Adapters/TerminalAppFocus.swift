import AgentMonitorCore
import Foundation

/// Terminal.app exposes each tab's `tty` and a writable `selected` through its scripting
/// dictionary (`sdef /System/Applications/Utilities/Terminal.app`); it has no pane class.
public struct TerminalAppFocus: TerminalFocusAdapter {
    public let bundleIdentifiers: Set<String> = ["com.apple.Terminal"]
    private let executable: URL
    private let prefix: [String]
    private let timeout: TimeInterval

    public init() { self.init(executable: URL(fileURLWithPath: "/usr/bin/osascript")) }

    init(executable: URL, prefix: [String] = [], timeout: TimeInterval = 30) {
        self.executable = executable
        self.prefix = prefix
        self.timeout = timeout
    }

    // Fixed text: the device path arrives only as `argv`. `is running` keeps a quit Terminal from
    // being relaunched. Addressing by bundle id rather than PID assumes one Terminal instance.
    // The inner timeout answers before the outer process deadline, so a pending consent prompt
    // reports -1712 instead of a killed helper.
    // `windows` also lists windows without tabs (one appeared as class `item`, 2026-10-15); reading
    // their tabs fails with -1728, so skip them rather than abort the search, but keep the
    // permission and timeout errors.
    static let script = """
        on run argv
            set target to item 1 of argv
            try
                if application id "com.apple.Terminal" is not running then return "missing"
                with timeout of 20 seconds
                    tell application id "com.apple.Terminal"
                        repeat with w in windows
                            try
                                set candidates to tabs of w
                            on error number code
                                if code is -1743 or code is -1712 then error number code
                                set candidates to {}
                            end try
                            repeat with t in candidates
                                if tty of t is target then
                                    set selected of t to true
                                    set miniaturized of w to false
                                    set index of w to 1
                                    activate
                                    return "focused"
                                end if
                            end repeat
                        end repeat
                    end tell
                end timeout
                return "missing"
            on error number code
                return "error " & code
            end try
        end run
        """

    public func focus(tty: String, in application: HostApplication) throws -> Bool {
        guard TerminalHost.isDevicePath(tty) else {
            throw ActionFailure("Refusing a malformed terminal device.")
        }
        let command = try BoundedCommand(
            executable: executable, arguments: prefix + ["-e", Self.script, tty], timeout: timeout,
            tool: "Terminal automation")
        defer { command.close() }
        let reply = String(decoding: try command.readOutput(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch reply {
        case "focused": return true
        case "missing": return false
        // -1743 errAEEventNotPermitted and -1712 errAETimeout, AppleEvents.h / MacErrors.h.
        case "error -1743":
            throw ActionFailure(
                "macOS has not allowed the terminal running Agent Monitor to control Terminal. Allow it in System Settings › Privacy & Security › Automation, then try again."
            )
        case "error -1712":
            throw ActionFailure(
                "Terminal did not answer in time. If macOS is asking for permission, answer it and try again."
            )
        case let error where error.hasPrefix("error "):
            throw ActionFailure("Terminal refused the focus request (AppleScript \(error)).")
        default:
            throw ActionFailure("Terminal returned an unsupported focus reply.")
        }
    }
}

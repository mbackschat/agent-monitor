import AgentMonitorCore
import AgentMonitorPresentation
import ApplicationServices
import Darwin
import Foundation

/// Keeps font workarounds in the terminal host, outside shared history and native chart drawing.
enum TerminalChartSelection {
    static func resolve(
        requested: ContributorChartStyle? = nil, environment: [String: String],
        font: () -> String? = localFont
    ) -> ContributorChartStyle {
        if let requested { return requested }
        guard environment["TERM_PROGRAM"] == "Apple_Terminal" else { return .stacked }
        guard environment["TMUX"] == nil, environment["STY"] == nil,
            environment["SSH_CONNECTION"] == nil
        else { return .compact }
        let name = (font() ?? "").lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        // These families passed the user's font comparison; Meslo and unknown fonts use the
        // single-row fallback. See docs/research/terminal-ui.md, 2026-10-31/2026-11-01.
        return ["menlo", "sourcecodepro", "monaco", "bitstreamverasansmono"].contains {
            name.hasPrefix($0)
        } ? .stacked : .compact
    }

    private static func localFont() -> String? {
        appleTerminalFont(tty: ttyname(STDOUT_FILENO).map { String(cString: $0) })
    }

    static func appleTerminalFont(
        tty: String?, permitted: () -> Bool = automationAllowed,
        query: (String) throws -> String = queryFont
    ) -> String? {
        guard let tty, tty.hasPrefix("/dev/tty"), tty.utf8.count < 128,
            !tty.contains(where: { $0.isWhitespace || $0.asciiValue.map { $0 < 32 } == true }),
            permitted()
        else { return nil }
        guard let reply = try? query(tty) else { return nil }
        let name = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 256,
            !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return name
    }

    private static func automationAllowed() -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Terminal")
        guard let descriptor = target.aeDesc else { return false }
        // AppleEvents.h: false checks existing authorization without requesting consent.
        return AEDeterminePermissionToAutomateTarget(descriptor, typeWildCard, typeWildCard, false) == noErr
    }

    private static func queryFont(tty: String) throws -> String {
        let command = try BoundedCommand(
            executable: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", script, tty], timeout: 2, tool: "Terminal font lookup")
        defer { command.close() }
        return String(decoding: try command.readOutput(), as: UTF8.self)
    }

    // Terminal.sdef exposes tty and current settings on each tab. Match our device, never the
    // frontmost tab or default profile; argv keeps the device path out of executable script text.
    // Only local read-only AppleEvents are sent; no shell, provider or network helper is invoked.
    static let script = """
        on run argv
            if application id "com.apple.Terminal" is not running then return ""
            with timeout of 1 second
                tell application id "com.apple.Terminal"
                    repeat with w in windows
                        try
                            set candidates to tabs of w
                        on error number code
                            if code is -1743 or code is -1712 then error number code
                            set candidates to {}
                        end try
                        repeat with t in candidates
                            if tty of t is item 1 of argv then return font name of current settings of t
                        end repeat
                    end repeat
                end tell
            end timeout
            return ""
        end run
        """
}

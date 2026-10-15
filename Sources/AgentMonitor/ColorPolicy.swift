import Darwin
import Foundation

/// Colors only reach a terminal: pipes and files stay plain, and `--no-color` or a non-empty
/// NO_COLOR (https://no-color.org) disable them.
enum ColorPolicy {
    static func enabled(noColor: Bool, environment: [String: String], isTerminal: Bool) -> Bool {
        !noColor && (environment["NO_COLOR"] ?? "").isEmpty && isTerminal
    }

    static func enabled(noColor: Bool, descriptor: Int32) -> Bool {
        enabled(
            noColor: noColor, environment: ProcessInfo.processInfo.environment,
            isTerminal: isatty(descriptor) == 1)
    }
}

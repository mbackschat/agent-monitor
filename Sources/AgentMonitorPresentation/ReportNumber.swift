import Foundation

enum ReportNumber {
    /// Two decimals in the POSIX locale, so every report prints "1.50" regardless of the user's region.
    static func text(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

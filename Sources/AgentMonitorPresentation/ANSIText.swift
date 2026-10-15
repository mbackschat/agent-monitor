/// SGR colors for line-oriented terminal output. The 16 basic colors follow the user's terminal
/// theme, unlike the TUI's fixed SwiftTUI palette; callers decide whether color is wanted.
public enum ANSIText {
    public static func styled(_ line: ReportLine) -> String {
        let code: String? =
            switch line.style {
            case .normal: nil
            case .title: "1;34"
            case .heading: "1"
            case .selected, .separator: "1;36"
            case .heavy, .warning: "33"
            case .muted: "90"
            case .success: "32"
            case .failure: "31"
            }
        guard let code, !line.text.isEmpty else { return line.text }
        return "\u{1B}[\(code)m\(line.text)\u{1B}[0m"
    }
}

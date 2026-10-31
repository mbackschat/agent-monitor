/// SGR colors for line-oriented terminal output. The 16 basic colors follow the user's terminal
/// theme; callers decide whether color is wanted.
public enum ANSIText {
    public static func styled(_ line: ReportLine) -> String {
        line.runs.map(styled).joined()
    }

    private static func styled(_ run: ReportLine.Run) -> String {
        let code: String? =
            switch run.style {
            case .normal: nil
            case .title: "1;34"
            case .heading: "1"
            case .selected: "1;7"
            case .separator: "36"
            case .heavy, .warning: "33"
            case .muted: "90"
            case .success: "32"
            case .failure: "31"
            }
        guard let code, !run.text.isEmpty else { return run.text }
        return "\u{1B}[\(code)m\(run.text)\u{1B}[0m"
    }
}

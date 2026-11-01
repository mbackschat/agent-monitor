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
            case .title, .identity: "1;34"
            case .metric: "1;36"
            case .shortcut: "1;4;36"
            case .chartFill: "34;44"
            case .chartOverflow: "33"
            case .chartOverflowFill: "33;43"
            case .heading: "1"
            case .selected: "1;7"
            case .separator: "34"
            case .heavy, .warning: "33"
            case .muted: "90"
            case .success: "32"
            case .failure: "31"
            }
        guard let code, !run.text.isEmpty else { return run.text }
        return "\u{1B}[\(code)m\(run.text)\u{1B}[0m"
    }
}

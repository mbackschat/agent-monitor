import AgentMonitorPresentation

/// The live report's only coverage warning is the badge on the footer Diagnostics control; counts and
/// explanations stay inside Diagnostics (docs/usage.md, `ed0672d`). Narrow footers shorten the label.
func showsCoverageWarningBadge(_ lines: [ReportLine]) -> Bool {
    lines.contains { $0.text.contains(#/D (diagnostics |diag )?!/#) }
}

/// The selected row's headline plus its following context band, which carries executable and CWD
/// under the accepted ledger layout (docs/architecture.md#constrained-overview-presentation).
func selectedBlock(_ lines: [ReportLine]) -> String {
    guard let start = lines.firstIndex(where: { $0.style == .selected }) else { return "" }
    let band = lines[(start + 1)...].prefix { $0.style == .normal && !$0.text.allSatisfy(\.isWhitespace) }
    return ([lines[start]] + band).map(\.text).joined(separator: "\n")
}

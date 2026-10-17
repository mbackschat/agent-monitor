import AgentMonitorCore

public struct DiagnosisViewState: Equatable, Sendable {
    public enum Phase: String, Sendable { case hidden, collecting, completed, failed, cancelled }
    public internal(set) var phase: Phase = .hidden
    public internal(set) var isRunning = false
    public internal(set) var content: [ReportLine] = []
    public var isVisible: Bool { phase != .hidden }

    public static let purpose = "Find which processes use the most CPU during a short observation."
    public static let whenToRun =
        "Run while the slowdown is happening; work that ended earlier cannot be recovered."
    public static var startHelp: String { "\(purpose) \(whenToRun) \(help)" }
    public static let interpretation =
        "Start with the largest CPU-seconds contributors. Use their PID and session evidence to find the workload in the live table; check coverage and Monitor helper flags before drawing conclusions."
    public static let help =
        "Measures from now: three one-second waits plus scan time; provider lookup may add up to three seconds per queried provider."
    public static let keyHint = "d CPU diagnosis"
    public static let cleanupHint = "CPU diagnosis cleanup in progress"
    public static let limits =
        "Collection and provider lookups add resource use. Monitor helper flags cover only observed relations to this interface; reparented/unobserved helpers and other monitor instances may be unflagged."

    public init() {}

    init(phase: Phase = .hidden, isRunning: Bool = false, content: [ReportLine] = []) {
        self.phase = phase
        self.isRunning = isRunning
        self.content = content
    }

    public var lines: [ReportLine] {
        switch phase {
        case .hidden: []
        case .collecting:
            [
                ReportLine(Self.purpose), ReportLine(Self.whenToRun), ReportLine(Self.help),
                ReportLine("Window starts at invocation.", style: .muted),
            ]
        case .completed: content
        case .failed: [ReportLine(DiagnosisText.collectionFailure, style: .failure)]
        case .cancelled:
            [ReportLine("Cancelled. No result retained.", style: .muted)]
                + (isRunning ? [ReportLine("Waiting for owned work to finish before another run.")] : [])
        }
    }

    public var reportText: String? {
        guard phase == .completed else { return nil }
        return content.map(\.text).joined(separator: "\n")
    }

    static func resultLines(_ value: CPUDiagnosis) -> [ReportLine] {
        [
            ReportLine(
                "Window started at invocation; result stays fixed until rerun or dismissal.", style: .muted),
            ReportLine(Self.interpretation),
        ]
            + DiagnosisText.lines(value, includingHelperFlags: true).map { ReportLine($0) }
            + [
                ReportLine(
                    "Launch-origin evidence is not proof of current use or exclusive ownership of shared daemons.",
                    style: .muted),
                ReportLine(Self.limits, style: .muted),
            ]
    }

    private func wrapped(width: Int) -> [ReportLine] {
        lines.flatMap { line in
            TerminalCells.wrapped(line.text, to: width).map { ReportLine($0, style: line.style) }
        }
    }

    func maximumOffset(width: Int, height: Int) -> Int {
        max(0, wrapped(width: width).count - max(0, height - 3))
    }

    public func terminalLines(width: Int, height: Int, offset: Int = 0) -> [ReportLine] {
        guard width > 0, height > 0 else { return [] }
        let title = ReportLine("CPU diagnosis · \(phase.rawValue)", style: .title)
        let controls = "Esc back | x cancel | q quit"
        if width < 40 || height < 8 {
            return [title, ReportLine("Resize to 40x8 or larger"), ReportLine(controls)]
                .prefix(height).map { ReportLine(TerminalCells.clipped($0.text, to: width), style: $0.style) }
        }
        let rows = wrapped(width: width)
        let capacity = height - 3
        let first = min(max(0, offset), max(0, rows.count - capacity))
        var result = [title] + Array(rows.dropFirst(first).prefix(capacity))
        result += Array(repeating: ReportLine(""), count: max(0, height - 2 - result.count))
        result += [
            ReportLine("↑/↓ scroll | \(isRunning ? "Run again unavailable" : "d Run again")", style: .muted),
            ReportLine(controls, style: .muted),
        ]
        return result.map { ReportLine(TerminalCells.clipped($0.text, to: width), style: $0.style) }
    }
}

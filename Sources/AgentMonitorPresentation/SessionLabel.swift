import AgentMonitorCore

extension HeavyProcess {
    /// Multiple writer threads describe shared runtime overhead, not a failed workload lookup;
    /// see docs/architecture.md, attribution evidence and inspection scope.
    var isSharedRuntime: Bool {
        attribution.provider == .codex && attribution.runtime == process
            && attribution.threadID == nil && attribution.evidence == .ambiguous
            && Set(attribution.candidateThreadIDs).count > 1
    }

    var sessionDescription: String {
        attribution.threadID ?? (isSharedRuntime ? "shared runtime" : "unresolved")
    }
}

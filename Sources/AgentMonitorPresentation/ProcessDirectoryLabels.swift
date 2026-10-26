import AgentMonitorCore

/// Builds directory context once per displayed population, preserving distinguishable suffixes.
public struct ProcessDirectoryLabels: Sendable {
    private let labels: [String: String]

    public init(_ rows: [HeavyProcess]) {
        labels = WorkloadDirectory.compactLabels(
            for: Set(rows.compactMap { $0.isSharedRuntime ? nil : $0.cwd }))
    }

    public func label(for process: HeavyProcess) -> String {
        if process.isSharedRuntime { return "Shared runtime" }
        guard let cwd = process.cwd else { return "CWD unavailable" }
        return labels[cwd] ?? WorkloadDirectory.compact(cwd)
    }
}

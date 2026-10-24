/// Resources of all observed agent-associated process lifetimes, independent of report filters.
/// Missing measurements are counted separately; totals include only available values.
public struct AgentLoadSummary: Equatable, Sendable {
    public let processCount: Int
    public let cpuPercent: Double
    public let footprintBytes: UInt64
    public let missingCPUCount: Int
    public let missingFootprintCount: Int
    public let heavyProcesses: Set<ProcessIdentity>

    public init(processes: [HeavyProcess], window: ReportWindowSummary? = nil) {
        let agentContributions =
            window?.contributions.filter {
                ProcessScope.agentsOnly.includes($0.attribution)
            } ?? []
        let candidateIDs = Set(agentContributions.map(\.process))
        let agents = Dictionary(
            processes.filter {
                ProcessScope.agentsOnly.includes($0.accounting?.currentAttribution ?? $0.attribution)
                    || candidateIDs.contains($0.process)
            }
            .map { ($0.process, $0) }, uniquingKeysWith: { _, last in last }
        ).values
        processCount = agents.count
        if let window {
            let ids = Set(agents.map(\.process))
            let measured = agentContributions.filter {
                $0.openingScan >= window.baselineScan && ids.contains($0.process)
            }
            cpuPercent =
                window.durationSeconds > 0
                ? measured.reduce(0) { $0 + $1.cpuSeconds } * 100 / window.durationSeconds : 0
            let measuredIDs = Set(measured.map(\.process))
            missingCPUCount = agents.filter { !measuredIDs.contains($0.process) }.count
        } else {
            cpuPercent = agents.compactMap(\.cpuPercent).reduce(0, +)
            missingCPUCount = agents.filter { $0.cpuPercent == nil }.count
        }
        let currentAgents = agents.filter {
            !$0.isHistorical
                && ProcessScope.agentsOnly.includes($0.accounting?.currentAttribution ?? $0.attribution)
        }
        footprintBytes = currentAgents.compactMap(\.footprintBytes).reduce(0, +)
        missingFootprintCount = currentAgents.filter { $0.footprintBytes == nil }.count
        let thresholds = Thresholds.heavy
        heavyProcesses = Set(
            agents.filter {
                ($0.cpuPercent.map { $0 > thresholds.cpuPercent } ?? false)
                    || ($0.footprintBytes.map { $0 > thresholds.memoryBytes } ?? false)
            }.map(\.process))
    }
}

/// Resources of all observed agent-associated process lifetimes, independent of report filters.
/// Missing measurements are counted separately; totals include only available values.
public struct AgentLoadSummary: Equatable, Sendable {
    public let processCount: Int
    public let cpuPercent: Double
    public let footprintBytes: UInt64
    public let missingCPUCount: Int
    public let missingFootprintCount: Int
    public let heavyProcesses: Set<ProcessIdentity>

    public init(processes: [HeavyProcess]) {
        let agents = Dictionary(
            processes.filter { ProcessScope.agentsOnly.includes($0.attribution) }
                .map { ($0.process, $0) }, uniquingKeysWith: { _, last in last }
        ).values
        processCount = agents.count
        cpuPercent = agents.compactMap(\.cpuPercent).reduce(0, +)
        footprintBytes = agents.compactMap(\.footprintBytes).reduce(0, +)
        missingCPUCount = agents.filter { $0.cpuPercent == nil }.count
        missingFootprintCount = agents.filter { $0.footprintBytes == nil }.count
        let thresholds = Thresholds()
        heavyProcesses = Set(
            agents.filter {
                ($0.cpuPercent.map { $0 > thresholds.cpuPercent } ?? false)
                    || ($0.footprintBytes.map { $0 > thresholds.memoryBytes } ?? false)
            }.map(\.process))
    }
}

import AgentMonitorCore

extension HeavyProcess {
    var sessionDescription: String {
        attribution.threadID ?? (isSharedRuntime ? "shared runtime" : "unresolved")
    }
}

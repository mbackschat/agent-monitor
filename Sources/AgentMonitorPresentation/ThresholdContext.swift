import AgentMonitorCore

public enum ThresholdContext {
    public static func text(_ thresholds: Thresholds) -> String {
        if thresholds.isUnfiltered { return "All observed processes" }
        var filters: [String] = []
        if thresholds.cpuPercent > 0 {
            filters.append("CPU > \(ReportNumber.text(thresholds.cpuPercent))%")
        }
        if thresholds.memoryBytes > 0 {
            filters.append("footprint > \(ReportNumber.text(Double(thresholds.memoryBytes) / 1e9)) GB")
        }
        return filters.joined(separator: " OR ")
    }
}

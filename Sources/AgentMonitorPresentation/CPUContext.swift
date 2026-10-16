import AgentMonitorCore
import Foundation

public enum CPUContext {
    public static func text(_ accounting: CPUAccounting?) -> String {
        guard let accounting else { return "CPU: host No data · your measured processes No data" }
        let host = accounting.hostBusyPercent.map { String(format: "%.0f%%", $0) } ?? "No data"
        let measured = String(format: "%.0f%%", accounting.measuredUserPercent)
        return
            "CPU: host \(host) of \(accounting.logicalCPUCount * 100)% · your measured processes \(measured) (\(accounting.unmeasuredLifetimeCount) without data)"
    }
}

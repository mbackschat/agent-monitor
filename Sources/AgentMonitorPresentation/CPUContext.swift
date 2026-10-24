import AgentMonitorCore
import Foundation

public enum CPUContext {
    public static func text(_ accounting: CPUAccounting?) -> String {
        guard let accounting else { return "CPU: host No data · your measured processes No data" }
        let host = accounting.hostBusyPercent.map { String(format: "%.0f%%", $0) } ?? "No data"
        let measured = String(format: "%.0f%%", accounting.measuredUserPercent)
        var line =
            "CPU: host \(host) of \(accounting.logicalCPUCount * 100)% · your measured processes \(measured) (\(accounting.unmeasuredLifetimeCount) without data)"
        if let timing = accounting.acquisition {
            if let period = timing.achievedPeriodSeconds {
                line += String(format: " · period %.0f ms", period * 1000)
            }
            if timing.resolutionDelaySeconds > timing.requestedPeriodSeconds {
                line += String(format: " · resolution %.1f s behind", timing.resolutionDelaySeconds)
            }
        }
        return line
    }
}

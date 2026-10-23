import AgentMonitorCore

public enum FootprintContext {
    public static func kernelPeak(_ process: HeavyProcess) -> String? {
        process.kernelPeakFootprintBytes.map {
            "Kernel footprint peak: \(ReportNumber.text(Double($0) / 1e9)) GB (may reset on exec)"
        }
    }
}

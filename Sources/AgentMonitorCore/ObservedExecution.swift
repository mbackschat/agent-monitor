/// Polling-visible execution changes invalidate launch metadata; an unchanged observation
/// cannot certify continuity. See architecture's attribution and prompt-capture contract.
struct ObservedExecution: Sendable {
    private var executable: String
    private var name: String
    private var peak: UInt64?

    init(_ sample: ProcessSample) {
        executable = sample.executable
        name = sample.name
        peak = sample.kernelPeakFootprintBytes
    }

    mutating func update(_ sample: ProcessSample) -> Bool {
        let peakFell = peak.flatMap { old in sample.kernelPeakFootprintBytes.map { $0 < old } } ?? false
        let changed = executable != sample.executable || name != sample.name || peakFell
        executable = sample.executable
        name = sample.name
        peak = changed ? sample.kernelPeakFootprintBytes : (sample.kernelPeakFootprintBytes ?? peak)
        return changed
    }
}

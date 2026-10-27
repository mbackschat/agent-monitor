public enum SamplingMode: String, Codable, Sendable { case fixed, adaptive }
public enum SamplingOverride: String, Codable, CaseIterable, Sendable {
    case uncertainty, lifecycle, recovery, excess, sustained, inspection
}

public struct SamplingDecision: Equatable, Codable, Sendable {
    public var mode: SamplingMode
    public var requestedSeconds: Double
    public var baseSeconds: Double
    public var minimumSeconds: Double
    public var maximumSeconds: Double
    public var rollingCPURate: Double
    public var youngCPURate: Double
    public var arrivalRate: Double
    public var rollingSpanSeconds: Double
    public var recentCPURate: Double
    public var recentSpanSeconds: Double
    public var overrides: Set<SamplingOverride>

    public init(
        mode: SamplingMode = .fixed, requestedSeconds: Double = 0.1, baseSeconds: Double = 0.1,
        minimumSeconds: Double = 0.1, maximumSeconds: Double = 0.1,
        rollingCPURate: Double = 0, youngCPURate: Double = 0, arrivalRate: Double = 0,
        rollingSpanSeconds: Double = 0, recentCPURate: Double = 0, recentSpanSeconds: Double = 0,
        overrides: Set<SamplingOverride> = []
    ) {
        self.mode = mode
        self.requestedSeconds = requestedSeconds
        self.baseSeconds = baseSeconds
        self.minimumSeconds = minimumSeconds
        self.maximumSeconds = maximumSeconds
        self.rollingCPURate = rollingCPURate
        self.youngCPURate = youngCPURate
        self.arrivalRate = arrivalRate
        self.rollingSpanSeconds = rollingSpanSeconds
        self.recentCPURate = recentCPURate
        self.recentSpanSeconds = recentSpanSeconds
        self.overrides = overrides
    }
}

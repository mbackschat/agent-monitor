public struct SamplingSettings: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var minimum: Double
    public var visibleMaximum: Double
    public var closedMultiplier: Double
    public var window: Double

    public init(
        enabled: Bool = false, minimum: Double = 0.1, visibleMaximum: Double = 0.1,
        closedMultiplier: Double = 1, window: Double = 60
    ) {
        self.enabled = enabled
        self.minimum = minimum
        self.visibleMaximum = visibleMaximum
        self.closedMultiplier = closedMultiplier
        self.window = window
    }

    public var isValid: Bool {
        minimum.isFinite && visibleMaximum.isFinite && window.isFinite && closedMultiplier.isFinite
            && minimum >= 0.1 && minimum <= visibleMaximum && visibleMaximum <= 60
            && (1...300).contains(window) && closedMultiplier >= 1 && visibleMaximum * closedMultiplier <= 60
    }

    public func maximum(panelVisible: Bool) -> Double {
        visibleMaximum * (panelVisible ? 1 : closedMultiplier)
    }
}

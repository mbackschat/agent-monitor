import Foundation

// Keep the test-only reference independent: it is the oracle for this bounded production controller.
struct AdaptiveSamplingController: Sendable {
    struct Aggregate: Sendable {
        var opening: Double
        var closing: Double
        var cpu: Double = 0
        var youngCPU: Double = 0
        var arrivals: Int = 0
        var event = false
        var recovery = false
    }
    struct Rates: Sendable {
        var cpu = 0.0
        var youngCPU = 0.0
        var arrivals = 0.0
        var span = 0.0
    }
    struct Calibration: Sendable {
        var cpuLow = 0.001
        var cpuHigh = 0.020
        var arrivalsLow = 2.0 / 60
        var arrivalsHigh = 20.0 / 60
        var lookback = 1.0
        var excess = 0.020
        var sustained = 0.100
    }
    typealias Reason = SamplingOverride
    struct Decision: Sendable {
        var requested: Double
        var base: Double
        var rolling = Rates()
        var recent = Rates()
        var reasons: Set<Reason> = []
    }
    var minimum = 0.1
    var maximum: Double
    var window = 60.0
    var enabled = true
    var calibration = Calibration()
    private(set) var base = 0.1
    private(set) var history: [Aggregate] = []
    private var previousClose: Double?
    private var held = false

    init(maximum: Double, window: Double = 60, calibration: Calibration = Calibration()) {
        self.maximum = maximum
        self.window = window
        self.calibration = calibration
    }

    mutating func observe(_ value: Aggregate, uncertain: Bool = false, inspection: Bool = false) -> Decision {
        let elapsed = max(0, value.closing - (previousClose ?? value.opening))
        previousClose = value.closing
        history.append(value)
        history.removeAll { $0.closing <= value.closing - window }
        if history.isEmpty { history = [value] }
        if history.count > 3_002 { history.removeFirst(history.count - 3_002) }
        let rolling = rates(over: window, at: value.closing)
        let recent = rates(over: calibration.lookback, at: value.closing)
        let cpuScore = score(rolling.youngCPU, low: calibration.cpuLow, high: calibration.cpuHigh)
        let arrivalScore = score(
            rolling.arrivals, low: calibration.arrivalsLow, high: calibration.arrivalsHigh)
        let target = maximum - max(cpuScore, arrivalScore) * (maximum - minimum)
        if !uncertain {
            let step = held ? 0 : (maximum - minimum) * elapsed / window
            base = max(minimum, min(target, base + step))
        }
        held = uncertain
        var reasons: Set<Reason> = []
        if enabled {
            if uncertain { reasons.insert(.uncertainty) }
            if recent.cpu - rolling.cpu >= calibration.excess { reasons.insert(.excess) }
            if recent.cpu >= calibration.sustained { reasons.insert(.sustained) }
            let events = history.filter { $0.closing > value.closing - calibration.lookback }
            if events.contains(where: \.event) { reasons.insert(.lifecycle) }
            if events.contains(where: \.recovery) { reasons.insert(.recovery) }
        }
        if inspection { reasons.insert(.inspection) }
        return Decision(
            requested: reasons.isEmpty ? (enabled ? base : maximum) : minimum,
            base: base, rolling: rolling, recent: recent, reasons: reasons)
    }
    mutating func changeMaximum(_ value: Double) {
        maximum = value
        base = min(maximum, max(minimum, base))
    }
    mutating func restart(minimum: Double, window: Double, enabled: Bool, at: Double) {
        self.minimum = minimum
        self.window = window
        self.enabled = enabled
        base = minimum
        history.removeAll(keepingCapacity: true)
        previousClose = at
        held = false
    }

    mutating func openPanel(maximum: Double) {
        changeMaximum(maximum)
        if enabled { base = minimum }
    }

    private func rates(over horizon: Double, at now: Double) -> Rates {
        var result = Rates()
        var opening = now
        for (index, aggregate) in history.enumerated()
        where aggregate.closing > now - horizon || index == history.count - 1 {
            opening = min(opening, aggregate.opening)
            result.cpu += aggregate.cpu
            result.youngCPU += aggregate.youngCPU
            result.arrivals += Double(aggregate.arrivals)
        }
        guard now > opening else { return Rates() }
        result.span = now - opening
        result.cpu /= result.span
        result.youngCPU /= result.span
        result.arrivals /= result.span
        return result
    }

    private func score(_ value: Double, low: Double, high: Double) -> Double {
        max(0, min(1, (value - low) / (high - low)))
    }
}

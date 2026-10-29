import AgentMonitorCore

/// A startup hardware default or an explicit user choice, never an activity-dependent scale.
public struct ContributorChartRange: Equatable, Sendable {
    public enum Selection: Equatable, Sendable {
        case hardware
        case percent(Double)
    }

    public let hardwareUpper: Double
    public let fullUpper: Double
    public let usesPerformanceCores: Bool
    public private(set) var selection: Selection = .hardware
    public var upper: Double {
        switch selection {
        case .hardware: hardwareUpper
        case .percent(let value): value
        }
    }

    public init(topology: ProcessorTopology) {
        fullUpper = Double(topology.logicalCPUCount) * 100
        hardwareUpper = Double(topology.performanceCPUCount ?? topology.logicalCPUCount) * 100
        usesPerformanceCores = topology.performanceCPUCount != nil
    }

    public var choices: [Selection] {
        var values = Set([hardwareUpper, fullUpper])
        var value = 100.0
        while value < fullUpper {
            values.insert(value)
            value *= 2
        }
        return [.hardware] + values.sorted().map(Selection.percent)
    }

    public func label(for selection: Selection) -> String {
        switch selection {
        case .hardware:
            "Hardware default (\(Int(hardwareUpper))%)"
                + (usesPerformanceCores ? "" : " · all cores")
        case .percent(let value):
            "\(Int(value))%" + (value == fullUpper ? " · all cores" : "")
        }
    }

    public mutating func select(_ choice: Selection) {
        guard choices.contains(choice) else { return }
        selection = choice
    }

    public mutating func cycle() {
        let choices = choices
        selection = choices[((choices.firstIndex(of: selection) ?? 0) + 1) % choices.count]
    }
}

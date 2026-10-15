import AgentMonitorCore
import Foundation

struct MenuBarIndicator {
    enum Availability { case waiting, current, unavailable }

    private let processorCount: Int
    private var load: AgentLoadSummary?
    private var sampledAt: Date?
    private var unreadableCount = 0
    private var previousHeavy: Set<ProcessIdentity>?
    private var highlightSamples = 0
    private(set) var availability = Availability.waiting

    init(processorCount: Int = ProcessInfo.processInfo.activeProcessorCount) {
        self.processorCount = max(1, processorCount)
    }

    var highlighted: Bool { highlightSamples > 0 }

    var level: Int? {
        guard let load, load.missingCPUCount < load.processCount || load.processCount == 0 else { return nil }
        let fraction = load.cpuPercent / (100 * Double(processorCount))
        switch fraction {
        case ...0: return 0
        case ..<0.25: return 1
        case ..<0.5: return 2
        default: return 3
        }
    }

    mutating func receive(_ snapshot: MonitoringSnapshot) {
        guard let load = snapshot.agentLoad else {
            fail()
            return
        }
        if highlightSamples > 0 {
            highlightSamples -= 1
        } else if let previousHeavy, !load.heavyProcesses.subtracting(previousHeavy).isEmpty {
            highlightSamples = 2
        }
        previousHeavy = load.heavyProcesses
        self.load = load
        sampledAt = snapshot.timestamp
        unreadableCount = snapshot.unreadableProcessCount
        availability = .current
    }

    mutating func fail() {
        load = nil
        sampledAt = nil
        previousHeavy = nil
        highlightSamples = 0
        availability = .unavailable
    }

    var statusDescription: String { statusLines.joined(separator: "\n") }

    var statusLines: [String] {
        guard let load, let sampledAt else {
            switch availability {
            case .waiting: return ["Agent Monitor — waiting for a load sample"]
            case .unavailable, .current: return ["Agent Monitor — load unavailable; open to inspect"]
            }
        }
        let cpu = load.cpuPercent.formatted(.number.precision(.fractionLength(1)))
        let memory = (Double(load.footprintBytes) / 1e9).formatted(.number.precision(.fractionLength(1)))
        let partial = load.missingCPUCount > 0 || load.missingFootprintCount > 0
        return [
            "Agent Monitor — \(load.processCount) observed agent processes",
            "CPU \(load.missingCPUCount > 0 ? "≥ " : "")\(cpu)% (100% = one core)",
            "Footprint \(load.missingFootprintCount > 0 ? "≥ " : "")\(memory) GB",
            "Bars: share of all cores · boundaries at 25% and 50%",
            "\(load.heavyProcesses.count) heavy agent processes",
            "Heavy: CPU > 25% of one core or footprint > 1 GB",
            highlighted ? "New heavy load — temporary highlight" : nil,
            partial ? "Some resource measurements are unavailable" : nil,
            unreadableCount > 0 ? "\(unreadableCount) processes could not be read" : nil,
            "Sampled \(sampledAt.formatted(date: .omitted, time: .standard))",
        ].compactMap { $0 }
    }
}

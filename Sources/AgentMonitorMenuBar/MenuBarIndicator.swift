import AgentMonitorCore
import AgentMonitorPresentation
import Foundation

struct MenuBarIndicator {
    enum Availability { case waiting, current, unavailable }

    private let processorCount: Int
    private var load: AgentLoadSummary?
    private var cpuAccounting: CPUAccounting?
    private var sampledAt: Date?
    private var unreadableCount = 0
    private var historicalCount = 0
    private var hasCollapsedDetail = false
    private var thresholds = Thresholds()
    private var paused = false
    private(set) var availability = Availability.waiting

    init(processorCount: Int = ProcessInfo.processInfo.activeProcessorCount) {
        self.processorCount = max(1, processorCount)
    }

    var processCount: Int? { load?.processCount }

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

    mutating func receive(_ snapshot: MonitoringSnapshot, paused: Bool = false) {
        load = AgentLoadSummary(processes: snapshot.observedFindings, window: snapshot.window)
        cpuAccounting = snapshot.cpuAccounting
        thresholds = Thresholds(
            cpuPercent: snapshot.cpuThresholdPercent, memoryBytes: snapshot.memoryThresholdBytes)
        self.paused = paused
        sampledAt = snapshot.timestamp
        unreadableCount = snapshot.unreadableProcessCount
        historicalCount = snapshot.observedFindings.filter(\.isHistorical).count
        hasCollapsedDetail = snapshot.window?.collapsedContributions.isEmpty == false
        availability = .current
    }

    mutating func fail() {
        load = nil
        cpuAccounting = nil
        sampledAt = nil
        availability = .unavailable
    }

    var statusDescription: String { statusLines.joined(separator: "\n") }

    var statusLines: [String] {
        guard let load, let sampledAt else {
            switch availability {
            case .waiting: return ["Agent Monitor — waiting for first sample"]
            case .unavailable, .current: return ["Agent Monitor — load unavailable; open to inspect"]
            }
        }
        let cpu = load.cpuPercent.formatted(.number.precision(.fractionLength(1)))
        let memory = (Double(load.footprintBytes) / 1e9).formatted(.number.precision(.fractionLength(1)))
        let partial = load.missingCPUCount > 0 || load.missingFootprintCount > 0
        return [
            "Agent Monitor — \(load.processCountRange.text) observed agent-associated processes"
                + (hasCollapsedDetail
                    ? "; older detail collapsed"
                    : " in this window, including \(historicalCount) no longer observed"),
            paused ? "Paused — matching the displayed table" : nil,
            "Observed agents: CPU \(load.missingCPUCount > 0 ? "≥ " : "")\(cpu)% (100% = one core)",
            CPUContext.text(cpuAccounting),
            "Footprint \(load.missingFootprintCount > 0 ? "≥ " : "")\(memory) GB",
            "Bars: share of all cores · boundaries at 25% and 50%",
            "Totals include filtered and historical contributors; sampling can miss short-lived work",
            "Display window: measured CPU; session ownership is point evidence",
            thresholds.isUnfiltered
                ? "Display: all observed processes"
                : "Filter: \(ThresholdContext.text(thresholds))",
            partial ? "Some resource measurements are unavailable" : nil,
            unreadableCount > 0 ? "\(unreadableCount) listed PID reads failed in the latest scan" : nil,
            "Sampled \(sampledAt.formatted(date: .omitted, time: .standard))",
        ].compactMap { $0 }
    }
}

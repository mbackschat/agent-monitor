import AgentMonitorCore
import Foundation

public enum HistoryMetric: String, CaseIterable, Sendable {
    case cpu = "CPU"
    case memory = "Memory"
    case heavyCount = "Heavy"

    public var next: Self {
        switch self {
        case .cpu: .memory
        case .memory: .heavyCount
        case .heavyCount: .cpu
        }
    }

    public func formatted(_ value: Double?) -> String {
        guard let value else { return "—" }
        switch self {
        case .cpu: return String(format: "%.0f%%", value)
        case .memory: return String(format: "%.1f GB", value)
        case .heavyCount: return String(format: "%.0f", value)
        }
    }
}

public enum HistoryWindow: String, CaseIterable, Sendable {
    case tenMinutes = "10m"
    case oneHour = "1h"

    public var seconds: Double {
        switch self {
        case .tenMinutes: 600
        case .oneHour: 3600
        }
    }

    public var next: Self {
        switch self {
        case .tenMinutes: .oneHour
        case .oneHour: .tenMinutes
        }
    }
}

/// Bounded scalar history, independent of filtering and process identity retention.
/// One-second buckets preserve peaks; empty or wholly unavailable chart buckets remain gaps.
public struct ReportHistory: Equatable, Sendable {
    private struct Point: Equatable, Sendable {
        let second: Double
        var cpu: Double?
        var memory: Double?
        var heavy: Double?

        func value(_ metric: HistoryMetric) -> Double? {
            switch metric {
            case .cpu: cpu
            case .memory: memory
            case .heavyCount: heavy
            }
        }
    }

    private var points: [Point] = []
    private var current: Point?
    private var timestamp: Date?
    public var pointCount: Int { points.count }

    public init() {}

    public mutating func receive(_ snapshot: MonitoringSnapshot) {
        guard let load = snapshot.agentLoad else { return }
        if let timestamp, snapshot.timestamp < timestamp { points.removeAll(keepingCapacity: true) }
        guard timestamp != snapshot.timestamp else { return }
        timestamp = snapshot.timestamp
        let time = floor(snapshot.timestamp.timeIntervalSince1970)
        let point = Point(
            second: time,
            cpu: load.missingCPUCount == 0 ? load.cpuPercent : nil,
            memory: load.missingFootprintCount == 0 ? Double(load.footprintBytes) / 1e9 : nil,
            heavy: load.missingCPUCount == 0 && load.missingFootprintCount == 0
                ? Double(load.heavyProcesses.count) : nil)
        current = point
        if let last = points.last, last.second == time {
            points[points.count - 1] = Point(
                second: time, cpu: peak(last.cpu, point.cpu), memory: peak(last.memory, point.memory),
                heavy: peak(last.heavy, point.heavy))
        } else {
            points.append(point)
        }
        points.removeAll { $0.second < time - HistoryWindow.oneHour.seconds }
    }

    public func currentValue(_ metric: HistoryMetric) -> Double? { current?.value(metric) }

    public func values(metric: HistoryMetric, window: HistoryWindow, count: Int) -> [Double?] {
        guard count > 0 else { return [] }
        var bins = [Double?](repeating: nil, count: count)
        guard let end = current?.second else { return bins }
        let start = end - window.seconds
        for point in points where point.second > start && point.second <= end {
            let index = min(count - 1, Int(ceil((point.second - start) * Double(count) / window.seconds)) - 1)
            bins[index] = peak(bins[index], point.value(metric))
        }
        return bins
    }

    public func line(metric: HistoryMetric, window: HistoryWindow, width: Int) -> String {
        let prefix = "Agent \(metric.rawValue)[h] "
        let suffix = " \(metric.formatted(currentValue(metric))) · \(window.rawValue)[t]"
        let bins = values(
            metric: metric, window: window, count: min(40, max(1, width - prefix.count - suffix.count)))
        let maximum = max(1, bins.compactMap { $0 }.max() ?? 1)
        let glyphs = Array("▁▂▃▄▅▆▇█")
        let plot = String(
            bins.map { value in
                guard let value else { return Character(" ") }
                return glyphs[min(7, max(0, Int((value / maximum * 7).rounded())))]
            })
        return String((prefix + plot + suffix).prefix(max(0, width)))
            .padding(toLength: max(0, width), withPad: " ", startingAt: 0)
    }

    private func peak(_ left: Double?, _ right: Double?) -> Double? {
        switch (left, right) {
        case (.some(let left), .some(let right)): max(left, right)
        case (.some(let value), nil), (nil, .some(let value)): value
        case (nil, nil): nil
        }
    }
}

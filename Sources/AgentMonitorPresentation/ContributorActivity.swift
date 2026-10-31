import AgentMonitorCore
import Foundation

/// Whole retained intervals, shared by every contributor lane; not reconstructed scan samples.
public struct ContributorActivity: Equatable, Sendable {
    public struct Span: Equatable, Sendable {
        public let startedAt: Double
        public let endedAt: Double
        public var duration: Double { max(0, endedAt - startedAt) }
    }
    public struct Sample: Equatable, Sendable {
        public var cpuSeconds = 0.0
        public var measuredIntervals = 0
        public var qualified = false
        public func percent(in span: Span) -> Double? {
            measuredIntervals > 0 && span.duration > 0 ? 100 * cpuSeconds / span.duration : nil
        }
        mutating func merge(_ other: Self) {
            cpuSeconds += other.cpuSeconds
            measuredIntervals += other.measuredIntervals
            qualified = qualified || other.qualified
        }
    }
    public private(set) var spans: [Span] = []
    public private(set) var samples: [ContributorID: [Sample?]] = [:]
    public private(set) var ceiling = 100.0
    public var duration: Double { max(0, (spans.last?.endedAt ?? 0) - (spans.first?.startedAt ?? 0)) }
    public var maximumSpan: Double { spans.map(\.duration).max() ?? 0 }

    public init(ceiling: Double = 100) {
        self.ceiling = ceiling.isFinite && ceiling > 0 ? ceiling : 100
    }

    init(
        recent: RecentActivitySnapshot, nodes: [ContributorID: ContributorNode], ceiling: Double,
        leaf: (RecentWorkerCategory) -> ContributorID
    ) {
        self.init(ceiling: ceiling)
        let units = recent.units
        guard let first = units.first, let last = units.last else { return }
        let crossings = units.flatMap(\.crossings).filter {
            $0.contribution.id.opening.scan.sequence >= recent.baselineScan
        }
        // A crossing counter delta has no timing inside its endpoints. Only boundaries
        // outside every crossing are valid (architecture.md, Resource history).
        let ordered = crossings.sorted {
            $0.contribution.id.opening.scan.sequence < $1.contribution.id.opening.scan.sequence
        }
        var crossingIndex = 0
        var closingScan: UInt64 = 0
        let safe = (1..<units.count).filter { index in
            let scan = units[index].baselineScan
            while crossingIndex < ordered.count,
                ordered[crossingIndex].contribution.id.opening.scan.sequence < scan
            {
                closingScan = max(closingScan, ordered[crossingIndex].contribution.id.closing.scan.sequence)
                crossingIndex += 1
            }
            return closingScan <= scan
        }
        var boundaries: Set<Int> = []
        if safe.count <= 11 {
            boundaries = Set(safe)
        } else {
            for division in 1...11 {
                let target = first.startedAt + (last.endedAt - first.startedAt) * Double(division) / 12
                if let index = safe.min(by: {
                    abs(units[$0].startedAt - target) < abs(units[$1].startedAt - target)
                }) {
                    boundaries.insert(index)
                }
            }
        }
        let cuts = [0] + boundaries.sorted() + [units.count]
        for index in 0..<(cuts.count - 1) {
            spans.append(
                Span(startedAt: units[cuts[index]].startedAt, endedAt: units[cuts[index + 1] - 1].endedAt))
        }
        let empty = [Sample?](repeating: nil, count: spans.count)
        func add(_ value: Sample, to id: ContributorID, at index: Int) {
            var values = samples[id] ?? empty
            var sample = values[index] ?? Sample()
            sample.merge(value)
            values[index] = sample
            samples[id] = values
        }
        for index in spans.indices {
            for unit in units[cuts[index]..<cuts[index + 1]] {
                for record in unit.records {
                    add(
                        Sample(
                            cpuSeconds: record.cpuSeconds, measuredIntervals: record.measuredIntervals,
                            qualified: record.excludedObservations > 0 || record.measuredIntervals == 0),
                        to: leaf(record.category), at: index)
                }
                for value in unit.collapsedContributions {
                    add(
                        Sample(
                            cpuSeconds: value.cpuSeconds, measuredIntervals: value.intervalCount,
                            qualified: true), to: .collapsed(value.category), at: index)
                }
                for crossing in unit.crossings
                where crossing.contribution.id.opening.scan.sequence >= recent.baselineScan {
                    let value = crossing.contribution
                    add(
                        Sample(
                            cpuSeconds: value.cpuSeconds, measuredIntervals: value.intervalCount,
                            qualified: value.spansMissingScans), to: leaf(crossing.category), at: index)
                }
            }
        }
        func aggregate(_ id: ContributorID) -> [Sample?] {
            if let cached = samples[id] { return cached }
            var values = empty
            for child in nodes[id]?.children ?? [] {
                for (index, sample) in aggregate(child).enumerated() {
                    guard let sample else { continue }
                    var combined = values[index] ?? Sample()
                    combined.merge(sample)
                    values[index] = combined
                }
            }
            samples[id] = values
            return values
        }
        for id in nodes.keys { _ = aggregate(id) }

    }

    public var scaleLabel: String { "0–\(Int(ceiling))%" }

    public var intervalLabel: String {
        let unequal = spans.map(\.duration).min().map { maximumSpan - $0 > 0.001 } ?? false
        return "\(String(format: "%.1f", duration)) s · \(spans.count) interval averages"
            + (unequal ? " · unequal durations" : "")
    }

    public func terminalLane(for id: ContributorID, width: Int, level: Int = 0, rows: Int = 1) -> String {
        guard width > 0, !spans.isEmpty, let values = samples[id] else {
            return String(repeating: "·", count: max(0, width))
        }
        let levels = Array("▁▂▃▄▅▆▇█")
        return (0..<width).map { column in
            let index = min(spans.count - 1, column * spans.count / width)
            guard let sample = values[index], let percent = sample.percent(in: spans[index])
            else { return "·" }
            if percent > ceiling, level == 0 { return "↑" }
            let filled = min(
                8, max(0, Int(ceil(percent / ceiling * Double(8 * rows))) - (rows - level - 1) * 8))
            if filled == 0 { return level == rows - 1 ? "_" : " " }
            return String(levels[filled - 1])
        }.joined()
    }
}

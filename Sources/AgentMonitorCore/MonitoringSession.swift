import Foundation

public protocol ProcessReading: Sendable {
    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata
}

extension NativeProcessReader: ProcessReading {}

public protocol SamplingClock: Sendable {
    func wait(seconds: Double) async throws
    func now() -> Date
}

public struct ContinuousSamplingClock: SamplingClock {
    public init() {}
    public func wait(seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }
    public func now() -> Date { Date() }
}

public enum MonitoringError: Error { case invalidConfiguration }

public struct MonitoringConfiguration: Sendable {
    public let thresholds: Thresholds
    public let intervalSeconds: Double
    public let samples: Int
    public let includeCommands: Bool
    public let scope: ProcessScope
    public let collectAgentLoad: Bool

    public init(
        thresholds: Thresholds = Thresholds(), intervalSeconds: Double = 1, samples: Int = 1,
        includeCommands: Bool = false, scope: ProcessScope = .agentsOnly, collectAgentLoad: Bool = false
    ) throws {
        guard intervalSeconds.isFinite, (0.1...60).contains(intervalSeconds), samples >= 0,
            thresholds.cpuPercent.isFinite, thresholds.cpuPercent >= 0
        else { throw MonitoringError.invalidConfiguration }
        self.thresholds = thresholds
        self.intervalSeconds = intervalSeconds
        self.samples = samples
        self.includeCommands = includeCommands
        self.scope = scope
        self.collectAgentLoad = collectAgentLoad
    }
}

public struct MonitoringSnapshot: Equatable, Sendable {
    public let timestamp: Date
    public let intervalSeconds: Double
    public let cpuThresholdPercent: Double
    public let memoryThresholdBytes: UInt64
    public let sampledProcessCount: Int
    public let unreadableProcessCount: Int
    public let findings: [HeavyProcess]
    public let agentLoad: AgentLoadSummary?

    public init(
        timestamp: Date, intervalSeconds: Double, cpuThresholdPercent: Double,
        memoryThresholdBytes: UInt64, sampledProcessCount: Int, unreadableProcessCount: Int,
        findings: [HeavyProcess], agentLoad: AgentLoadSummary? = nil
    ) {
        self.timestamp = timestamp
        self.intervalSeconds = intervalSeconds
        self.cpuThresholdPercent = cpuThresholdPercent
        self.memoryThresholdBytes = memoryThresholdBytes
        self.sampledProcessCount = sampledProcessCount
        self.unreadableProcessCount = unreadableProcessCount
        self.findings = findings
        self.agentLoad = agentLoad
    }
}

public struct MonitoringSession: Sendable {
    private let configuration: MonitoringConfiguration
    private let reader: any ProcessReading
    private let clock: any SamplingClock
    private let excluded: Set<Int32>

    public init(
        configuration: MonitoringConfiguration, reader: any ProcessReading,
        clock: any SamplingClock = ContinuousSamplingClock(), excluding: Set<Int32> = []
    ) {
        self.configuration = configuration
        self.reader = reader
        self.clock = clock
        self.excluded = excluding
    }

    public var initialThresholds: Thresholds { configuration.thresholds }
    public var initialInterval: Double { configuration.intervalSeconds }

    /// Waits one interval and returns it. Changing a live interval wakes the wait, which then
    /// counts the time already waited against the new interval; CPU stays exact because it
    /// divides by the measured time between samples.
    private func wait(_ live: LiveInterval?) async throws -> Double {
        guard let live else {
            try await clock.wait(seconds: configuration.intervalSeconds)
            return configuration.intervalSeconds
        }
        let start = clock.now()
        while true {
            let (interval, generation) = live.current()
            guard interval.isFinite, (0.1...60).contains(interval) else {
                throw MonitoringError.invalidConfiguration
            }
            let remaining = interval - clock.now().timeIntervalSince(start)
            guard remaining > 0 else { return interval }
            let changed = try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    try await clock.wait(seconds: remaining)
                    return false
                }
                group.addTask {
                    await live.changed(after: generation)
                    return true
                }
                defer { group.cancelAll() }
                return try await group.next() ?? false
            }
            try Task.checkCancellation()
            guard changed else { return interval }
        }
    }

    /// Delivers snapshots sequentially, awaiting each consumer without buffering reports.
    /// Reads updated thresholds once per sample, preserving the CPU baseline.
    @concurrent public func run(
        thresholds currentThresholds: (@Sendable () async -> Thresholds)? = nil,
        interval live: LiveInterval? = nil,
        _ receive: @Sendable (MonitoringSnapshot) async throws -> Void
    ) async throws {
        try Task.checkCancellation()
        var monitor = Monitor()
        monitor.ingest(try reader.snapshot(excluding: excluded).samples)
        var count = 0
        var lastAgentLoadAt: Date?
        while configuration.samples == 0 || count < configuration.samples {
            let interval = try await wait(live)
            try Task.checkCancellation()
            let thresholds = await currentThresholds?() ?? configuration.thresholds
            guard thresholds.cpuPercent.isFinite, thresholds.cpuPercent >= 0 else {
                throw MonitoringError.invalidConfiguration
            }
            try Task.checkCancellation()
            let snapshot = try reader.snapshot(excluding: excluded)
            monitor.ingest(snapshot.samples)
            let sampledAt = clock.now()
            // Full-population metadata reads dominate history cost; see docs/research/menu-bar-load-cost.md.
            let collectAgentLoad =
                configuration.collectAgentLoad
                && (lastAgentLoadAt.map { sampledAt < $0 || sampledAt.timeIntervalSince($0) >= 15 } ?? true)
            if collectAgentLoad {
                lastAgentLoadAt = sampledAt
                for sample in snapshot.samples {
                    try Task.checkCancellation()
                    monitor.enrich(
                        reader.metadata(for: sample, includeCommand: configuration.includeCommands),
                        for: sample.identity)
                }
            } else {
                monitor.enrich(thresholds: thresholds) {
                    reader.metadata(for: $0, includeCommand: configuration.includeCommands)
                }
            }
            try await receive(
                MonitoringSnapshot(
                    timestamp: sampledAt, intervalSeconds: interval,
                    cpuThresholdPercent: thresholds.cpuPercent,
                    memoryThresholdBytes: thresholds.memoryBytes,
                    sampledProcessCount: snapshot.samples.count,
                    unreadableProcessCount: snapshot.unreadableCount,
                    findings: monitor.findings(
                        thresholds: thresholds, scope: configuration.scope),
                    agentLoad: collectAgentLoad ? monitor.agentLoad() : nil))
            count += 1
        }
    }
}

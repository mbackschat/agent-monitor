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

/// Runs a harness's declared session listing; injected so tests never start a provider CLI.
package protocol SessionRegistryReading: Sendable {
    func output(of query: SessionRegistryQuery) throws -> Data
}

package struct CommandSessionRegistryReader: SessionRegistryReading {
    private let executable: URL
    private let prefix: [String]
    private let timeout: TimeInterval

    /// Sampling uses a short timeout: a listing that cannot finish leaves runtimes unresolved for
    /// that sample. `executable` and `prefix` let tests substitute a fake CLI.
    package init(
        executable: URL = URL(fileURLWithPath: "/usr/bin/env"), prefix: [String] = [],
        timeout: TimeInterval = 3
    ) {
        self.executable = executable
        self.prefix = prefix
        self.timeout = timeout
    }

    package func output(of query: SessionRegistryQuery) throws -> Data {
        let command = try BoundedCommand(
            executable: executable, arguments: prefix + query.command, environment: query.environment,
            timeout: timeout, tool: query.tool)
        defer { command.close() }
        return try command.readOutput()
    }
}

/// When each provider's listing is due: immediately for a runtime the previous listing did not
/// cover, otherwise once a minute so bindings follow `/clear` or `/resume`. Failures wait the same
/// minute because a listing costs a provider CLI start (docs/research/claude-runtime-attribution.md).
struct SessionRegistryCadence {
    private var previous: [AgentProvider: (at: Date, runtimes: Set<ProcessIdentity>)] = [:]

    mutating func due(_ provider: AgentProvider, runtimes: Set<ProcessIdentity>, at now: Date) -> Bool {
        if let last = previous[provider], runtimes.isSubset(of: last.runtimes), now >= last.at,
            now.timeIntervalSince(last.at) < 60
        {
            return false
        }
        previous[provider] = (now, runtimes)
        return true
    }
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
    public let cpuAccounting: CPUAccounting
    public let timestamp: Date
    public let intervalSeconds: Double
    public let cpuThresholdPercent: Double
    public let memoryThresholdBytes: UInt64
    public let sampledProcessCount: Int
    public let unreadableProcessCount: Int
    public let findings: [HeavyProcess]
    public let agentLoad: AgentLoadSummary?

    public init(
        cpuAccounting: CPUAccounting, timestamp: Date, intervalSeconds: Double, cpuThresholdPercent: Double,
        memoryThresholdBytes: UInt64, sampledProcessCount: Int, unreadableProcessCount: Int,
        findings: [HeavyProcess], agentLoad: AgentLoadSummary? = nil
    ) {
        self.cpuAccounting = cpuAccounting
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
    private let registry: any SessionRegistryReading
    private let excluded: Set<Int32>

    public init(
        configuration: MonitoringConfiguration, reader: any ProcessReading,
        clock: any SamplingClock = ContinuousSamplingClock(), excluding: Set<Int32> = []
    ) {
        self.init(
            configuration: configuration, reader: reader, clock: clock,
            registry: CommandSessionRegistryReader(),
            excluding: excluding)
    }

    package init(
        configuration: MonitoringConfiguration, reader: any ProcessReading, clock: any SamplingClock,
        registry: any SessionRegistryReading, excluding: Set<Int32> = []
    ) {
        self.configuration = configuration
        self.reader = reader
        self.clock = clock
        self.registry = registry
        self.excluded = excluding
    }

    public var initialThresholds: Thresholds { configuration.thresholds }
    public var initialInterval: Double { configuration.intervalSeconds }

    /// Waits one interval and returns it. Changing a live interval wakes the wait, which then
    /// counts the time already waited against the new interval; CPU uses measured times,
    /// including the newborn listing boundary defined in docs/architecture.md#cpu-accounting.
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

    /// Runs the harness listings due for `findings` and reports whether any ran.
    /// A failed listing clears its provider's bindings; cancellation still ends the session.
    private func listSessions(
        for findings: [HeavyProcess], in monitor: inout Monitor, cadence: inout SessionRegistryCadence,
        at now: Date
    ) throws -> Bool {
        var listed = false
        for (provider, runtimes) in monitor.sessionRegistryRuntimes(in: findings)
        where cadence.due(provider, runtimes: runtimes, at: now) {
            guard let query = monitor.sessionRegistry(for: provider) else { continue }
            let output: Data?
            do {
                output = try registry.output(of: query)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                output = nil
            }
            monitor.bindSessions(output, provider: provider)
            listed = true
        }
        return listed
    }

    /// Delivers snapshots sequentially, awaiting each consumer without buffering reports.
    /// Reads updated thresholds once per sample, preserving the CPU baseline. `resolveSessions`
    /// lets a consumer that currently shows no session identities, such as a closed menu bar
    /// panel, skip harness listings while keeping existing bindings; nil always resolves.
    @concurrent public func run(
        thresholds currentThresholds: (@Sendable () async -> Thresholds)? = nil,
        interval live: LiveInterval? = nil,
        resolveSessions: (@Sendable () async -> Bool)? = nil,
        _ receive: @Sendable (MonitoringSnapshot) async throws -> Void
    ) async throws {
        try Task.checkCancellation()
        var monitor = Monitor()
        monitor.ingest(try reader.snapshot(excluding: excluded))
        var count = 0
        var lastAgentLoadAt: Date?
        var cadence = SessionRegistryCadence()
        while configuration.samples == 0 || count < configuration.samples {
            let interval = try await wait(live)
            try Task.checkCancellation()
            let thresholds = await currentThresholds?() ?? configuration.thresholds
            guard thresholds.cpuPercent.isFinite, thresholds.cpuPercent >= 0 else {
                throw MonitoringError.invalidConfiguration
            }
            try Task.checkCancellation()
            let snapshot = try reader.snapshot(excluding: excluded)
            let cpuAccounting = monitor.ingest(snapshot)
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
            var findings = monitor.findings(thresholds: thresholds, scope: configuration.scope)
            if await resolveSessions?() ?? true,
                try listSessions(for: findings, in: &monitor, cadence: &cadence, at: sampledAt)
            {
                findings = monitor.findings(thresholds: thresholds, scope: configuration.scope)
            }
            try await receive(
                MonitoringSnapshot(
                    cpuAccounting: cpuAccounting,
                    timestamp: sampledAt, intervalSeconds: interval,
                    cpuThresholdPercent: thresholds.cpuPercent,
                    memoryThresholdBytes: thresholds.memoryBytes,
                    sampledProcessCount: snapshot.samples.count,
                    unreadableProcessCount: snapshot.unreadableCount,
                    findings: findings,
                    agentLoad: collectAgentLoad ? monitor.agentLoad() : nil))
            count += 1
        }
    }
}

import Foundation

public protocol ProcessReading: Sendable {
    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata
    func isCurrent(_ sample: ProcessSample) -> Bool
    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata?
    func metadata(for sample: ProcessSample, includeCommand: Bool, capturedLaunch: ProcessMetadata?)
        -> ProcessMetadata
}

extension NativeProcessReader: ProcessReading {}

extension ProcessReading {
    public func isCurrent(_ sample: ProcessSample) -> Bool { false }
    public func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        nil
    }
    public func metadata(
        for sample: ProcessSample, includeCommand: Bool, capturedLaunch: ProcessMetadata?
    ) -> ProcessMetadata {
        capturedLaunch ?? metadata(for: sample, includeCommand: includeCommand)
    }
}

public protocol SamplingClock: Sendable {
    func wait(seconds: Double) async throws
    func now() -> Date
    func monotonicNow() -> Double
}

public struct ContinuousSamplingClock: SamplingClock {
    public init() {}
    public func wait(seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }
    public func now() -> Date { Date() }
    public func monotonicNow() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }
}

/// Runs a harness's declared session listing; injected so tests never start a provider CLI.
package protocol SessionRegistryReading: Sendable {
    func output(of query: SessionRegistryQuery) throws -> Data
    func output(of query: SessionRegistryQuery, checking: @escaping @Sendable () throws -> Void) throws
        -> Data
}

extension SessionRegistryReading {
    package func output(of query: SessionRegistryQuery, checking: @escaping @Sendable () throws -> Void)
        throws -> Data
    {
        try checking()
        let result = try output(of: query)
        try checking()
        return result
    }
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
        try output(of: query, checking: { try Task.checkCancellation() })
    }

    package func output(of query: SessionRegistryQuery, checking: @escaping @Sendable () throws -> Void)
        throws -> Data
    {
        let command = try BoundedCommand(
            executable: executable, arguments: prefix + query.command, environment: query.environment,
            timeout: timeout, tool: query.tool, checkCancellation: checking)
        defer { command.close() }
        return try command.readOutput()
    }
}

/// When each provider's listing is due: immediately for a runtime the previous listing did not
/// cover, otherwise once a minute so bindings follow `/clear` or `/resume`. Failures wait the same
/// minute because a listing costs a provider CLI start (docs/research/claude-runtime-attribution.md).
struct SessionRegistryCadence: Sendable {
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

public enum MonitoringError: Error, Equatable, LocalizedError {
    case invalidConfiguration
    case overloaded(stage: MonitoringStage, rejectedScan: UInt64)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Invalid monitoring configuration."
        case .overloaded(let stage, let scan):
            "Monitoring stopped: the \(stage.rawValue) queue reached its retention limit before scan \(scan). Accepted reports were drained; later measurements are unavailable."
        }
    }
}

public struct MonitoringConfiguration: Sendable {
    public let thresholds: Thresholds
    public let intervalSeconds: Double
    public let samples: Int
    public let includeCommands: Bool
    public let scope: ProcessScope
    public let collectAgentLoad: Bool
    public let pipelineLimits: MonitoringPipelineLimits
    public let reportIntervalSeconds: Double?
    public let promptCaptureLimits: PromptCaptureLimits

    public init(
        thresholds: Thresholds = Thresholds(), intervalSeconds: Double = 1, samples: Int = 1,
        includeCommands: Bool = false, scope: ProcessScope = .agentsOnly, collectAgentLoad: Bool = false,
        pipelineLimits: MonitoringPipelineLimits = MonitoringPipelineLimits(),
        promptCaptureLimits: PromptCaptureLimits = PromptCaptureLimits(), reportIntervalSeconds: Double? = nil
    ) throws {
        guard intervalSeconds.isFinite, (0.1...60).contains(intervalSeconds), samples >= 0,
            thresholds.cpuPercent.isFinite, thresholds.cpuPercent >= 0, pipelineLimits.isValid,
            promptCaptureLimits.isValid,
            reportIntervalSeconds.map({ $0.isFinite && (0.1...60).contains($0) }) ?? true
        else { throw MonitoringError.invalidConfiguration }
        self.thresholds = thresholds
        self.intervalSeconds = intervalSeconds
        self.samples = samples
        self.includeCommands = includeCommands
        self.scope = scope
        self.collectAgentLoad = collectAgentLoad
        self.pipelineLimits = pipelineLimits
        self.promptCaptureLimits = promptCaptureLimits
        self.reportIntervalSeconds = reportIntervalSeconds
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
    /// Unfiltered observations in the requested scope: display thresholds must not change resource totals.
    public let observedFindings: [HeavyProcess]
    public let agentLoad: AgentLoadSummary?
    public let window: ReportWindowSummary?

    public init(
        cpuAccounting: CPUAccounting, timestamp: Date, intervalSeconds: Double, cpuThresholdPercent: Double,
        memoryThresholdBytes: UInt64, sampledProcessCount: Int, unreadableProcessCount: Int,
        findings: [HeavyProcess], agentLoad: AgentLoadSummary? = nil,
        observedFindings: [HeavyProcess]? = nil, window: ReportWindowSummary? = nil
    ) {
        self.cpuAccounting = cpuAccounting
        self.timestamp = timestamp
        self.intervalSeconds = intervalSeconds
        self.cpuThresholdPercent = cpuThresholdPercent
        self.memoryThresholdBytes = memoryThresholdBytes
        self.sampledProcessCount = sampledProcessCount
        self.unreadableProcessCount = unreadableProcessCount
        self.findings = findings
        self.observedFindings = observedFindings ?? findings
        self.agentLoad = agentLoad
        self.window = window
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

    /// Acquisition and blocking resolution use separate serial threads and bounded FIFOs.
    @concurrent public func run(
        thresholds currentThresholds: (@Sendable () async -> Thresholds)? = nil,
        interval live: LiveInterval? = nil,
        _ receive: @Sendable (MonitoringSnapshot) async throws -> Void
    ) async throws {
        try await IndependentMonitoringPipeline(
            configuration: configuration, reader: reader, clock: clock, registry: registry, excluded: excluded
        ).run(thresholds: currentThresholds, interval: live, receive)
    }
}

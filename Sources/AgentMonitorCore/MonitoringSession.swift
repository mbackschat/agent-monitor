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

extension SamplingClock {
    public func wait(seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }
}

public struct ContinuousSamplingClock: SamplingClock {
    public init() {}
    public func now() -> Date { Date() }
    public func monotonicNow() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }
}

/// Runs a harness's declared session listing; injected so tests never start a provider CLI.
package protocol SessionRegistryReading: Sendable {
    var isAvailable: Bool { get }
    func output(of query: SessionRegistryQuery) throws -> Data
    func output(of query: SessionRegistryQuery, checking: @escaping @Sendable () throws -> Void) throws
        -> Data
}

extension SessionRegistryReading {
    package var isAvailable: Bool { true }

    package func output(of query: SessionRegistryQuery, checking: @escaping @Sendable () throws -> Void)
        throws -> Data
    {
        try checking()
        let result = try output(of: query)
        try checking()
        return result
    }
}

package struct OfflineSessionRegistryReader: SessionRegistryReading {
    package init() {}

    package var isAvailable: Bool { false }

    package func output(of query: SessionRegistryQuery) throws -> Data {
        throw BoundedCommandFailure(ProviderRuntimeAvailability.sessionListingUnavailableReason)
    }
}

package struct CommandSessionRegistryReader: SessionRegistryReading {
    private let executable: URL
    private let prefix: [String]
    private let timeout: TimeInterval

    /// Explicit executable injection is reserved for disposable fixtures. Production uses
    /// OfflineSessionRegistryReader because CLI startup has no offline guarantee
    /// (docs/architecture.md#offline-runtime).
    package init(
        executable: URL, prefix: [String] = [], timeout: TimeInterval = 3
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

    mutating func due(
        _ provider: AgentProvider, runtimes: Set<ProcessIdentity>, at now: Date,
        profile: PipelineProfile? = nil
    ) -> Bool {
        if let last = previous[provider], runtimes.isSubset(of: last.runtimes), now >= last.at,
            now.timeIntervalSince(last.at) < 60
        {
            return false
        }
        let reason: PipelineProfile.Counter
        if let last = previous[provider] {
            if now < last.at {
                reason = .registryClockResetAdmissions
            } else if now.timeIntervalSince(last.at) >= 60 {
                reason = .registryPeriodicAdmissions
            } else {
                reason = .registryNewRuntimeAdmissions
            }
        } else {
            reason = .registryInitialAdmissions
        }
        previous[provider] = (now, runtimes)
        profile?.increment(reason)
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
            "Monitoring stopped: \(stage.capacityDescription) reached its retention limit before scan \(scan). Coverage ends at the last delivered scan."
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
    public let inspectionObservations: Bool
    public let sampling: SamplingSettings

    public init(
        thresholds: Thresholds = Thresholds(), intervalSeconds: Double = 1, samples: Int = 1,
        includeCommands: Bool = false, scope: ProcessScope = .agentsOnly, collectAgentLoad: Bool = false,
        pipelineLimits: MonitoringPipelineLimits = MonitoringPipelineLimits(),
        promptCaptureLimits: PromptCaptureLimits = PromptCaptureLimits(),
        reportIntervalSeconds: Double? = nil,
        inspectionObservations: Bool = false, sampling: SamplingSettings? = nil
    ) throws {
        let sampling = sampling ?? SamplingSettings(visibleMaximum: intervalSeconds)
        guard sampling.isValid, intervalSeconds.isFinite, (0.1...60).contains(intervalSeconds), samples >= 0,
            thresholds.cpuPercent.isFinite, thresholds.cpuPercent >= 0, pipelineLimits.isValid,
            promptCaptureLimits.isValid, !inspectionObservations || reportIntervalSeconds != nil,
            reportIntervalSeconds.map({ $0.isFinite && (0.1...60).contains($0) }) ?? true
        else { throw MonitoringError.invalidConfiguration }
        self.thresholds = thresholds
        self.intervalSeconds = sampling.visibleMaximum
        self.sampling = sampling
        self.samples = samples
        self.includeCommands = includeCommands
        self.scope = scope
        self.collectAgentLoad = collectAgentLoad
        self.pipelineLimits = pipelineLimits
        self.promptCaptureLimits = promptCaptureLimits
        self.reportIntervalSeconds = reportIntervalSeconds
        self.inspectionObservations = inspectionObservations
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
    public let recentActivity: RecentActivitySnapshot?

    public init(
        cpuAccounting: CPUAccounting, timestamp: Date, intervalSeconds: Double, cpuThresholdPercent: Double,
        memoryThresholdBytes: UInt64, sampledProcessCount: Int, unreadableProcessCount: Int,
        findings: [HeavyProcess], agentLoad: AgentLoadSummary? = nil,
        observedFindings: [HeavyProcess]? = nil, window: ReportWindowSummary? = nil,
        recentActivity: RecentActivitySnapshot? = nil
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
        self.recentActivity = recentActivity
    }
}

public struct MonitoringSession: Sendable {
    private let configuration: MonitoringConfiguration
    private let reader: any ProcessReading
    private let clock: any AcquisitionClock
    private let registry: any SessionRegistryReading
    private let excluded: Set<Int32>
    private let recentActivity: RecentActivityStore?
    private var profile: PipelineProfile? = nil

    public init(
        configuration: MonitoringConfiguration, reader: any ProcessReading,
        clock: any AcquisitionClock = ContinuousSamplingClock(), excluding: Set<Int32> = [],
        recentActivity: RecentActivityStore? = nil
    ) {
        self.init(
            configuration: configuration, reader: reader, clock: clock,
            registry: OfflineSessionRegistryReader(),
            excluding: excluding, recentActivity: recentActivity)
    }

    package init(
        configuration: MonitoringConfiguration, reader: any ProcessReading, clock: any AcquisitionClock,
        registry: any SessionRegistryReading, excluding: Set<Int32> = [],
        recentActivity: RecentActivityStore? = nil
    ) {
        self.configuration = configuration
        self.reader = reader
        self.clock = clock
        self.registry = registry
        self.excluded = excluding
        self.recentActivity = recentActivity
    }

    package func profiling(_ profile: PipelineProfile) -> Self {
        var session = self
        session.profile = profile
        return session
    }

    public var initialThresholds: Thresholds { configuration.thresholds }
    public var inspectionObservations: Bool { configuration.inspectionObservations }
    public var initialInterval: Double { configuration.intervalSeconds }
    public var initialSampling: SamplingSettings { configuration.sampling }

    /// Serial counter/accounting collection is independent of blocking enrichment and presentation.
    @concurrent public func run(
        thresholds currentThresholds: (@Sendable () async -> Thresholds)? = nil,
        interval live: LiveInterval? = nil, inspection: LiveInspection? = nil,
        _ receive: @Sendable (MonitoringSnapshot) async throws -> Void
    ) async throws {
        try await IndependentMonitoringPipeline(
            configuration: configuration, reader: reader, clock: clock, registry: registry,
            excluded: excluded, recentActivity: recentActivity, profile: profile, inspection: inspection
        ).run(thresholds: currentThresholds, interval: live, receive)
    }
}

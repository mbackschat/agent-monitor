import Foundation

/// Bounds remain valid when an unobserved lifetime returns after its identity detail was released.
public struct LifetimeCountRange: Equatable, Codable, Sendable {
    public private(set) var minimum: Int
    public private(set) var maximum: Int

    public init(minimum: Int, maximum: Int) {
        precondition(minimum >= 0 && maximum >= minimum)
        self.minimum = minimum
        self.maximum = maximum
    }

    public var text: String { minimum == maximum ? "\(minimum)" : "\(minimum)–\(maximum)" }

    public mutating func union(_ other: Self) {
        minimum = max(minimum, other.minimum)
        maximum += other.maximum
    }
}

public struct CollapsedCategory: Hashable, Codable, Sendable {
    public let provider: AgentProvider?
    public let sessionID: String?
    public let rootSessionID: String?
    public let runtime: ProcessIdentity?
    public let candidates: [String]
    public let includedInAgentScope: Bool
    public let resolution: RecentSession.Resolution?
    public let executable: String?
    public let isAgentRuntime: Bool?
    public let agentAssociated: Bool
    public let categoryDetailsRetained: Bool

    init(_ category: RecentWorkerCategory, includedInAgentScope: Bool) {
        self.includedInAgentScope = includedInAgentScope
        runtime = category.owner.runtime
        candidates = category.owner.candidates
        provider = category.owner.provider
        sessionID = category.owner.sessionID
        rootSessionID = category.owner.rootSessionID
        resolution = category.owner.resolution
        executable = category.executable
        isAgentRuntime = category.isAgentRuntime
        agentAssociated = category.owner.isAgent
        categoryDetailsRetained = true
    }

    init(remainingAgentWork: Bool, includedInAgentScope: Bool, isAgentRuntime: Bool?) {
        self.includedInAgentScope = includedInAgentScope
        runtime = nil
        candidates = []
        provider = nil
        sessionID = nil
        rootSessionID = nil
        resolution = nil
        executable = nil
        self.isAgentRuntime = isAgentRuntime
        agentAssociated = remainingAgentWork
        categoryDetailsRetained = false
    }

    var textBytes: Int {
        ([sessionID, rootSessionID, executable].compactMap { $0 } + candidates).reduce(0) {
            $0 + $1.utf8.count
        }
    }
}

/// Exact resource aggregates with explicitly reduced identity/category detail under delivery pressure.
/// Count bounds combine by max/sum, never by assuming that absence proves a worker exited.
public struct CollapsedContribution: Equatable, Codable, Sendable {
    public let category: CollapsedCategory
    public private(set) var cpuSeconds: Double
    public private(set) var intervalCount: Int
    public private(set) var missingReadIntervalCount: Int
    public private(set) var executableChangedIntervalCount: Int
    public private(set) var excludedObservationCount: Int
    public private(set) var startedAt: Double
    public private(set) var endedAt: Double
    public private(set) var maximumFootprint: RecentMemoryReading?
    public private(set) var earliestEvidenceObservedAt: Double?
    public private(set) var latestEvidenceObservedAt: Double?
    public private(set) var missingEvidenceTimeCount: Int
    public private(set) var processCount: LifetimeCountRange
    public private(set) var workerCount: LifetimeCountRange

    init(
        category: CollapsedCategory, memory: RecentWorkerRecord, cpu: CPUContribution?,
        earliestEvidence: Double?, latestEvidence: Double?, missingEvidence: Int
    ) {
        self.category = category
        cpuSeconds = cpu?.cpuSeconds ?? 0
        intervalCount = cpu?.intervalCount ?? 0
        missingReadIntervalCount = cpu?.missingReadIntervalCount ?? 0
        executableChangedIntervalCount = memory.executableChangedIntervals
        excludedObservationCount = memory.excludedObservations
        startedAt = min(memory.firstObservedAt, cpu?.startedAt ?? memory.firstObservedAt)
        endedAt = max(memory.lastObservedAt, cpu?.endedAt ?? memory.lastObservedAt)
        maximumFootprint = memory.maximumFootprint
        earliestEvidenceObservedAt = earliestEvidence
        latestEvidenceObservedAt = latestEvidence
        missingEvidenceTimeCount = missingEvidence
        processCount = LifetimeCountRange(minimum: 1, maximum: 1)
        let workers = memory.category.isAgentRuntime ? 0 : 1
        workerCount = LifetimeCountRange(minimum: workers, maximum: workers)
    }

    mutating func setCounts(processes: Int, workers: Int) {
        processCount = LifetimeCountRange(minimum: processes, maximum: processes)
        workerCount = LifetimeCountRange(minimum: workers, maximum: workers)
    }

    public mutating func merge(_ other: Self) {
        precondition(category == other.category)
        cpuSeconds += other.cpuSeconds
        intervalCount += other.intervalCount
        missingReadIntervalCount += other.missingReadIntervalCount
        executableChangedIntervalCount += other.executableChangedIntervalCount
        excludedObservationCount += other.excludedObservationCount
        startedAt = min(startedAt, other.startedAt)
        endedAt = max(endedAt, other.endedAt)
        if let reading = other.maximumFootprint,
            maximumFootprint.map({
                reading.bytes > $0.bytes || (reading.bytes == $0.bytes && reading.observedAt < $0.observedAt)
            }) ?? true
        {
            maximumFootprint = reading
        }
        if let time = other.earliestEvidenceObservedAt {
            earliestEvidenceObservedAt = min(earliestEvidenceObservedAt ?? time, time)
        }
        if let time = other.latestEvidenceObservedAt {
            latestEvidenceObservedAt = max(latestEvidenceObservedAt ?? time, time)
        }
        missingEvidenceTimeCount += other.missingEvidenceTimeCount
        processCount.union(other.processCount)
        workerCount.union(other.workerCount)
    }

    func droppingCategoryDetail() -> Self {
        Self(
            category: CollapsedCategory(
                remainingAgentWork: category.agentAssociated,
                includedInAgentScope: category.includedInAgentScope, isAgentRuntime: category.isAgentRuntime),
            copying: self)
    }

    private init(category: CollapsedCategory, copying source: Self) {
        self.category = category
        cpuSeconds = source.cpuSeconds
        intervalCount = source.intervalCount
        missingReadIntervalCount = source.missingReadIntervalCount
        executableChangedIntervalCount = source.executableChangedIntervalCount
        excludedObservationCount = source.excludedObservationCount
        startedAt = source.startedAt
        endedAt = source.endedAt
        maximumFootprint = source.maximumFootprint
        earliestEvidenceObservedAt = source.earliestEvidenceObservedAt
        latestEvidenceObservedAt = source.latestEvidenceObservedAt
        missingEvidenceTimeCount = source.missingEvidenceTimeCount
        processCount = source.processCount
        workerCount = source.workerCount
    }
}

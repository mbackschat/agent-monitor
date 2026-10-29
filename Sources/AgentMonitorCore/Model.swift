import Foundation

public struct ProcessIdentity: Hashable, Codable, Sendable {
    public let pid: Int32
    public let startMicroseconds: UInt64

    public init(pid: Int32, startMicroseconds: UInt64) {
        self.pid = pid
        self.startMicroseconds = startMicroseconds
    }
}

public struct ProcessSample: Sendable {
    public let identity: ProcessIdentity
    public var parentPID: Int32
    public var executable: String
    public var name: String
    public var terminal: String?
    public var terminalDevice: UInt32?
    public var startedAt: Double?
    public var sampledAtTicks: UInt64?
    public var startedAtTicks: UInt64?
    public var sampledAt: Double
    public var cpuSeconds: Double?
    public var rawCPU: NativeCPUCounters?
    public var footprintBytes: UInt64?
    public var kernelPeakFootprintBytes: UInt64?

    public init(
        identity: ProcessIdentity, parentPID: Int32, executable: String, name: String,
        terminal: String? = nil, sampledAt: Double, cpuSeconds: Double?, footprintBytes: UInt64?
    ) {
        self.identity = identity
        self.parentPID = parentPID
        self.executable = executable
        self.name = name
        self.terminal = terminal
        self.sampledAt = sampledAt
        self.cpuSeconds = cpuSeconds
        self.footprintBytes = footprintBytes
    }

    public var runtimeProvider: AgentProvider? {
        AttributionAdapters.builtIn.runtimeProvider(for: executable)
    }
}

public enum AgentProvider: String, Codable, Sendable {
    case codex, claude
}

public struct SessionMarker: Equatable, Codable, Sendable {
    public let provider: AgentProvider
    public let threadID: String
    public let rootSessionID: String?
    /// Claude's per-session inbox socket, exported beside the session marker; routing detail only.
    public let inboxSocket: String?

    public init(
        threadID: String, rootSessionID: String? = nil, provider: AgentProvider,
        inboxSocket: String? = nil
    ) {
        self.provider = provider
        self.threadID = threadID
        self.rootSessionID = rootSessionID
        self.inboxSocket = inboxSocket
    }
}

public enum MetadataStatus: String, Codable, Sendable {
    case markerRead, notObserved, unavailable, malformed, truncated
}

public struct ProcessMetadata: Equatable, Sendable {
    /// At most one per provider; two only when one agent runs inside the other, and attribution
    /// then chooses by the nearest runtime.
    public var markers: [SessionMarker]
    public var status: MetadataStatus
    public var cwd: String?
    public var command: [String]?
    /// `argv[0]`, kept without the remaining arguments: multi-call executables select their
    /// behavior by it, so it can withdraw a runtime claim made from the executable path.
    public var invocation: String?
    public var terminal: String?
    public var writerThreadIDs: [String]
    /// Unix socket paths a Claude runtime listens on; links detached workloads to their inbox owner.
    public var listeningSockets: [String]

    public init(
        markers: [SessionMarker] = [], status: MetadataStatus = .notObserved,
        cwd: String? = nil, command: [String]? = nil, invocation: String? = nil, terminal: String? = nil,
        writerThreadIDs: [String] = [], listeningSockets: [String] = []
    ) {
        self.markers = markers
        self.status = status
        self.cwd = cwd
        self.command = command
        self.invocation = invocation
        self.terminal = terminal
        self.writerThreadIDs = writerThreadIDs
        self.listeningSockets = listeningSockets
    }
}

public enum AttributionEvidence: String, Codable, Sendable {
    case marker, inheritedMarker, writerLock, runtimeOnly, ambiguous, unknown
}

public enum RuntimeContext: String, Codable, Sendable {
    case terminal, nonterminal, unverified
}

public enum ProcessScope: Equatable, Sendable {
    case agentsOnly, allProcesses

    func includes(_ attribution: Attribution) -> Bool {
        switch self {
        case .agentsOnly: attribution.provider != nil || attribution.runtime != nil
        case .allProcesses: true
        }
    }
}

public struct Attribution: Hashable, Codable, Sendable {
    public let provider: AgentProvider?
    public let evidence: AttributionEvidence
    public let context: RuntimeContext
    public let threadID: String?
    public let rootSessionID: String?
    public let runtime: ProcessIdentity?
    public let terminal: String?
    public let runtimeDirectory: String?
    public let candidateThreadIDs: [String]
    public let ancestry: [ProcessIdentity]
}

public struct HeavyProcess: Equatable, Codable, Sendable {
    public let process: ProcessIdentity
    public let executable: String
    public let name: String
    public let invocationName: String?
    public var observedName: String { invocationName ?? name }
    public let cpuPercent: Double?
    public let footprintBytes: UInt64?
    public let kernelPeakFootprintBytes: UInt64?
    public let cwd: String?
    public let command: [String]?
    public let metadataStatus: MetadataStatus
    public let attribution: Attribution
    public let accounting: ProcessWindowAccounting?
    public var isHistorical: Bool { accounting?.isHistorical == true }

    init(
        process: ProcessIdentity, executable: String, name: String, cpuPercent: Double?,
        footprintBytes: UInt64?, kernelPeakFootprintBytes: UInt64? = nil, cwd: String?,
        command: [String]?, metadataStatus: MetadataStatus, attribution: Attribution,
        accounting: ProcessWindowAccounting? = nil, invocationName: String? = nil
    ) {
        self.process = process
        self.executable = executable
        self.name = name
        self.invocationName = invocationName
        self.cpuPercent = cpuPercent
        self.footprintBytes = footprintBytes
        self.kernelPeakFootprintBytes = kernelPeakFootprintBytes
        self.cwd = cwd
        self.command = command
        self.metadataStatus = metadataStatus
        self.attribution = attribution
        self.accounting = accounting
    }

    func usingAttribution(_ owner: Attribution) -> HeavyProcess {
        HeavyProcess(
            process: process, executable: executable, name: name, cpuPercent: cpuPercent,
            footprintBytes: footprintBytes, kernelPeakFootprintBytes: kernelPeakFootprintBytes,
            cwd: cwd, command: command, metadataStatus: metadataStatus, attribution: owner,
            accounting: accounting,
            invocationName: invocationName)
    }

    /// Provider evidence identifies shared runtime usage without assigning it to one thread.
    public var isSharedRuntime: Bool { AttributionAdapters.builtIn.isSharedRuntime(self) }
}

public struct Thresholds: Equatable, Sendable {
    public let cpuPercent: Double
    public let memoryBytes: UInt64

    public static let heavy = Thresholds(cpuPercent: 25, memoryBytes: 1_000_000_000)

    public var isUnfiltered: Bool { cpuPercent == 0 && memoryBytes == 0 }

    public func includes(cpu: Double?, footprint: UInt64?) -> Bool {
        isUnfiltered
            || (cpuPercent > 0 && cpu.map { $0 > cpuPercent } == true)
            || (memoryBytes > 0 && footprint.map { $0 > memoryBytes } == true)
    }

    public init(cpuPercent: Double = 0, memoryBytes: UInt64 = 0) {
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

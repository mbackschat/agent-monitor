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
    public var sampledAt: Double
    public var cpuSeconds: Double?
    public var footprintBytes: UInt64?

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
        let path = URL(fileURLWithPath: executable)
        switch path.lastPathComponent {
        case "codex": return .codex
        case "claude": return .claude
        default:
            let directory = path.deletingLastPathComponent()
            if directory.lastPathComponent == "versions",
                directory.deletingLastPathComponent().lastPathComponent == "claude"
            {
                return .claude
            }
            return nil
        }
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
        threadID: String, rootSessionID: String? = nil, provider: AgentProvider = .codex,
        inboxSocket: String? = nil
    ) {
        self.provider = provider
        self.threadID = threadID
        self.rootSessionID = rootSessionID
        self.inboxSocket = inboxSocket
    }
}

public enum MetadataStatus: String, Codable, Sendable {
    case markerRead, notObserved, unavailable, malformed
}

public struct ProcessMetadata: Sendable {
    public var marker: SessionMarker?
    public var status: MetadataStatus
    public var cwd: String?
    public var command: [String]?
    public var terminal: String?
    public var writerThreadIDs: [String]

    public init(
        marker: SessionMarker? = nil, status: MetadataStatus = .notObserved,
        cwd: String? = nil, command: [String]? = nil, terminal: String? = nil, writerThreadIDs: [String] = []
    ) {
        self.marker = marker
        self.status = status
        self.cwd = cwd
        self.command = command
        self.terminal = terminal
        self.writerThreadIDs = writerThreadIDs
    }
}

public enum AttributionEvidence: String, Codable, Sendable {
    case marker, inheritedMarker, writerLock, runtimeOnly, ambiguous, unknown
}

public enum RuntimeContext: String, Codable, Sendable {
    case terminal, nonterminal, unverified
}

public enum ProcessScope: Sendable {
    case agentsOnly, allProcesses

    func includes(_ attribution: Attribution) -> Bool {
        switch self {
        case .agentsOnly: attribution.provider != nil || attribution.runtime != nil
        case .allProcesses: true
        }
    }
}

public struct Attribution: Equatable, Codable, Sendable {
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
    public let cpuPercent: Double?
    public let footprintBytes: UInt64?
    public let cwd: String?
    public let command: [String]?
    public let metadataStatus: MetadataStatus
    public let attribution: Attribution
}

public struct Thresholds: Equatable, Sendable {
    public let cpuPercent: Double
    public let memoryBytes: UInt64

    public init(cpuPercent: Double = 25, memoryBytes: UInt64 = 1_000_000_000) {
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

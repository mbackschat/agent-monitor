import Foundation

/// Provider rules consume host-allowlisted observations and report evidence. Native access,
/// process lifetimes and competing claims stay in the host (docs/architecture.md#agent-attribution-adapters).
protocol AgentAttributionAdapter: Sendable {
    var provider: AgentProvider { get }
    var environmentKeys: Set<String> { get }
    var runtimeObservations: Set<RuntimeObservation> { get }
    func recognizesRuntime(_ executable: String) -> Bool
    /// Whether a process recognized from `executable` is still a runtime when invoked as
    /// `invocation` (`argv[0]`). Consulted only for recognized executables whose arguments were read.
    func acceptsRuntimeInvocation(_ invocation: String, executable: String) -> Bool
    func marker(in environment: [String: Set<String>]) throws -> SessionMarker?
    func runtimeEvidence(from observations: RuntimeObservations) -> RuntimeEvidence
    func runtimeLink(for marker: SessionMarker) -> RuntimeLink?
    func isSharedRuntime(_ attribution: Attribution) -> Bool
    /// The harness's own listing of the sessions its live runtimes host, for runtimes whose
    /// session no native observation reveals. Nil when the harness offers none.
    var sessionRegistry: SessionRegistryQuery? { get }
    func runtimeSessions(fromRegistry output: Data) throws -> [RuntimeSession]
}

extension AgentAttributionAdapter {
    func acceptsRuntimeInvocation(_ invocation: String, executable: String) -> Bool { true }
    var sessionRegistry: SessionRegistryQuery? { nil }
    func runtimeSessions(fromRegistry output: Data) throws -> [RuntimeSession] { [] }
}

/// A harness CLI command the host runs through `PATH`, with `environment` overlaid, to list the
/// sessions of live runtimes. The adapter declares and parses it; it never runs it.
package struct SessionRegistryQuery: Equatable, Sendable {
    package let tool: String
    package let command: [String]
    package let environment: [String: String]
}

/// One listed session. A runtime binds only to the single active entry naming its PID, so a
/// server hosting several sessions stays unbound.
package struct RuntimeSession: Equatable, Sendable {
    package let runtimePID: Int32
    /// Normalized lowercase UUID, or nil when the listed value is not one.
    package let sessionID: String?
    package let active: Bool
}

enum RuntimeObservation: Hashable, Sendable {
    case openFilePaths, listeningSockets
}

struct RuntimeObservations: Sendable {
    var openFilePaths: [String] = []
    var listeningSockets: [String] = []
}

struct RuntimeEvidence: Sendable {
    var writerThreadIDs: [String] = []
    var listeningSockets: [String] = []
}

enum RuntimeLink: Sendable {
    case writerThread(String)
    case listeningSocket(String)

    func matches(_ metadata: ProcessMetadata) -> Bool {
        switch self {
        case .writerThread(let id): metadata.writerThreadIDs.contains(id)
        case .listeningSocket(let path): metadata.listeningSockets.contains(path)
        }
    }
}

enum AttributionAdapterError: Error, Equatable {
    case duplicateProvider(AgentProvider)
    case malformedMarker
    case markerProviderMismatch
}

enum MarkerEnvironment {
    static func uuid(_ key: String, in environment: [String: Set<String>]) throws -> String? {
        guard let values = environment[key], !values.isEmpty else { return nil }
        let normalized = try Set(
            values.map { value in
                guard let uuid = UUID(uuidString: value) else {
                    throw AttributionAdapterError.malformedMarker
                }
                return uuid.uuidString.lowercased()
            })
        guard normalized.count == 1 else { throw AttributionAdapterError.malformedMarker }
        return normalized.first
    }
}

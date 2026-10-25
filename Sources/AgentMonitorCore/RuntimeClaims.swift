struct RuntimeClaims: Sendable {
    let executable: String
    private let adapters: [any AgentAttributionAdapter]

    init(executable: String, adapters: [any AgentAttributionAdapter]) {
        self.executable = executable
        self.adapters = adapters
    }

    func plan(invokedAs invocation: String? = nil) -> RuntimeObservationPlan {
        guard let invocation else { return RuntimeObservationPlan(adapters) }
        return RuntimeObservationPlan(
            adapters.filter { $0.acceptsRuntimeInvocation(invocation, executable: executable) })
    }
}

struct RuntimeObservationPlan: Sendable {
    private let adapters: [any AgentAttributionAdapter]

    init(_ adapters: [any AgentAttributionAdapter]) { self.adapters = adapters }

    var isRuntime: Bool { !adapters.isEmpty }
    var providers: Set<AgentProvider> { Set(adapters.map(\.provider)) }
    var requests: Set<RuntimeObservation> { Set(adapters.flatMap(\.runtimeObservations)) }

    func evidence(from observations: RuntimeObservations) -> RuntimeEvidence {
        var writers: Set<String> = []
        var listeners: Set<String> = []
        for adapter in adapters {
            let allowed = RuntimeObservations(
                openFilePaths: adapter.runtimeObservations.contains(.openFilePaths)
                    ? observations.openFilePaths : [],
                listeningSockets: adapter.runtimeObservations.contains(.listeningSockets)
                    ? observations.listeningSockets : [])
            let evidence = adapter.runtimeEvidence(from: allowed)
            writers.formUnion(evidence.writerThreadIDs)
            listeners.formUnion(evidence.listeningSockets)
        }
        return RuntimeEvidence(writerThreadIDs: writers.sorted(), listeningSockets: listeners.sorted())
    }
}

struct RuntimeClaimsCache: Sendable {
    private let adapters: AttributionAdapters
    private let maximumEntries: Int
    private let maximumKeyBytes: Int
    private var entries: [String: RuntimeClaims] = [:]
    private var insertionOrder: [String] = []
    private(set) var retainedKeyBytes = 0

    var retainedEntryCount: Int { entries.count }

    init(
        adapters: AttributionAdapters = .builtIn, maximumEntries: Int = 256,
        maximumKeyBytes: Int = 65_536
    ) {
        precondition(maximumEntries >= 0 && maximumKeyBytes >= 0)
        self.adapters = adapters
        self.maximumEntries = maximumEntries
        self.maximumKeyBytes = maximumKeyBytes
    }

    mutating func claims(for executable: String) -> RuntimeClaims {
        if let cached = entries[executable] {
            // Swift String keys use canonical equivalence; adapters receive the observed spelling
            // under the attribution contract, so a different UTF-8 spelling must be recognized fresh.
            guard cached.executable.utf8.elementsEqual(executable.utf8) else {
                return adapters.runtimeClaims(for: executable)
            }
            return cached
        }
        let claims = adapters.runtimeClaims(for: executable)
        let bytes = executable.utf8.count
        guard maximumEntries > 0, executable.hasPrefix("/"), bytes <= maximumKeyBytes else {
            return claims
        }
        while entries.count >= maximumEntries || bytes > maximumKeyBytes - retainedKeyBytes {
            let oldest = insertionOrder.removeFirst()
            if let removed = entries.removeValue(forKey: oldest) {
                retainedKeyBytes -= removed.executable.utf8.count
            }
        }
        entries[executable] = claims
        insertionOrder.append(executable)
        retainedKeyBytes += bytes
        return claims
    }
}

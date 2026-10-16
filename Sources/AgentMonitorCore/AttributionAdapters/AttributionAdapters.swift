import Foundation

package struct AttributionAdapters: Sendable {
    private let adapters: [any AgentAttributionAdapter]

    package static let builtIn = Self(codex: CodexAttributionAdapter(), claude: ClaudeAttributionAdapter())

    private init(codex: CodexAttributionAdapter, claude: ClaudeAttributionAdapter) {
        adapters = [codex, claude]
    }

    init(_ adapters: [any AgentAttributionAdapter]) throws {
        var providers: Set<AgentProvider> = []
        for adapter in adapters where !providers.insert(adapter.provider).inserted {
            throw AttributionAdapterError.duplicateProvider(adapter.provider)
        }
        self.adapters = adapters
    }

    var environmentKeys: Set<String> { Set(adapters.flatMap(\.environmentKeys)) }

    func runtimeProviders(for executable: String, invokedAs invocation: String? = nil) -> Set<AgentProvider> {
        Set(recognizing(executable, invokedAs: invocation).map(\.provider))
    }

    /// Narrows existing executable claims by `argv[0]` without repeating path recognition.
    func runtimeProviders(
        _ claims: Set<AgentProvider>, invokedAs invocation: String, executable: String
    ) -> Set<AgentProvider> {
        claims.filter { provider in
            adapter(for: provider)?.acceptsRuntimeInvocation(
                invocation, executable: executable)
                == true
        }
    }

    private func recognizing(_ executable: String, invokedAs invocation: String?)
        -> [any AgentAttributionAdapter]
    {
        adapters.filter { adapter in
            adapter.recognizesRuntime(executable)
                && invocation.map { adapter.acceptsRuntimeInvocation($0, executable: executable) } != false
        }
    }

    func runtimeProvider(for executable: String) -> AgentProvider? {
        let providers = runtimeProviders(for: executable)
        return providers.count == 1 ? providers.first : nil
    }

    func markers(in environment: [String: Set<String>]) throws -> [SessionMarker] {
        try adapters.compactMap { adapter in
            let allowed = environment.filter { adapter.environmentKeys.contains($0.key) }
            guard let marker = try adapter.marker(in: allowed) else { return nil }
            guard marker.provider == adapter.provider else {
                throw AttributionAdapterError.markerProviderMismatch
            }
            return marker
        }
    }

    func runtimeEvidence(
        for executable: String, invokedAs invocation: String? = nil,
        read: (Set<RuntimeObservation>) -> RuntimeObservations
    ) -> RuntimeEvidence {
        let recognized = recognizing(executable, invokedAs: invocation)
        guard !recognized.isEmpty else { return RuntimeEvidence() }
        let observations = read(Set(recognized.flatMap(\.runtimeObservations)))
        var writers: Set<String> = []
        var listeners: Set<String> = []
        for adapter in recognized {
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

    package func sessionRegistry(for provider: AgentProvider) -> SessionRegistryQuery? {
        adapter(for: provider)?.sessionRegistry
    }

    package func runtimeSessions(_ provider: AgentProvider, fromRegistry output: Data) throws
        -> [RuntimeSession]
    {
        try adapter(for: provider)?.runtimeSessions(fromRegistry: output) ?? []
    }

    private func adapter(for provider: AgentProvider) -> (any AgentAttributionAdapter)? {
        adapters.first { $0.provider == provider }
    }

    func runtimeLink(for marker: SessionMarker) -> RuntimeLink? {
        adapter(for: marker.provider)?.runtimeLink(for: marker)
    }

    func isSharedRuntime(_ process: HeavyProcess) -> Bool {
        guard process.attribution.runtime == process.process else { return false }
        guard let provider = process.attribution.provider else { return false }
        return adapter(for: provider)?.isSharedRuntime(process.attribution) == true
    }
}

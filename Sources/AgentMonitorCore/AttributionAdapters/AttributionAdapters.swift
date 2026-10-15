struct AttributionAdapters: Sendable {
    private let adapters: [any AgentAttributionAdapter]

    static let builtIn = Self(codex: CodexAttributionAdapter(), claude: ClaudeAttributionAdapter())

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

    func runtimeProviders(for executable: String) -> Set<AgentProvider> {
        Set(adapters.filter { $0.recognizesRuntime(executable) }.map(\.provider))
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
        for executable: String, read: (Set<RuntimeObservation>) -> RuntimeObservations
    ) -> RuntimeEvidence {
        let recognized = adapters.filter { $0.recognizesRuntime(executable) }
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

    func runtimeLink(for marker: SessionMarker) -> RuntimeLink? {
        adapters.first { $0.provider == marker.provider }?.runtimeLink(for: marker)
    }

    func isSharedRuntime(_ process: HeavyProcess) -> Bool {
        guard process.attribution.runtime == process.process else { return false }
        return adapters.first { $0.provider == process.attribution.provider }?
            .isSharedRuntime(process.attribution) == true
    }
}

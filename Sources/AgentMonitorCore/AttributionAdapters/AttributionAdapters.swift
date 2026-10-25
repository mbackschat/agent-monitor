import Foundation

package struct AttributionAdapters: Sendable {
    private let adapters: [any AgentAttributionAdapter]
    private let environmentKeyDeclarations: [Set<String>]
    let environmentKeys: Set<String>
    let environmentKeyBytes: [(name: String, bytes: [UInt8])]

    package static let builtIn = Self(codex: CodexAttributionAdapter(), claude: ClaudeAttributionAdapter())

    private init(codex: CodexAttributionAdapter, claude: ClaudeAttributionAdapter) {
        self.init(preparing: [codex, claude])
    }

    init(_ adapters: [any AgentAttributionAdapter]) throws {
        var providers: Set<AgentProvider> = []
        for adapter in adapters where !providers.insert(adapter.provider).inserted {
            throw AttributionAdapterError.duplicateProvider(adapter.provider)
        }
        self.init(preparing: adapters)
    }

    private init(preparing adapters: [any AgentAttributionAdapter]) {
        let declarations = adapters.map(\.environmentKeys)
        let keys = Set(declarations.flatMap { $0 })
        self.adapters = adapters
        environmentKeyDeclarations = declarations
        environmentKeys = keys
        environmentKeyBytes = keys.map { (name: $0, bytes: Array($0.utf8)) }
    }

    func runtimeClaims(for executable: String) -> RuntimeClaims {
        RuntimeClaims(executable: executable, adapters: adapters.filter { $0.recognizesRuntime(executable) })
    }

    func runtimeProviders(for executable: String, invokedAs invocation: String? = nil) -> Set<AgentProvider> {
        runtimeClaims(for: executable).plan(invokedAs: invocation).providers
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

    func workloadInvocationName(
        _ claims: Set<AgentProvider>, invokedAs invocation: String, executable: String
    ) -> String? {
        let names = Set(
            claims.compactMap {
                adapter(for: $0)?.workloadInvocationName(invocation, executable: executable)
            })
        return names.count == 1 ? names.first : nil
    }

    func runtimeProvider(for executable: String) -> AgentProvider? {
        let providers = runtimeProviders(for: executable)
        return providers.count == 1 ? providers.first : nil
    }

    func markers(in environment: [String: Set<String>]) throws -> [SessionMarker] {
        try zip(adapters, environmentKeyDeclarations).compactMap { adapter, keys in
            let allowed = environment.filter { keys.contains($0.key) }
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
        let plan = runtimeClaims(for: executable).plan(invokedAs: invocation)
        guard plan.isRuntime else { return RuntimeEvidence() }
        return plan.evidence(from: read(plan.requests))
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

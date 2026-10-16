import Foundation

public struct Monitor: Sendable {
    private struct Node: Sendable {
        var sample: ProcessSample
        var parent: ProcessIdentity?
        var metadata = ProcessMetadata(status: .unavailable)
        var cpuContribution: CPUContribution?
        var cpuPercent: Double? { cpuContribution?.cpuPercent }
        /// Claims from the executable path, kept for the lifetime; `runtimeProviders` may narrow
        /// them once `argv[0]` has been read.
        var recognizedProviders: Set<AgentProvider>
        var runtimeProviders: Set<AgentProvider>

        init(sample: ProcessSample, recognizedProviders: Set<AgentProvider>) {
            self.sample = sample
            self.recognizedProviders = recognizedProviders
            runtimeProviders = recognizedProviders
        }
    }

    private var nodes: [ProcessIdentity: Node] = [:]
    private var previousListing: Double?
    private var previousHostCounters: HostCPUCounters?
    private var previousScanSeconds: Double?
    private var live: Set<ProcessIdentity> = []
    private var runtimes: [AgentProvider: Set<ProcessIdentity>] = [:]
    /// Sessions that runtime lifetimes host according to their harness's latest listing.
    private var listedSessions: [ProcessIdentity: String] = [:]
    private let adapters: AttributionAdapters

    public init() { adapters = .builtIn }

    init(adapters: AttributionAdapters) { self.adapters = adapters }

    @discardableResult public mutating func ingest(_ snapshot: ProcessSnapshot) -> CPUAccounting {
        ingest(snapshot.samples, listedAt: snapshot.listedAt)
        let measured = live.compactMap { nodes[$0]?.cpuPercent }
        defer {
            previousHostCounters = snapshot.hostCounters
            previousScanSeconds = snapshot.scanSeconds
        }
        return CPUAccounting(
            hostBusyPercent: snapshot.hostCounters?.busyPercent(since: previousHostCounters),
            logicalCPUCount: snapshot.logicalCPUCount,
            measuredUserPercent: measured.reduce(0, +), unmeasuredLifetimeCount: live.count - measured.count,
            previousScanSeconds: previousScanSeconds)
    }

    public mutating func ingest(_ samples: [ProcessSample], listedAt: Double? = nil) {
        let byPID = Dictionary(
            samples.map { ($0.identity.pid, $0.identity) }, uniquingKeysWith: { _, new in new })
        let previouslyLive = live
        defer { previousListing = listedAt }
        live = Set(samples.map(\.identity))
        for sample in samples {
            var node =
                nodes[sample.identity]
                ?? Node(
                    sample: sample, recognizedProviders: adapters.runtimeProviders(for: sample.executable))
            let previous = previouslyLive.contains(sample.identity) ? nodes[sample.identity]?.sample : nil
            node.cpuContribution = nil
            if let previous, let oldCPU = previous.cpuSeconds, let newCPU = sample.cpuSeconds,
                sample.sampledAt > previous.sampledAt, newCPU >= oldCPU
            {
                node.cpuContribution = CPUContribution(
                    cpuSeconds: newCPU - oldCPU, observedSeconds: sample.sampledAt - previous.sampledAt)
            } else if previous == nil, let previousListing, let birth = sample.startedAt,
                birth > previousListing, birth <= sample.sampledAt,
                sample.sampledAt > previousListing, let cpu = sample.cpuSeconds, cpu >= 0
            {
                node.cpuContribution = CPUContribution(
                    cpuSeconds: cpu, observedSeconds: sample.sampledAt - previousListing)
            }
            if node.sample.executable != sample.executable {
                node.metadata = ProcessMetadata(status: .unavailable)
                node.recognizedProviders = adapters.runtimeProviders(for: sample.executable)
                node.runtimeProviders = node.recognizedProviders
                listedSessions[sample.identity] = nil
            }
            if let parent = byPID[sample.parentPID], parent != sample.identity,
                parent.startMicroseconds <= sample.identity.startMicroseconds
            {
                node.parent = parent
            }
            node.sample = sample
            nodes[sample.identity] = node
        }
        runtimes = [:]
        for identity in live { indexRuntime(identity) }
        listedSessions = listedSessions.filter { live.contains($0.key) }

        // Retain departed ancestors only while a live descendant needs them; see
        // docs/research/macos-process-attribution.md for reparenting and PID reuse.
        var retained = live
        for identity in live {
            retained.formUnion(chain(from: identity))
        }
        nodes = nodes.filter { retained.contains($0.key) }
    }

    public mutating func enrich(_ metadata: ProcessMetadata, for identity: ProcessIdentity) {
        guard var node = nodes[identity] else { return }
        var updated = metadata
        switch metadata.status {
        case .unavailable, .notObserved:
            if updated.markers.isEmpty { updated.markers = node.metadata.markers }
        case .markerRead, .malformed:
            break
        }
        updated.invocation = updated.invocation ?? node.metadata.invocation
        node.metadata = updated
        let providers =
            updated.invocation.map {
                adapters.runtimeProviders(
                    node.recognizedProviders, invokedAs: $0, executable: node.sample.executable)
            } ?? node.recognizedProviders
        let changed = providers != node.runtimeProviders
        node.runtimeProviders = providers
        nodes[identity] = node
        if changed {
            for provider in runtimes.keys { runtimes[provider]?.remove(identity) }
            listedSessions[identity] = nil
            indexRuntime(identity)
        }
    }

    /// Live runtimes behind `findings` whose session only their harness's own listing can supply,
    /// by provider. Bound runtimes are included so a listing can follow `/clear` or `/resume`.
    public func sessionRegistryRuntimes(in findings: [HeavyProcess]) -> [AgentProvider: Set<ProcessIdentity>]
    {
        var result: [AgentProvider: Set<ProcessIdentity>] = [:]
        for finding in findings {
            let owner = finding.attribution
            switch owner.evidence {
            case .runtimeOnly, .sessionRegistry:
                guard let provider = owner.provider, let runtime = owner.runtime, live.contains(runtime),
                    adapters.sessionRegistry(for: provider) != nil
                else { continue }
                result[provider, default: []].insert(runtime)
            case .marker, .inheritedMarker, .writerLock, .ambiguous, .unknown:
                continue
            }
        }
        return result
    }

    package func sessionRegistry(for provider: AgentProvider) -> SessionRegistryQuery? {
        adapters.sessionRegistry(for: provider)
    }

    /// Replaces the provider's bindings with its listing; nil (a failed listing) or an unparsable
    /// one removes them. Each live runtime binds only to the single active entry naming its PID.
    @discardableResult package mutating func bindSessions(
        _ output: Data?, provider: AgentProvider, restrictingTo verified: Set<ProcessIdentity>? = nil
    ) -> Bool {
        let parsed = output.flatMap { try? adapters.runtimeSessions(provider, fromRegistry: $0) }
        let sessions = parsed ?? []
        let byPID = Dictionary(grouping: sessions, by: \.runtimePID)
        for runtime in runtimes[provider] ?? [] {
            let listed = byPID[runtime.pid] ?? []
            if verified?.contains(runtime) != false,
                listed.count == 1, let session = listed.first, session.active, let id = session.sessionID
            {
                listedSessions[runtime] = id
            } else {
                listedSessions[runtime] = nil
            }
        }
        return parsed != nil
    }

    /// Only live processes claimed by exactly one provider can be detached-runtime candidates.
    private mutating func indexRuntime(_ identity: ProcessIdentity) {
        guard live.contains(identity), let providers = nodes[identity]?.runtimeProviders,
            providers.count == 1,
            let provider = providers.first
        else { return }
        runtimes[provider, default: []].insert(identity)
    }

    /// Reads metadata for the processes, their ancestry and, in a second pass, the runtimes a
    /// detached session marker points to, which are only known once the marker has been read.
    /// Each process is read once.
    public mutating func enrich(
        for identities: [ProcessIdentity], using metadata: (ProcessSample) throws -> ProcessMetadata
    ) rethrows {
        var enriched: Set<ProcessIdentity> = []
        for _ in 1...2 {
            for sample in enrichmentTargets(for: identities) where enriched.insert(sample.identity).inserted {
                enrich(try metadata(sample), for: sample.identity)
            }
        }
    }

    public mutating func enrich(
        thresholds: Thresholds, using metadata: (ProcessSample) -> ProcessMetadata
    ) {
        enrich(for: heavyIdentities(thresholds: thresholds), using: metadata)
    }

    public func enrichmentTargets(thresholds: Thresholds = Thresholds()) -> [ProcessSample] {
        enrichmentTargets(for: heavyIdentities(thresholds: thresholds))
    }

    /// Ancestry chains, plus the runtimes a detached session marker may point to. Those candidates
    /// appear only once the marker has been read, so callers enrich in a second pass.
    public func enrichmentTargets(for identities: some Sequence<ProcessIdentity>) -> [ProcessSample] {
        var targets: Set<ProcessIdentity> = []
        for identity in identities {
            targets.formUnion(chain(from: identity))
            let walk = walk(from: identity)
            if walk.runtime == nil, let marker = walk.marker, let owner = walk.markerOwner {
                targets.formUnion(detachedRuntimeCandidates(marker, owner: owner))
            }
        }
        return targets.intersection(live).compactMap { nodes[$0]?.sample }
    }

    public func findings(
        thresholds: Thresholds = Thresholds(), scope: ProcessScope = .allProcesses
    ) -> [HeavyProcess] {
        heavyIdentities(thresholds: thresholds).compactMap { identity in
            finding(for: identity)
        }.filter { scope.includes($0.attribution) }.sorted {
            if $0.cpuPercent != $1.cpuPercent { return ($0.cpuPercent ?? -1) > ($1.cpuPercent ?? -1) }
            if $0.footprintBytes != $1.footprintBytes {
                return ($0.footprintBytes ?? 0) > ($1.footprintBytes ?? 0)
            }
            return $0.process.pid < $1.process.pid
        }
    }

    /// The accepted interval's numerator and measured duration, before percentage rounding.
    /// Absent lifetimes cannot expose counters retained solely for ancestry.
    public func cpuContribution(for identity: ProcessIdentity) -> CPUContribution? {
        guard live.contains(identity) else { return nil }
        return nodes[identity]?.cpuContribution
    }

    public func agentLoad() -> AgentLoadSummary {
        AgentLoadSummary(processes: live.compactMap { finding(for: $0) })
    }

    /// Inspect a live process independently of display thresholds.
    public func finding(for identity: ProcessIdentity) -> HeavyProcess? {
        guard live.contains(identity), let node = nodes[identity] else { return nil }
        return HeavyProcess(
            process: identity, executable: node.sample.executable, name: node.sample.name,
            cpuPercent: node.cpuPercent, footprintBytes: node.sample.footprintBytes,
            cwd: node.metadata.cwd, command: node.metadata.command, metadataStatus: node.metadata.status,
            attribution: resolve(identity).attribution)
    }

    /// The session marker behind a live process's resolved attribution. Action routing reads
    /// provider details such as Claude's inbox here so they stay out of JSONL snapshots.
    public func attributingMarker(for identity: ProcessIdentity) -> SessionMarker? {
        guard live.contains(identity) else { return nil }
        let resolved = resolve(identity)
        switch resolved.attribution.evidence {
        case .marker, .inheritedMarker: return resolved.marker
        case .writerLock, .sessionRegistry, .runtimeOnly, .ambiguous, .unknown: return nil
        }
    }

    private func heavyIdentities(thresholds: Thresholds) -> [ProcessIdentity] {
        live.filter { identity in
            guard let node = nodes[identity] else { return false }
            return node.cpuPercent.map { $0 > thresholds.cpuPercent } == true
                || node.sample.footprintBytes.map { $0 > thresholds.memoryBytes } == true
        }
    }

    private func chain(from identity: ProcessIdentity) -> [ProcessIdentity] {
        var path: [ProcessIdentity] = []
        var visited: Set<ProcessIdentity> = []
        var next: ProcessIdentity? = identity
        while let current = next, let node = nodes[current], visited.insert(current).inserted {
            path.append(current)
            next = node.parent
        }
        return path
    }

    /// A later runtime cannot explain launch origin, even if it resumed the same thread or
    /// reused an inbox path; see docs/architecture.md, attribution evidence and inspection scope.
    private func detachedRuntimeCandidates(_ marker: SessionMarker, owner: ProcessIdentity)
        -> [ProcessIdentity]
    {
        guard adapters.runtimeLink(for: marker) != nil else { return [] }
        return (runtimes[marker.provider] ?? []).filter { $0.startMicroseconds <= owner.startMicroseconds }
    }

    /// What walking up from a process found before the first agent runtime.
    private struct Walk {
        var path: [ProcessIdentity] = []
        var marker: SessionMarker?
        var markerOwner: ProcessIdentity?
        var runtime: Node?
        var unresolvedMetadata = false
    }

    private func resolve(_ identity: ProcessIdentity) -> (
        attribution: Attribution, marker: SessionMarker?, markerOwner: ProcessIdentity?
    ) {
        var walk = self.walk(from: identity)
        if walk.runtime == nil, let marker = walk.marker, let owner = walk.markerOwner {
            walk.runtime = detachedRuntime(for: marker, owner: owner)
        }
        let runtime = walk.runtime
        let candidates = Array(Set(runtime?.metadata.writerThreadIDs ?? [])).sorted()
        let runtimeProviders = runtime?.runtimeProviders ?? []
        let runtimeProvider = runtimeProviders.count == 1 ? runtimeProviders.first : nil
        let providerConflict =
            runtimeProviders.count > 1
            || (walk.marker != nil && runtimeProvider != nil && walk.marker?.provider != runtimeProvider)
        let (evidence, thread) = classify(
            walk, uncertain: providerConflict || walk.unresolvedMetadata, of: identity, candidates: candidates
        )
        let attribution = Attribution(
            provider: providerConflict ? nil : walk.marker?.provider ?? runtimeProvider,
            evidence: evidence,
            context: runtime.map {
                $0.sample.terminal == nil && $0.sample.terminalDevice == nil ? .nonterminal : .terminal
            } ?? .unverified,
            threadID: thread,
            rootSessionID: providerConflict || walk.unresolvedMetadata ? nil : walk.marker?.rootSessionID,
            runtime: runtime?.sample.identity,
            terminal: runtime?.metadata.terminal ?? runtime?.sample.terminal,
            runtimeDirectory: runtime?.metadata.cwd, candidateThreadIDs: candidates, ancestry: walk.path
        )
        return (attribution, walk.marker, walk.markerOwner)
    }

    private func walk(from identity: ProcessIdentity) -> Walk {
        var walk = Walk()
        let ancestors = chain(from: identity)
        let nearestProviders =
            ancestors.lazy.compactMap { self.nodes[$0] }
            .map(\.runtimeProviders).first { !$0.isEmpty } ?? []
        let nearest = nearestProviders.count == 1 ? nearestProviders.first : nil
        for key in ancestors {
            guard let node = nodes[key] else { continue }
            walk.path.append(key)
            let providers = node.runtimeProviders
            if !providers.isEmpty {
                walk.runtime = node
                if providers.count > 1 { walk.unresolvedMetadata = true }
                break
            }
            guard walk.marker == nil else { continue }
            if node.metadata.status == .malformed { walk.unresolvedMetadata = true }
            let markers = node.metadata.markers
            guard !markers.isEmpty else { continue }
            // Nested agents leave both markers; the inner agent is the nearest runtime.
            if let value = markers.count == 1 ? markers[0] : markers.first(where: { $0.provider == nearest })
            {
                walk.marker = value
                walk.markerOwner = key
            } else {
                walk.unresolvedMetadata = true
            }
        }
        return walk
    }

    /// Adapters supply the exact link; the host requires one live, lifetime-compatible match
    /// (docs/architecture.md#agent-attribution-adapters).
    private func detachedRuntime(for marker: SessionMarker, owner: ProcessIdentity) -> Node? {
        guard let link = adapters.runtimeLink(for: marker) else { return nil }
        let owners = detachedRuntimeCandidates(marker, owner: owner).compactMap { nodes[$0] }
            .filter { link.matches($0.metadata) }
        return owners.count == 1 ? owners[0] : nil
    }

    private func classify(
        _ walk: Walk, uncertain: Bool, of identity: ProcessIdentity, candidates: [String]
    ) -> (AttributionEvidence, String?) {
        if uncertain { return (.ambiguous, nil) }
        if let marker = walk.marker {
            return (walk.markerOwner == identity ? .marker : .inheritedMarker, marker.threadID)
        }
        switch candidates.count {
        case 1: return (.writerLock, candidates[0])
        case 2...: return (.ambiguous, nil)
        default:
            guard let runtime = walk.runtime else { return (.unknown, nil) }
            if let session = listedSessions[runtime.sample.identity] { return (.sessionRegistry, session) }
            return (.runtimeOnly, nil)
        }
    }
}

public enum ResourceMath {
    public static func seconds(ticks: UInt64, numerator: UInt32, denominator: UInt32) -> Double {
        precondition(denominator != 0)
        return Double(ticks) * Double(numerator) / Double(denominator) / 1_000_000_000
    }
}

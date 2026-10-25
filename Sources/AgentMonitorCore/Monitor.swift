import Foundation

public struct Monitor: Sendable {
    private struct Node: Sendable {
        var sample: ProcessSample
        var execution: ObservedExecution
        var executionObservedAt: Double?
        var invocationName: String?
        var parent: ProcessIdentity?
        var metadata = ProcessMetadata(status: .unavailable)
        var markerObservedAt: Double?
        var metadataObservedAt: Double?
        var cpuContribution: CPUContribution?
        var cpuPercent: Double? {
            guard let cpuContribution, !cpuContribution.spansMissingScans else { return nil }
            return cpuContribution.cpuPercent
        }
        /// Claims from the executable path, kept for the lifetime; `runtimeProviders` may narrow
        /// them once `argv[0]` has been read.
        var recognizedProviders: Set<AgentProvider>
        var runtimeProviders: Set<AgentProvider>

        init(sample: ProcessSample, recognizedProviders: Set<AgentProvider>) {
            self.sample = sample
            execution = ObservedExecution(sample)
            self.recognizedProviders = recognizedProviders
            runtimeProviders = recognizedProviders
        }

        struct Update {
            let previousParent: ProcessIdentity?
            let parent: ProcessIdentity?
            let invalidatesResolution: Bool
            let executed: Bool
            let touchesRuntime: Bool
        }

        mutating func update(
            _ next: ProcessSample, contribution: CPUContribution?, parent candidate: ProcessIdentity?,
            isNew: Bool, adapters: AttributionAdapters
        ) -> Update {
            let previousParent = parent
            let wasRuntime = !runtimeProviders.isEmpty
            let terminalChanged =
                sample.terminal != next.terminal || sample.terminalDevice != next.terminalDevice
            cpuContribution = contribution
            let executed = execution.update(next)
            if executed {
                executionObservedAt = next.sampledAt
                metadata = ProcessMetadata(status: .unavailable)
                invocationName = nil
                markerObservedAt = nil
                metadataObservedAt = nil
                recognizedProviders = adapters.runtimeProviders(for: next.executable)
                runtimeProviders = recognizedProviders
            }
            if let candidate, candidate != next.identity,
                candidate.startMicroseconds <= next.identity.startMicroseconds
            {
                parent = candidate
            }
            sample = next
            return Update(
                previousParent: previousParent, parent: parent,
                invalidatesResolution: isNew || executed || parent != previousParent || terminalChanged,
                executed: executed, touchesRuntime: wasRuntime || !runtimeProviders.isEmpty)
        }
    }

    private struct Resolution: Sendable {
        let attribution: Attribution
        let marker: SessionMarker?
        let detachedGeneration: UInt64?
    }
    private var nodes: [ProcessIdentity: Node] = [:]
    private var children: [ProcessIdentity: Set<ProcessIdentity>] = [:]
    private var resolutions: [ProcessIdentity: Resolution] = [:]
    private var detachedGeneration: UInt64 = 0

    private var counterLedger = CounterLedger()
    public private(set) var counterScan: CounterScan?
    private var previousHostCounters: HostCPUCounters?
    private var previousScanSeconds: Double?
    private var live: Set<ProcessIdentity> = []
    private var runtimes: [AgentProvider: Set<ProcessIdentity>] = [:]
    /// Sessions that runtime lifetimes host according to their harness's latest listing.
    private var listedSessions: [ProcessIdentity: String] = [:]
    private var listedSessionNames: [ProcessIdentity: String] = [:]
    private var registryObservedAt: [ProcessIdentity: Double] = [:]
    private let adapters: AttributionAdapters
    private let profile: PipelineProfile?

    public init() {
        adapters = .builtIn
        profile = nil
    }

    package init(profile: PipelineProfile?) {
        adapters = .builtIn
        self.profile = profile
    }

    init(adapters: AttributionAdapters) {
        self.adapters = adapters
        profile = nil
    }

    private mutating func advanceDetachedGeneration() {
        detachedGeneration += 1
        profile?.increment(.detachedGenerationChanges)
    }

    private mutating func invalidate(_ identity: ProcessIdentity) {
        var pending = [identity]
        var visited: Set<ProcessIdentity> = []
        while let next = pending.popLast() {
            guard visited.insert(next).inserted else { continue }
            resolutions[next] = nil
            pending.append(contentsOf: children[next] ?? [])
        }
    }

    private func cachedResolution(_ identity: ProcessIdentity) -> Resolution? {
        guard let value = resolutions[identity],
            value.detachedGeneration == nil || value.detachedGeneration == detachedGeneration
        else { return nil }
        return value
    }

    @discardableResult public mutating func ingest(_ snapshot: ProcessSnapshot) -> CPUAccounting {
        let accounting = counterLedger.ingest(
            snapshot.samples, listedAt: snapshot.listedAt, scanSeconds: snapshot.scanSeconds,
            source: snapshot)
        return ingest(snapshot, accounting: accounting)
    }

    @discardableResult mutating func ingest(_ snapshot: ProcessSnapshot, accounting: CounterScan)
        -> CPUAccounting
    {
        ingest(snapshot.samples, accounting: accounting)
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
        let accounting = counterLedger.ingest(samples, listedAt: listedAt)
        ingest(samples, accounting: accounting)
    }

    private mutating func ingest(_ samples: [ProcessSample], accounting: CounterScan) {
        counterScan = accounting
        let contributions = Dictionary(
            accounting.contributions.map { ($0.id.closing.process, $0) },
            uniquingKeysWith: { first, _ in first })
        let byPID = Dictionary(
            samples.map { ($0.identity.pid, $0.identity) }, uniquingKeysWith: { _, new in new })
        let previouslyLive = live
        live = Set(samples.map(\.identity))
        for identity in previouslyLive.subtracting(live) {
            resolutions[identity] = nil
            if nodes[identity]?.runtimeProviders.isEmpty == false { advanceDetachedGeneration() }
        }
        let adapters = self.adapters
        for sample in samples {
            let isNew = nodes.index(forKey: sample.identity) == nil
            let update = nodes[
                sample.identity,
                default: Node(
                    sample: sample, recognizedProviders: adapters.runtimeProviders(for: sample.executable))
            ].update(
                sample, contribution: contributions[sample.identity], parent: byPID[sample.parentPID],
                isNew: isNew, adapters: adapters)
            if update.executed {
                listedSessions[sample.identity] = nil
                listedSessionNames[sample.identity] = nil
            }
            if update.parent != update.previousParent {
                if let previousParent = update.previousParent {
                    children[previousParent]?.remove(sample.identity)
                    if children[previousParent]?.isEmpty == true { children[previousParent] = nil }
                }
                if let parent = update.parent { children[parent, default: []].insert(sample.identity) }
            }
            if update.invalidatesResolution { invalidate(sample.identity) }
            if (update.invalidatesResolution || !previouslyLive.contains(sample.identity))
                && update.touchesRuntime
            {
                advanceDetachedGeneration()
            }
        }
        runtimes = [:]
        for identity in live { indexRuntime(identity) }
        for identity in listedSessions.keys where !live.contains(identity) {
            listedSessions[identity] = nil
            listedSessionNames[identity] = nil
            invalidate(identity)
            advanceDetachedGeneration()
        }
        registryObservedAt = registryObservedAt.filter { live.contains($0.key) }

        // Retain departed ancestors only while a live descendant needs them; see
        // docs/research/macos-process-attribution.md for reparenting and PID reuse.
        var retained = live
        for identity in live {
            var next = nodes[identity]?.parent
            while let ancestor = next, retained.insert(ancestor).inserted {
                next = nodes[ancestor]?.parent
            }
        }
        let departed = nodes.keys.filter { !retained.contains($0) }
        for identity in departed {
            if let parent = nodes[identity]?.parent {
                children[parent]?.remove(identity)
                if children[parent]?.isEmpty == true { children[parent] = nil }
            }
            children[identity] = nil
            resolutions[identity] = nil
            nodes[identity] = nil
        }
    }

    public mutating func enrich(
        _ metadata: ProcessMetadata, for identity: ProcessIdentity,
        observedAt: Double? = nil, launchObservedAt: Double? = nil, requestedAt: Double? = nil
    ) {
        guard var node = nodes[identity] else { return }
        let markerTime = launchObservedAt ?? observedAt
        if let boundary = node.executionObservedAt,
            [requestedAt, observedAt, markerTime].compactMap({ $0 }).contains(where: { $0 < boundary })
        {
            return
        }
        let olderMarker =
            markerTime.flatMap { incoming in node.markerObservedAt.map { incoming < $0 } } ?? false
        let olderMetadata =
            observedAt.flatMap { incoming in node.metadataObservedAt.map { incoming < $0 } } ?? false
        var updated = olderMetadata ? node.metadata : metadata
        if !olderMetadata { node.metadataObservedAt = observedAt }
        // A process may overwrite its argument area without exec. Empty parser reads keep launch
        // markers until a polling-visible exec boundary; older async evidence cannot cross that boundary.
        // See architecture's attribution contract and the parser/exec regression tests.
        if olderMarker {
            updated.markers = node.metadata.markers
        } else {
            switch metadata.status {
            case .unavailable where metadata.markers.isEmpty, .truncated where metadata.markers.isEmpty,
                .notObserved where metadata.markers.isEmpty:
                updated.markers = node.metadata.markers
            case .unavailable, .notObserved, .markerRead, .malformed, .truncated:
                updated.markers = metadata.markers
                node.markerObservedAt = markerTime
            }
        }
        updated.invocation = updated.invocation ?? node.metadata.invocation
        let metadataChanged = node.metadata != updated
        node.metadata = updated
        node.invocationName = updated.invocation.flatMap {
            adapters.workloadInvocationName(
                node.recognizedProviders, invokedAs: $0, executable: node.sample.executable)
        }
        let providers =
            updated.invocation.map {
                adapters.runtimeProviders(
                    node.recognizedProviders, invokedAs: $0, executable: node.sample.executable)
            } ?? node.recognizedProviders
        let changed = providers != node.runtimeProviders
        if metadataChanged || changed {
            invalidate(identity)
            if !node.runtimeProviders.isEmpty || !providers.isEmpty { advanceDetachedGeneration() }
        }
        node.runtimeProviders = providers
        nodes[identity] = node
        if changed {
            for provider in runtimes.keys { runtimes[provider]?.remove(identity) }
            listedSessions[identity] = nil
            listedSessionNames[identity] = nil
            indexRuntime(identity)
        }
    }

    /// Live runtimes behind `findings` whose session only their harness's own listing can supply,
    /// by provider. Bound runtimes are included so a listing can follow `/clear` or `/resume`.
    public func sessionRegistryRuntimes(
        in findings: [HeavyProcess], excludingChildrenOf collectorPID: Int32? = nil
    ) -> [AgentProvider: Set<ProcessIdentity>] {
        var result: [AgentProvider: Set<ProcessIdentity>] = [:]
        var checked: [AgentProvider: Set<ProcessIdentity>] = [:]
        for finding in findings {
            let owner = finding.attribution
            switch owner.evidence {
            case .runtimeOnly, .sessionRegistry:
                guard let provider = owner.provider, let runtime = owner.runtime, live.contains(runtime),
                    adapters.sessionRegistry(for: provider) != nil
                else { continue }
                guard checked[provider, default: []].insert(runtime).inserted else { continue }
                // A provider CLI spawned by the collector must not trigger its next listing.
                // The 2026-10-24 live audit observed 12 helpers and 12 listings in six seconds.
                if let collectorPID {
                    profile?.increment(.registryAncestorChecks)
                    if chain(from: runtime).contains(where: {
                        nodes[$0]?.sample.parentPID == collectorPID
                    }) {
                        continue
                    }
                }
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
        _ output: Data?, provider: AgentProvider, restrictingTo verified: Set<ProcessIdentity>? = nil,
        observedAt: Double? = nil, requestedAt: [ProcessIdentity: Double]? = nil
    ) -> Bool {
        let parsed = output.flatMap { try? adapters.runtimeSessions(provider, fromRegistry: $0) }
        let sessions = parsed ?? []
        let byPID = Dictionary(grouping: sessions, by: \.runtimePID)
        for runtime in runtimes[provider] ?? [] {
            if let boundary = nodes[runtime]?.executionObservedAt,
                [requestedAt?[runtime], observedAt].compactMap({ $0 }).contains(where: { $0 < boundary })
            {
                continue
            }
            let previous = listedSessions[runtime]
            let listed = byPID[runtime.pid] ?? []
            if verified?.contains(runtime) != false,
                listed.count == 1, let session = listed.first, session.active, let id = session.sessionID
            {
                listedSessions[runtime] = id
                listedSessionNames[runtime] = session.name
                registryObservedAt[runtime] = observedAt
            } else {
                listedSessions[runtime] = nil
                listedSessionNames[runtime] = nil
                registryObservedAt[runtime] = nil
            }
            if listedSessions[runtime] != previous {
                invalidate(runtime)
                advanceDetachedGeneration()
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

    /// Resolution depends on graph/metadata changes, not new counter or footprint values.
    /// Window collection needs every row but defers display ordering to window projection.
    mutating func accountingFindings(sorted: Bool = false) -> [HeavyProcess] {
        var misses: UInt64 = 0
        var rows: [HeavyProcess] = []
        rows.reserveCapacity(live.count)
        for identity in live {
            guard let node = nodes[identity] else { continue }
            let resolution: Resolution
            if let cached = cachedResolution(identity) {
                resolution = cached
            } else {
                resolution = resolveUncached(identity)
                resolutions[identity] = resolution
                misses += 1
            }
            rows.append(finding(node, owner: resolution.attribution))
        }
        profile?.increment(.resolutionMisses, by: misses)
        profile?.increment(.resolutionHits, by: UInt64(live.count) - misses)
        return sorted ? rows.sorted(by: Self.precedes) : rows
    }

    public func findings(
        thresholds: Thresholds = Thresholds(), scope: ProcessScope = .allProcesses
    ) -> [HeavyProcess] {
        heavyIdentities(thresholds: thresholds).compactMap { identity in
            finding(for: identity)
        }.filter { scope.includes($0.attribution) }.sorted(by: Self.precedes)
    }

    private static func precedes(_ left: HeavyProcess, _ right: HeavyProcess) -> Bool {
        if left.cpuPercent != right.cpuPercent { return (left.cpuPercent ?? -1) > (right.cpuPercent ?? -1) }
        if left.footprintBytes != right.footprintBytes {
            return (left.footprintBytes ?? 0) > (right.footprintBytes ?? 0)
        }
        return left.process.pid < right.process.pid
    }

    /// Returns the interval closed by the current scan, including recovery across read gaps.
    /// A retained baseline alone is not new work; absent lifetimes therefore return nil.
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
        return finding(node, owner: resolve(identity).attribution)
    }

    private func finding(_ node: Node, owner: Attribution) -> HeavyProcess {
        let name = owner.runtime.flatMap { runtime -> String? in
            guard let provider = owner.provider, runtimes[provider]?.contains(runtime) == true,
                listedSessions[runtime] == owner.threadID, SessionCorroboration.isExact(owner)
            else { return nil }
            return listedSessionNames[runtime]
        }
        return HeavyProcess(
            process: node.sample.identity, executable: node.sample.executable, name: node.sample.name,
            cpuPercent: node.cpuPercent, footprintBytes: node.sample.footprintBytes,
            kernelPeakFootprintBytes: node.sample.kernelPeakFootprintBytes,
            cwd: node.metadata.cwd, command: node.metadata.command, metadataStatus: node.metadata.status,
            attribution: owner, sessionName: name, invocationName: node.invocationName)
    }

    /// The primary label's actual point-observation time, never a claim of interval support.
    /// Cached markers retain their original time under the resource-accounting contract.
    var agentRuntimeIdentities: Set<ProcessIdentity> {
        Set(live.filter { !(nodes[$0]?.runtimeProviders.isEmpty ?? true) })
    }

    func attributionObservationTimes(for findings: [HeavyProcess]? = nil) -> [ProcessIdentity: Double] {
        var result: [ProcessIdentity: Double] = [:]
        for row in findings ?? self.findings(scope: .allProcesses) {
            let id = row.process
            let owner = row.attribution
            switch owner.evidence {
            case .marker, .inheritedMarker:
                let source = owner.ancestry.first { ancestor in
                    nodes[ancestor]?.metadata.markers.contains {
                        $0.threadID == owner.threadID && $0.provider == owner.provider
                    } == true
                }
                result[id] = source.flatMap { nodes[$0]?.markerObservedAt }
            case .writerLock: result[id] = owner.runtime.flatMap { nodes[$0]?.metadataObservedAt }
            case .sessionRegistry: result[id] = owner.runtime.flatMap { registryObservedAt[$0] }
            case .runtimeOnly, .ambiguous, .unknown: break
            }
        }
        return result
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
            return thresholds.includes(cpu: node.cpuPercent, footprint: node.sample.footprintBytes)
        }
    }

    func chain(from identity: ProcessIdentity) -> [ProcessIdentity] {
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

    private func resolve(_ identity: ProcessIdentity) -> Resolution {
        cachedResolution(identity) ?? resolveUncached(identity)
    }

    private func resolveUncached(_ identity: ProcessIdentity) -> Resolution {
        var walk = self.walk(from: identity)
        let detached = walk.runtime == nil && walk.marker != nil
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
        return Resolution(
            attribution: attribution, marker: walk.marker,
            detachedGeneration: detached ? detachedGeneration : nil)
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

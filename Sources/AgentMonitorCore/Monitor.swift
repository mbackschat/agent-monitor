public struct Monitor: Sendable {
    private struct Node: Sendable {
        var sample: ProcessSample
        var parent: ProcessIdentity?
        var metadata = ProcessMetadata(status: .unavailable)
        var cpuPercent: Double?
    }

    private var nodes: [ProcessIdentity: Node] = [:]
    private var live: Set<ProcessIdentity> = []

    public init() {}

    public mutating func ingest(_ samples: [ProcessSample]) {
        let byPID = Dictionary(
            samples.map { ($0.identity.pid, $0.identity) }, uniquingKeysWith: { _, new in new })
        live = Set(samples.map(\.identity))
        for sample in samples {
            var node = nodes[sample.identity] ?? Node(sample: sample)
            let previous = nodes[sample.identity]?.sample
            node.cpuPercent = nil
            if let previous, let oldCPU = previous.cpuSeconds, let newCPU = sample.cpuSeconds,
                sample.sampledAt > previous.sampledAt, newCPU >= oldCPU
            {
                node.cpuPercent = 100 * (newCPU - oldCPU) / (sample.sampledAt - previous.sampledAt)
            }
            if node.sample.executable != sample.executable {
                node.metadata = ProcessMetadata(status: .unavailable)
            }
            if let parent = byPID[sample.parentPID], parent != sample.identity,
                parent.startMicroseconds <= sample.identity.startMicroseconds
            {
                node.parent = parent
            }
            node.sample = sample
            nodes[sample.identity] = node
        }

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
        node.metadata = updated
        nodes[identity] = node
    }

    /// Reads metadata for the processes, their ancestry and, in a second pass, the runtimes a
    /// detached Claude marker points to, which are only known once the marker has been read.
    /// Each process is read once.
    public mutating func enrich(
        for identities: [ProcessIdentity], using metadata: (ProcessSample) -> ProcessMetadata
    ) {
        var enriched: Set<ProcessIdentity> = []
        for _ in 1...2 {
            for sample in enrichmentTargets(for: identities) where enriched.insert(sample.identity).inserted {
                enrich(metadata(sample), for: sample.identity)
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

    /// Ancestry chains, plus the runtimes a detached Claude marker may point to. Those candidates
    /// appear only once the marker has been read, so callers enrich in a second pass.
    public func enrichmentTargets(for identities: some Sequence<ProcessIdentity>) -> [ProcessSample] {
        var targets: Set<ProcessIdentity> = []
        for identity in identities {
            targets.formUnion(chain(from: identity))
            let resolved = resolve(identity)
            if resolved.attribution.runtime == nil, let marker = resolved.marker,
                let owner = resolved.markerOwner
            {
                targets.formUnion(inboxCandidates(marker, owner: owner))
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
        case .writerLock, .runtimeOnly, .ambiguous, .unknown: return nil
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

    /// Live Claude runtimes that existed when the marker's process inherited it; a later start
    /// means a reused PID and therefore possibly a reused socket name.
    private func inboxCandidates(_ marker: SessionMarker, owner: ProcessIdentity) -> [ProcessIdentity] {
        guard marker.provider == .claude, marker.inboxSocket != nil else { return [] }
        return live.filter {
            nodes[$0]?.sample.runtimeProvider == .claude && $0.startMicroseconds <= owner.startMicroseconds
        }
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
            walk.runtime = inboxRuntime(for: marker, owner: owner)
        }
        let runtime = walk.runtime
        let candidates = Array(Set(runtime?.metadata.writerThreadIDs ?? [])).sorted()
        let providerConflict =
            walk.marker != nil && runtime?.sample.runtimeProvider != nil
            && walk.marker?.provider != runtime?.sample.runtimeProvider
        let (evidence, thread) = classify(
            walk, uncertain: providerConflict || walk.unresolvedMetadata, of: identity, candidates: candidates
        )
        let attribution = Attribution(
            provider: providerConflict ? nil : walk.marker?.provider ?? runtime?.sample.runtimeProvider,
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
        let nearest = ancestors.lazy.compactMap { self.nodes[$0]?.sample.runtimeProvider }.first
        for key in ancestors {
            guard let node = nodes[key] else { continue }
            walk.path.append(key)
            if node.sample.runtimeProvider != nil {
                walk.runtime = node
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

    /// A detached workload keeps the inbox path its runtime exported (docs/research/
    /// claude-session-messaging.md); the one live runtime still listening on it launched it.
    private func inboxRuntime(for marker: SessionMarker, owner: ProcessIdentity) -> Node? {
        guard let inbox = marker.inboxSocket else { return nil }
        let owners = inboxCandidates(marker, owner: owner).compactMap { nodes[$0] }
            .filter { $0.metadata.listeningSockets.contains(inbox) }
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
        default: return (walk.runtime == nil ? .unknown : .runtimeOnly, nil)
        }
    }
}

public enum ResourceMath {
    public static func seconds(ticks: UInt64, numerator: UInt32, denominator: UInt32) -> Double {
        precondition(denominator != 0)
        return Double(ticks) * Double(numerator) / Double(denominator) / 1_000_000_000
    }
}

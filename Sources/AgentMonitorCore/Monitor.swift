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
            updated.marker = metadata.marker ?? node.metadata.marker
        case .markerRead, .malformed:
            break
        }
        node.metadata = updated
        nodes[identity] = node
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

    private func resolve(_ identity: ProcessIdentity) -> (
        attribution: Attribution, marker: SessionMarker?, markerOwner: ProcessIdentity?
    ) {
        var path: [ProcessIdentity] = []
        var marker: SessionMarker?
        var markerOwner: ProcessIdentity?
        var runtime: Node?
        var malformedMetadata = false
        for key in chain(from: identity) {
            guard let node = nodes[key] else { continue }
            path.append(key)
            if node.sample.runtimeProvider != nil {
                runtime = node
                break
            }
            if marker == nil, node.metadata.status == .malformed { malformedMetadata = true }
            if marker == nil, let value = node.metadata.marker {
                marker = value
                markerOwner = key
            }
        }
        // A detached workload keeps the inbox path its runtime exported (docs/research/
        // claude-session-messaging.md); the one live runtime still listening on it launched it.
        if runtime == nil, let marker, let markerOwner, let inbox = marker.inboxSocket {
            let owners = inboxCandidates(marker, owner: markerOwner).compactMap { nodes[$0] }
                .filter { $0.metadata.listeningSockets.contains(inbox) }
            if owners.count == 1 { runtime = owners[0] }
        }
        let candidates = Array(Set(runtime?.metadata.writerThreadIDs ?? [])).sorted()
        let evidence: AttributionEvidence
        let thread: String?
        let providerConflict =
            marker != nil && runtime?.sample.runtimeProvider != nil
            && marker?.provider != runtime?.sample.runtimeProvider
        if providerConflict || malformedMetadata {
            evidence = .ambiguous
            thread = nil
        } else if let marker {
            evidence = markerOwner == identity ? .marker : .inheritedMarker
            thread = marker.threadID
        } else {
            switch candidates.count {
            case 1:
                evidence = .writerLock
                thread = candidates[0]
            case 2...:
                evidence = .ambiguous
                thread = nil
            default:
                evidence = runtime == nil ? .unknown : .runtimeOnly
                thread = nil
            }
        }
        let attribution = Attribution(
            provider: providerConflict ? nil : marker?.provider ?? runtime?.sample.runtimeProvider,
            evidence: evidence,
            context: runtime.map {
                $0.sample.terminal == nil && $0.sample.terminalDevice == nil ? .nonterminal : .terminal
            } ?? .unverified,
            threadID: thread,
            rootSessionID: providerConflict || malformedMetadata ? nil : marker?.rootSessionID,
            runtime: runtime?.sample.identity,
            terminal: runtime?.metadata.terminal ?? runtime?.sample.terminal,
            runtimeDirectory: runtime?.metadata.cwd, candidateThreadIDs: candidates, ancestry: path
        )
        return (attribution, marker, markerOwner)
    }
}

public enum ResourceMath {
    public static func seconds(ticks: UInt64, numerator: UInt32, denominator: UInt32) -> Double {
        precondition(denominator != 0)
        return Double(ticks) * Double(numerator) / Double(denominator) / 1_000_000_000
    }
}

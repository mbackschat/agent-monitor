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
        var identities: Set<ProcessIdentity> = []
        for identity in heavyIdentities(thresholds: thresholds) {
            identities.formUnion(chain(from: identity))
        }
        return identities.intersection(live).compactMap { nodes[$0]?.sample }
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
            attribution: attribute(identity))
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

    private func attribute(_ identity: ProcessIdentity) -> Attribution {
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
        return Attribution(
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
    }
}

public enum ResourceMath {
    public static func seconds(ticks: UInt64, numerator: UInt32, denominator: UInt32) -> Double {
        precondition(denominator != 0)
        return Double(ticks) * Double(numerator) / Double(denominator) / 1_000_000_000
    }
}

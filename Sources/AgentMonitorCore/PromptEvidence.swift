import Foundation

public struct PromptCaptureLimits: Sendable {
    public let attempts: Int
    public let bytes: Int
    public let bytesPerRead: Int
    public let elapsedSeconds: Double
    public let retainedDiscoveries: Int

    public init(
        attempts: Int = 16, bytes: Int = 1_048_576, bytesPerRead: Int = 65_536,
        elapsedSeconds: Double = 0.005, retainedDiscoveries: Int = 8_192
    ) {
        self.attempts = attempts
        self.bytes = bytes
        self.bytesPerRead = bytesPerRead
        self.elapsedSeconds = elapsedSeconds
        self.retainedDiscoveries = retainedDiscoveries
    }

    var isValid: Bool {
        attempts > 0 && bytes > 0 && bytesPerRead > 0 && retainedDiscoveries > 0
            && elapsedSeconds.isFinite && elapsedSeconds > 0
    }
}

public enum PromptEvidenceStatus: String, Sendable {
    case captured, unavailable, deferred, unsupported, truncated
}

/// A launch observation is point evidence. Neither a stable path nor successful capture
/// establishes execution continuity (docs/proposals/resource-accounting.md).
public struct PromptEvidence: Sendable {
    public let id: UUID
    public let process: ProcessIdentity
    public let discoveredAt: Double
    public let observedAt: Double?
    public let readSeconds: Double
    public let reservedBytes: Int
    public let status: PromptEvidenceStatus
    public let metadata: ProcessMetadata?
}

public struct PromptCaptureSummary: Equatable, Codable, Sendable {
    public let captured: Int
    public let unavailable: Int
    public let truncated: Int
    public let deferred: Int
    public let unsupported: Int
    public let reservedBytes: Int
    public let readSeconds: Double

    init(_ evidence: [PromptEvidence]) {
        captured = evidence.filter { $0.status == .captured }.count
        truncated = evidence.filter { $0.status == .truncated }.count
        unavailable = evidence.filter { $0.status == .unavailable }.count
        deferred = evidence.filter { $0.status == .deferred }.count
        unsupported = evidence.filter { $0.status == .unsupported }.count
        reservedBytes = evidence.reduce(0) { $0 + $1.reservedBytes }
        readSeconds = evidence.reduce(0) { $0 + $1.readSeconds }
    }
}

struct PromptEvidenceCapture: Sendable {
    private struct Discovery: Sendable {
        var discoveredAt: Double
        var lastSeen: UInt64
        var executable: String
        var name: String
        var peak: UInt64?
        var attempted = false
    }
    private var discoveries: [ProcessIdentity: Discovery] = [:]

    mutating func capture(
        _ samples: [ProcessSample], sequence: UInt64, using reader: any ProcessReading,
        clock: any SamplingClock, limits: PromptCaptureLimits
    ) -> [PromptEvidence] {
        let start = clock.monotonicNow()
        var candidates: [ProcessSample] = []
        for sample in samples {
            var discovery =
                discoveries[sample.identity]
                ?? Discovery(
                    discoveredAt: sample.sampledAt, lastSeen: sequence, executable: sample.executable,
                    name: sample.name, peak: sample.kernelPeakFootprintBytes)
            let peakFell =
                discovery.peak.flatMap { old in sample.kernelPeakFootprintBytes.map { $0 < old } } ?? false
            if discovery.executable != sample.executable || discovery.name != sample.name || peakFell {
                discovery.discoveredAt = sample.sampledAt
                discovery.attempted = false
            }
            discovery.lastSeen = sequence
            discovery.executable = sample.executable
            discovery.name = sample.name
            discovery.peak = sample.kernelPeakFootprintBytes ?? discovery.peak
            discoveries[sample.identity] = discovery
            if !discovery.attempted { candidates.append(sample) }
        }
        candidates.sort {
            let left = $0.startedAt ?? $0.sampledAt
            let right = $1.startedAt ?? $1.sampledAt
            if left != right { return left > right }
            if $0.identity.pid != $1.identity.pid { return $0.identity.pid < $1.identity.pid }
            return $0.identity.startMicroseconds < $1.identity.startMicroseconds
        }
        var attempts = 0
        var bytes = 0
        var evidence: [PromptEvidence] = []
        for sample in candidates {
            guard let discovery = discoveries[sample.identity] else { continue }
            let allowance = min(limits.bytesPerRead, limits.bytes - bytes)
            guard attempts < limits.attempts, allowance > 0,
                clock.monotonicNow() - start < limits.elapsedSeconds
            else {
                evidence.append(
                    PromptEvidence(
                        id: UUID(), process: sample.identity, discoveredAt: discovery.discoveredAt,
                        observedAt: nil,
                        readSeconds: 0, reservedBytes: 0, status: .deferred, metadata: nil))
                continue
            }
            attempts += 1
            bytes += allowance
            let before = clock.monotonicNow()
            let metadata = reader.captureLaunchEvidence(for: sample, maximumBytes: allowance)
            let after = clock.monotonicNow()
            let status: PromptEvidenceStatus
            switch metadata?.status {
            case .none: status = .unsupported
            case .truncated: status = .truncated
            case .unavailable, .notObserved: status = .unavailable
            case .markerRead, .malformed: status = .captured
            }
            discoveries[sample.identity]?.attempted = true
            evidence.append(
                PromptEvidence(
                    id: UUID(), process: sample.identity, discoveredAt: discovery.discoveredAt,
                    observedAt: after,
                    readSeconds: max(0, after - before), reservedBytes: allowance, status: status,
                    metadata: metadata))
        }
        if discoveries.count > limits.retainedDiscoveries {
            let removed = discoveries.sorted {
                if $0.value.lastSeen != $1.value.lastSeen { return $0.value.lastSeen < $1.value.lastSeen }
                if $0.key.pid != $1.key.pid { return $0.key.pid < $1.key.pid }
                return $0.key.startMicroseconds < $1.key.startMicroseconds
            }.prefix(discoveries.count - limits.retainedDiscoveries)
            for (identity, _) in removed { discoveries[identity] = nil }
        }
        return evidence
    }
}

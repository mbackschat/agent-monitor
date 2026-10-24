import Foundation

public enum MonitoringStage: String, Sendable { case resolution, presentation }

public struct MonitoringPipelineLimits: Sendable {
    public let pendingScans: Int
    public let pendingObservations: Int
    public let pendingTextBytes: Int

    public init(
        pendingScans: Int = 128, pendingObservations: Int = 65_536, pendingTextBytes: Int = 16_777_216
    ) {
        self.pendingScans = pendingScans
        self.pendingObservations = pendingObservations
        self.pendingTextBytes = pendingTextBytes
    }

    var isValid: Bool { pendingScans > 0 && pendingObservations > 0 && pendingTextBytes > 0 }
}

struct MonitoringPayloadSize: Sendable {
    var observations: Int
    var textBytes: Int

    init(observations: Int, textBytes: Int) {
        self.observations = observations
        self.textBytes = textBytes
    }

    init(_ snapshot: ProcessSnapshot) {
        observations = snapshot.samples.count + snapshot.nativeOutcomes.count
        textBytes = snapshot.samples.reduce(0) {
            $0 + $1.executable.utf8.count + $1.name.utf8.count + ($1.terminal?.utf8.count ?? 0)
        }
        observations += snapshot.promptEvidence.count
        for evidence in snapshot.promptEvidence {
            guard let metadata = evidence.metadata else { continue }
            let fields =
                [metadata.cwd, metadata.invocation, metadata.terminal].compactMap { $0 }
                + (metadata.command ?? []) + metadata.writerThreadIDs + metadata.listeningSockets
                + metadata.markers.flatMap {
                    [$0.threadID, $0.rootSessionID, $0.inboxSocket].compactMap { $0 }
                }
            observations += fields.count + metadata.markers.count
            textBytes += fields.reduce(0) { $0 + $1.utf8.count }
        }
    }

    init(_ findings: [HeavyProcess]) {
        observations = findings.count
        textBytes = findings.reduce(0) { total, finding in
            let fields = [
                finding.executable, finding.name, finding.cwd, finding.attribution.threadID,
                finding.attribution.rootSessionID, finding.attribution.terminal,
                finding.attribution.runtimeDirectory,
            ]
            return total + fields.compactMap { $0 }.reduce(0) { $0 + $1.utf8.count }
                + (finding.command ?? []).reduce(0) { $0 + $1.utf8.count }
                + finding.attribution.candidateThreadIDs.reduce(0) { $0 + $1.utf8.count }
        }
        observations += findings.reduce(0) {
            $0 + $1.attribution.ancestry.count + $1.attribution.candidateThreadIDs.count
                + ($1.command?.count ?? 0)
        }
    }
}

/// A single-consumer FIFO. Pressure terminates visibly after accepted entries drain;
/// replacing snapshots here would discard CPU intervals (resource-accounting proposal).
actor MonitoringChannel<Element: Sendable> {
    private struct Entry {
        let value: Element
        let size: MonitoringPayloadSize
    }

    private let stage: MonitoringStage
    private let limits: MonitoringPipelineLimits
    private var queue: [Entry?] = []
    private var head = 0
    private var observations = 0
    private var textBytes = 0
    private var ended = false
    private var failure: (any Error)?
    private var waiter: CheckedContinuation<Element?, any Error>?

    init(stage: MonitoringStage, limits: MonitoringPipelineLimits) {
        self.stage = stage
        self.limits = limits
    }

    func send(_ value: Element, size: MonitoringPayloadSize, sequence: UInt64) throws {
        guard !ended else { throw failure ?? CancellationError() }
        guard queue.count - head < limits.pendingScans,
            size.observations <= limits.pendingObservations - observations,
            size.textBytes <= limits.pendingTextBytes - textBytes
        else { throw MonitoringError.overloaded(stage: stage, rejectedScan: sequence) }
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: value)
        } else {
            queue.append(Entry(value: value, size: size))
            observations += size.observations
            textBytes += size.textBytes
        }
    }

    func finish(throwing error: (any Error)? = nil) {
        guard !ended else { return }
        ended = true
        failure = error
        if let waiter {
            self.waiter = nil
            if let error { waiter.resume(throwing: error) } else { waiter.resume(returning: nil) }
        }
    }

    func cancel() {
        queue.removeAll()
        head = 0
        observations = 0
        textBytes = 0
        if !ended { finish(throwing: CancellationError()) }
    }

    func next() async throws -> Element? {
        try Task.checkCancellation()
        if head < queue.count, let entry = queue[head] {
            queue[head] = nil
            head += 1
            observations -= entry.size.observations
            textBytes -= entry.size.textBytes
            if head >= max(1, limits.pendingScans / 2) {
                queue.removeFirst(head)
                head = 0
            }
            return entry.value
        }
        if ended {
            if let failure { throw failure }
            return nil
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiter = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }
}

import Foundation

public enum MonitoringStage: String, Sendable {
    case accounting, publication, presentation

    var capacityDescription: String {
        switch self {
        case .accounting: "the open accounting unit"
        case .presentation: "the pending report"
        case .publication: "the closed accounting units awaiting publication"
        }
    }
}

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

struct MonitoringPayloadSize: Equatable, Sendable {
    var observations: Int
    var textBytes: Int

    init(observations: Int, textBytes: Int) {
        self.observations = observations
        self.textBytes = textBytes
    }

    init(_ findings: [HeavyProcess], includeAttribution: Bool = true) {
        observations = findings.count
        textBytes = 0
        for finding in findings {
            textBytes += finding.executable.utf8.count + finding.name.utf8.count
            textBytes += finding.cwd?.utf8.count ?? 0
            textBytes += finding.sessionName?.utf8.count ?? 0
            for value in finding.command ?? [] { textBytes += value.utf8.count }
            observations += finding.command?.count ?? 0
            if includeAttribution {
                let context = Self(attribution: finding.attribution)
                observations += context.observations
                textBytes += context.textBytes
            }
        }
    }

    mutating func add(_ other: Self) {
        observations += other.observations
        textBytes += other.textBytes
    }

    mutating func subtract(_ other: Self) {
        observations -= other.observations
        textBytes -= other.textBytes
    }

    init(attribution owner: Attribution) {
        observations = owner.ancestry.count + owner.candidateThreadIDs.count
        textBytes =
            (owner.threadID?.utf8.count ?? 0) + (owner.rootSessionID?.utf8.count ?? 0)
            + (owner.terminal?.utf8.count ?? 0) + (owner.runtimeDirectory?.utf8.count ?? 0)
        for value in owner.candidateThreadIDs { textBytes += value.utf8.count }
    }

}

/// Bounded single-consumer delivery; accounting windows may merge by unique endpoints.
/// Admission preserves the accepted value if coalescing cannot represent the next window.
actor MonitoringChannel<Element: Sendable> {
    private struct Entry {
        var value: Element
        var size: MonitoringPayloadSize
    }

    private let coalesce: (@Sendable (inout Element, Element) throws -> MonitoringPayloadSize)?
    private let stage: MonitoringStage
    private let limits: MonitoringPipelineLimits
    private var queue: [Entry?] = []
    private var head = 0
    private var observations = 0
    private var textBytes = 0
    private var ended = false
    private var failure: (any Error)?
    private var waiter: CheckedContinuation<Element?, any Error>?

    init(
        stage: MonitoringStage, limits: MonitoringPipelineLimits,
        coalesce: (@Sendable (inout Element, Element) throws -> MonitoringPayloadSize)? = nil
    ) {
        self.coalesce = coalesce
        self.stage = stage
        self.limits = limits
    }

    func send(_ value: Element, size: MonitoringPayloadSize, sequence: UInt64) throws {
        guard !ended else { throw failure ?? CancellationError() }
        if let coalesce, head < queue.count, var previous = queue[head] {
            // An exceptional current-population overflow must not mutate already accepted work.
            // Keep the rollback value until admission succeeds (CPU-01 pressure contract).
            let mergedSize = try coalesce(&previous.value, value)
            guard mergedSize.observations <= limits.pendingObservations,
                mergedSize.textBytes <= limits.pendingTextBytes
            else { throw MonitoringError.overloaded(stage: stage, rejectedScan: sequence) }
            previous.size = mergedSize
            queue[head] = previous
            observations = mergedSize.observations
            textBytes = mergedSize.textBytes
            return
        }
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

    var isDrained: Bool { ended && head == queue.count }

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

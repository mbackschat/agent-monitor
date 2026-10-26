import Foundation

enum InspectionLimits {
    static let maximumReads = 16
    static let maximumNativeOperations = 132
    static let maximumHeldReadings = 16
    static let maximumHeldRecords = 512
    static let maximumHeldTextBytes = 65_536
    static let offset = 0.05
    static let maximumSeconds = 0.01
    static let deadlineReserve = 0.005
}

public struct InspectionCoverage: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable { case disabled, enabled, mixed }
    public var mode: Mode = .disabled
    public var opportunitiesTaken = 0
    public var opportunitiesSkipped = 0
    public var enumerationFailures = 0
    public var candidatesRead = 0
    public var candidatesFailed = 0
    public var candidatesLeftUnread = 0
    public var carriedObservations = 0
    public var supersededReadings = 0
    public var droppedReadings = 0
    public var discardedReadings = 0
    public var maximumCompleteScanLateness: Double = 0

    public init() {}

    public var mostlySkipped: Bool {
        mode != .disabled && opportunitiesSkipped > opportunitiesTaken
    }

    public mutating func merge(_ other: Self) {
        if mode != other.mode { mode = .mixed }
        opportunitiesTaken += other.opportunitiesTaken
        opportunitiesSkipped += other.opportunitiesSkipped
        enumerationFailures += other.enumerationFailures
        candidatesRead += other.candidatesRead
        candidatesFailed += other.candidatesFailed
        candidatesLeftUnread += other.candidatesLeftUnread
        carriedObservations += other.carriedObservations
        supersededReadings += other.supersededReadings
        droppedReadings += other.droppedReadings
        discardedReadings += other.discardedReadings
        maximumCompleteScanLateness = max(maximumCompleteScanLateness, other.maximumCompleteScanLateness)
    }
}

struct HeldInspectionObservation: Sendable {
    let sample: ProcessSample
    let row: HeavyProcess
    let evidenceAt: Double?
    let isAgentRuntime: Bool
    let corroboratedRoot: String?

    var payloadSize: MonitoringPayloadSize {
        var size = MonitoringPayloadSize([row])
        size.observations += 1
        size.textBytes += sample.executable.utf8.count + sample.name.utf8.count
        size.textBytes += corroboratedRoot?.utf8.count ?? 0
        return size
    }
}

/// Held evidence is not accepted CPU. Only the next complete census can admit it
/// under the disappearance table in proposals/inspection-observations.md.
struct InspectionBuffer: Sendable {
    private var readings: [ProcessIdentity: HeldInspectionObservation] = [:]
    private var size = MonitoringPayloadSize(observations: 0, textBytes: 0)
    var coverage = InspectionCoverage()
    var count: Int { readings.count }

    mutating func retain(_ reading: HeldInspectionObservation) -> Bool {
        guard readings[reading.sample.identity] == nil else { return false }
        var proposed = size
        proposed.add(reading.payloadSize)
        guard count < InspectionLimits.maximumHeldReadings,
            proposed.observations <= InspectionLimits.maximumHeldRecords,
            proposed.textBytes <= InspectionLimits.maximumHeldTextBytes
        else {
            coverage.droppedReadings += 1
            return false
        }
        readings[reading.sample.identity] = reading
        size = proposed
        return true
    }

    mutating func discard() {
        coverage.discardedReadings += count
        clear()
    }

    mutating func admit(at census: ProcessSnapshot) -> [HeldInspectionObservation] {
        let current = Dictionary(uniqueKeysWithValues: census.samples.map { ($0.identity.pid, $0) })
        let listed = census.listedPIDs.map(Set.init)
        let outcomes = Dictionary(grouping: census.nativeOutcomes, by: \.pid)
        var carried: [HeldInspectionObservation] = []
        for reading in readings.values {
            let identity = reading.sample.identity
            if let sample = current[identity.pid] {
                if sample.identity != identity {
                    carried.append(reading)
                } else if sample.cpuSeconds != nil {
                    coverage.supersededReadings += 1
                } else {
                    coverage.droppedReadings += 1
                }
                continue
            }
            let vanished = listed?.contains(identity.pid) == false
            let proven = (outcomes[identity.pid] ?? []).contains { outcome in
                switch (outcome.operation, outcome.status) {
                case (.bsdInfo, .lookupUnavailable), (.identityVerification, .lookupUnavailable): true
                case (.identityVerification, .identityMismatch):
                    outcome.verifiedIdentity.map { $0.pid == identity.pid && $0 != identity } ?? false
                default: false
                }
            }
            if vanished || proven { carried.append(reading) } else { coverage.droppedReadings += 1 }
        }
        coverage.carriedObservations += carried.count
        clear()
        return carried.sorted { $0.sample.identity.pid < $1.sample.identity.pid }
    }

    private mutating func clear() {
        readings.removeAll(keepingCapacity: true)
        size = MonitoringPayloadSize(observations: 0, textBytes: 0)
    }
}

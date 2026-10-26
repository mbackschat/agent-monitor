import Foundation
import Synchronization

public struct RecentActivityLimits: Sendable {
    public let seconds: Double
    public let records: Int
    public let textBytes: Int

    public init(seconds: Double = 60, records: Int = 65_536, textBytes: Int = 16_777_216) {
        precondition(seconds > 0 && seconds.isFinite && records > 0 && textBytes > 0)
        self.seconds = seconds
        self.records = records
        self.textBytes = textBytes
    }
}

/// A self-contained immutable view. Its lease charges retained backing data until inspection ends.
public final class RecentActivitySnapshot: Equatable, Sendable {
    public let id: UUID
    public let runID: UUID
    public let scope: ProcessScope
    public let units: [RecentActivityUnit]
    public let displayUnits: [RecentActivityUnit]
    public let current: [RecentWorkerRecord]
    public let present: Set<ProcessIdentity>
    public let finalScan: UInt64
    public let endedAt: Double
    public let currentContextAvailable: Bool
    public let retentionLimited: Bool
    public let targetSeconds: Double
    private let release: @Sendable (UUID) -> Void
    private let publish: @Sendable (RecentActivitySnapshot, [RecentActivityUnit]) -> RecentActivitySnapshot

    init(
        id: UUID, runID: UUID, scope: ProcessScope, units: [RecentActivityUnit],
        current: [RecentWorkerRecord],
        present: Set<ProcessIdentity>, finalScan: UInt64, endedAt: Double, limited: Bool,
        target: Double, currentContextAvailable: Bool, displayUnits: [RecentActivityUnit],
        publish: @escaping @Sendable (RecentActivitySnapshot, [RecentActivityUnit]) -> RecentActivitySnapshot,
        release: @escaping @Sendable (UUID) -> Void
    ) {
        self.id = id
        self.runID = runID
        self.scope = scope
        self.units = units
        self.displayUnits = displayUnits
        self.publish = publish
        self.current = current
        self.present = present
        self.finalScan = finalScan
        self.endedAt = endedAt
        self.currentContextAvailable = currentContextAvailable
        retentionLimited = limited
        targetSeconds = target
        self.release = release
    }

    deinit { release(id) }
    func displaying(_ unit: RecentActivityUnit) -> RecentActivitySnapshot {
        publish(self, [unit])
    }
    public static func == (lhs: RecentActivitySnapshot, rhs: RecentActivitySnapshot) -> Bool {
        lhs.id == rhs.id
    }
    public var inspectionCoverage: InspectionCoverage {
        guard let first = units.first else { return InspectionCoverage() }
        return units.dropFirst().reduce(first.inspectionCoverage) { result, unit in
            var combined = result
            combined.merge(unit.inspectionCoverage)
            return combined
        }
    }

    public var baselineScan: UInt64 { units.first?.baselineScan ?? finalScan }
    public var startedAt: Double { units.first?.startedAt ?? endedAt }
    public var duration: Double { max(0, endedAt - startedAt) }
    public var cpuSeconds: Double {
        units.reduce(0) { total, unit in
            total + unit.records.reduce(0) { $0 + $1.cpuSeconds }
                + unit.collapsedContributions.reduce(0) { $0 + $1.cpuSeconds }
                + unit.crossings.filter { $0.contribution.id.opening.scan.sequence >= baselineScan }
                .reduce(0) { $0 + $1.contribution.cpuSeconds }
        }
    }
    public var recoveredCPUSeconds: Double {
        units.flatMap(\.crossings).filter { $0.contribution.id.opening.scan.sequence < baselineScan }
            .reduce(0) { $0 + $1.contribution.cpuSeconds }
    }
}

public struct RecentActivityDiagnostics: Codable, Sendable {
    public let retainedUnits: Int
    public let chargedRecords: Int
    public let chargedTextBytes: Int
    public let leases: Int
    public let lossBoundary: Double?
    public let capacityEvictions: Int
    public let discontinuities: Int
    public let currentContextAvailable: Bool
    public let categoryRecords: Int
    public let candidateReferences: Int
    public let sharedCandidateEntries: Int
    public let crossingRecords: Int
    public let coverageRecords: Int
}

protocol RecentActivityCollecting: Sendable {
    func append(_ unit: RecentActivityUnit, current: [RecentWorkerRecord]?, present: Set<ProcessIdentity>?)
    func snapshot() -> RecentActivitySnapshot?
}

/// Publication admits ordered units; Mutex also permits snapshot leases to be released by UI tasks.
public final class RecentActivityStore: RecentActivityCollecting {
    private struct Lease: Sendable {
        let units: [UUID: MonitoringPayloadSize]
        let extra: MonitoringPayloadSize
    }
    private struct State: Sendable {
        var runID: UUID?
        var scope: ProcessScope?
        var lastScan: UInt64?
        var endedAt = 0.0
        var units: [RecentActivityUnit] = []
        var leases: [UUID: Lease] = [:]
        var current: [RecentWorkerRecord] = []
        var present: Set<ProcessIdentity> = []
        var lossBoundary: Double?
        var currentAvailable = true
        var capacityEvictions = 0
        var discontinuities = 0
        var membershipRecordVisits = 0
        var membership: [ProcessIdentity: Int] = [:]

        mutating func appendUnit(_ unit: RecentActivityUnit) {
            units.append(unit)
            updateMembership(unit, delta: 1)
        }

        mutating func removeUnits(where predicate: (RecentActivityUnit) -> Bool) {
            var retained: [RecentActivityUnit] = []
            for unit in units {
                if predicate(unit) {
                    updateMembership(unit, delta: -1)
                } else {
                    retained.append(unit)
                }
            }
            units = retained
        }

        mutating func removeFirstUnit() -> RecentActivityUnit {
            let unit = units.removeFirst()
            updateMembership(unit, delta: -1)
            return unit
        }

        mutating func clearUnits() {
            units.removeAll()
            membership.removeAll()
        }

        private mutating func updateMembership(_ unit: RecentActivityUnit, delta: Int) {
            guard unit.scope == .agentsOnly else { return }
            // Whole-unit eviction removes exactly these references. A lifetime may have several
            // frozen categories, so a set removal would expire its membership too early.
            for record in unit.records {
                membershipRecordVisits += 1
                let identity = record.category.process
                let count = (membership[identity] ?? 0) + delta
                precondition(count >= 0)
                membership[identity] = count == 0 ? nil : count
            }
        }
    }
    private let limits: RecentActivityLimits
    private let state = Mutex(State())

    public init(limits: RecentActivityLimits = RecentActivityLimits()) { self.limits = limits }

    func append(
        _ unit: RecentActivityUnit, current: [RecentWorkerRecord]? = nil,
        present: Set<ProcessIdentity>? = nil
    ) {
        state.withLock { value in
            if value.runID != unit.runID || value.scope != unit.scope {
                value.runID = unit.runID
                value.scope = unit.scope
                value.clearUnits()
                value.lastScan = nil
                value.lossBoundary = nil
                value.capacityEvictions = 0
                value.discontinuities = 0
            }
            if let last = value.lastScan {
                precondition(unit.baselineScan >= last && unit.finalScan > last)
                if unit.baselineScan > last {
                    value.discontinuities += 1
                    value.clearUnits()
                    value.lossBoundary = unit.startedAt
                }
            }
            value.lastScan = unit.finalScan
            value.endedAt = unit.endedAt
            value.removeUnits { $0.startedAt < unit.endedAt - limits.seconds }
            value.appendUnit(unit)
            value.current = (current ?? unit.records.filter { $0.atCensus && $0.lastScan == unit.finalScan })
                .filter {
                    unit.scope == .allProcesses || $0.category.owner.isAgent
                        || value.membership[$0.category.process] != nil
                }
            value.present = present ?? Set(value.current.map(\.category.process))
            value.currentAvailable = true
            evictUnitsToFit(&value)
            if !fits(value) {
                value.current = []
                value.present = []
                value.currentAvailable = false
                value.lossBoundary = unit.endedAt
            }
        }
    }

    public func snapshot() -> RecentActivitySnapshot? {
        state.withLock { value in
            guard let run = value.runID, let scope = value.scope, let final = value.lastScan else {
                return nil
            }
            return publishLocked(
                &value, run: run, scope: scope, units: value.units, display: value.units.suffix(1).map { $0 },
                current: value.current, present: value.present, final: final, end: value.endedAt,
                limited: value.lossBoundary.map { $0 > value.endedAt - limits.seconds } ?? false,
                currentAvailable: value.currentAvailable)
        }
    }

    private func republish(_ source: RecentActivitySnapshot, display: [RecentActivityUnit])
        -> RecentActivitySnapshot
    {
        state.withLock { value in
            publishLocked(
                &value, run: source.runID, scope: source.scope, units: source.units, display: display,
                current: source.current, present: source.present, final: source.finalScan,
                end: source.endedAt, limited: source.retentionLimited,
                currentAvailable: source.currentContextAvailable)
        }
    }

    private func publishLocked(
        _ value: inout State, run: UUID, scope: ProcessScope, units: [RecentActivityUnit],
        display: [RecentActivityUnit], current: [RecentWorkerRecord], present: Set<ProcessIdentity>,
        final: UInt64, end: Double, limited: Bool, currentAvailable: Bool
    ) -> RecentActivitySnapshot {
        let id = UUID()
        var retained = units
        var projected = RecentActivityUnit.compacted(retained)
        var displayed = display
        var rows = current
        var identities = present
        var shortened = limited
        func lease() -> Lease? {
            var sizes: [UUID: MonitoringPayloadSize] = [:]
            for unit in projected + displayed { sizes[unit.id] = unit.size }
            var extra = extraSize(rows, present: identities)
            guard !sizes.isEmpty || extra.observations > 0 || extra.textBytes > 0 else { return nil }
            // Shared unit payloads are charged once, but each inspection owns its lease and
            // references. CPU-01's bounded retention includes that bookkeeping even when
            // several snapshots share all of their underlying measurements.
            extra.observations += 1 + sizes.count
            return Lease(units: sizes, extra: extra)
        }
        value.leases[id] = lease()
        // Published ranges own compact records, so evict original store units before reducing
        // an immutable projection. Republishing must not try to free its own still-live input.
        evictUnitsToFit(&value)
        while !fits(value), !retained.isEmpty {
            let removed = retained.removeFirst()
            if value.units.contains(where: { $0.id == removed.id }) {
                value.removeUnits { $0.id == removed.id }
                value.capacityEvictions += 1
                value.lossBoundary = max(value.lossBoundary ?? removed.endedAt, removed.endedAt)
            }
            shortened = true
            projected = RecentActivityUnit.compacted(retained)
            value.leases[id] = lease()
        }
        if !fits(value) {
            displayed = []
            rows = []
            identities = []
            shortened = true
            if value.runID == run && value.scope == scope {
                value.lossBoundary = max(value.lossBoundary ?? end, end)
            }
            value.leases[id] = lease()
        }
        return RecentActivitySnapshot(
            id: id, runID: run, scope: scope, units: projected, current: rows,
            present: identities, finalScan: final, endedAt: end, limited: shortened,
            target: limits.seconds,
            currentContextAvailable: currentAvailable && rows.count == current.count
                && identities.count == present.count, displayUnits: displayed,
            publish: { [self] source, display in republish(source, display: display) },
            release: { [self] id in state.withLock { $0.leases[id] = nil } })
    }

    private func evictUnitsToFit(_ value: inout State) {
        while !fits(value), !value.units.isEmpty {
            let removed = value.removeFirstUnit()
            value.capacityEvictions += 1
            value.lossBoundary = max(value.lossBoundary ?? removed.endedAt, removed.endedAt)
        }
    }

    private func extraSize(_ rows: [RecentWorkerRecord], present: Set<ProcessIdentity>)
        -> MonitoringPayloadSize
    {
        rows.reduce(MonitoringPayloadSize(observations: present.count, textBytes: 0)) { size, row in
            MonitoringPayloadSize(
                observations: size.observations + row.payloadSize.observations,
                textBytes: size.textBytes + row.payloadSize.textBytes)
        }
    }

    public var diagnostics: RecentActivityDiagnostics {
        state.withLock { value in
            let size = usage(value)
            return RecentActivityDiagnostics(
                retainedUnits: value.units.count, chargedRecords: size.observations,
                chargedTextBytes: size.textBytes, leases: value.leases.count,
                lossBoundary: value.lossBoundary, capacityEvictions: value.capacityEvictions,
                discontinuities: value.discontinuities, currentContextAvailable: value.currentAvailable,
                categoryRecords: value.units.reduce(0) { $0 + $1.records.count },
                candidateReferences: value.units.reduce(0) { total, unit in
                    total + unit.records.reduce(0) { $0 + $1.category.owner.candidates.count }
                },
                sharedCandidateEntries: value.units.reduce(0) { total, unit in
                    total
                        + Set((unit.records.map(\.category) + unit.crossings.map(\.category)).map(\.owner))
                        .reduce(0) { $0 + $1.candidates.count }
                },
                crossingRecords: value.units.reduce(0) { $0 + $1.crossings.count },
                coverageRecords: value.units.reduce(0) { $0 + $1.readCoverage.retainedCount })
        }
    }

    var retainedPayloadSize: MonitoringPayloadSize { state.withLock { usage($0) } }
    var membershipRecordVisitCount: Int { state.withLock { $0.membershipRecordVisits } }

    var membershipMatchesRetainedRecords: Bool {
        state.withLock { value in
            var expected: [ProcessIdentity: Int] = [:]
            for unit in value.units where unit.scope == .agentsOnly {
                for record in unit.records { expected[record.category.process, default: 0] += 1 }
            }
            return value.membership == expected
        }
    }

    private func fits(_ value: State, adding: MonitoringPayloadSize? = nil) -> Bool {
        let size = usage(value, adding: adding)
        return size.observations <= limits.records && size.textBytes <= limits.textBytes
    }

    private func usage(_ value: State, adding: MonitoringPayloadSize? = nil) -> MonitoringPayloadSize {
        var all = Dictionary(uniqueKeysWithValues: value.units.map { ($0.id, $0.size) })
        var size = extraSize(value.current, present: value.present)
        for lease in value.leases.values {
            all.merge(lease.units) { first, _ in first }
            size.observations += lease.extra.observations
            size.textBytes += lease.extra.textBytes
        }
        for retained in all.values {
            size.observations += retained.observations
            size.textBytes += retained.textBytes
        }
        size.observations += adding?.observations ?? 0
        size.textBytes += adding?.textBytes ?? 0
        return size
    }
}

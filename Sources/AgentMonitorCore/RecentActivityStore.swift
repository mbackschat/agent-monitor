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
    func coalescing(_ previous: RecentActivitySnapshot?) -> RecentActivitySnapshot {
        guard let previous, previous.runID == runID, previous.scope == scope else { return self }
        return publish(self, previous.displayUnits + displayUnits)
    }
    public static func == (lhs: RecentActivitySnapshot, rhs: RecentActivitySnapshot) -> Bool {
        lhs.id == rhs.id
    }
    public var baselineScan: UInt64 { units.first?.baselineScan ?? finalScan }
    public var startedAt: Double { units.first?.startedAt ?? endedAt }
    public var duration: Double { max(0, endedAt - startedAt) }
    public var cpuSeconds: Double {
        units.reduce(0) { total, unit in
            total + unit.records.reduce(0) { $0 + $1.cpuSeconds }
                + unit.crossings.filter { $0.contribution.id.opening.scan.sequence >= baselineScan }
                .reduce(0) { $0 + $1.contribution.cpuSeconds }
        }
    }
    public var recoveredCPUSeconds: Double {
        units.flatMap(\.crossings).filter { $0.contribution.id.opening.scan.sequence < baselineScan }
            .reduce(0) { $0 + $1.contribution.cpuSeconds }
    }
}

/// Resolution admits ordered units; Mutex also permits snapshot leases to be released by UI tasks.
public final class RecentActivityStore: Sendable {
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
        var limited = false
        var currentAvailable = true
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
                value.units.removeAll()
                value.lastScan = nil
                value.limited = false
            }
            if let last = value.lastScan {
                precondition(unit.baselineScan >= last && unit.finalScan > last)
                if unit.baselineScan > last {
                    value.units.removeAll()
                    value.limited = true
                }
            }
            value.lastScan = unit.finalScan
            value.endedAt = unit.endedAt
            value.units.removeAll { $0.startedAt < unit.endedAt - limits.seconds }
            let selected = Set((value.units + [unit]).flatMap { $0.records.map(\.category.process) })
            value.current = (current ?? unit.records.filter { $0.lastScan == unit.finalScan }).filter {
                selected.contains($0.category.process)
                    || unit.scope == .allProcesses || $0.category.owner.isAgent
            }
            value.present = present ?? Set(value.current.map(\.category.process))
            value.currentAvailable = true
            value.units.removeAll { $0.startedAt < unit.endedAt - limits.seconds }
            value.units.append(unit)
            while !fits(value), !value.units.isEmpty {
                value.units.removeFirst()
                value.limited = true
            }
            if !fits(value) {
                value.current = []
                value.present = []
                value.currentAvailable = false
                value.limited = true
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
                limited: value.limited, currentAvailable: value.currentAvailable)
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
        var displayed = display
        var rows = current
        var identities = present
        var shortened = limited
        func lease() -> Lease {
            var sizes: [UUID: MonitoringPayloadSize] = [:]
            for unit in retained + displayed { sizes[unit.id] = unit.size }
            return Lease(units: sizes, extra: extraSize(rows, present: identities))
        }
        value.leases[id] = lease()
        while !fits(value), !retained.isEmpty {
            let removed = retained.removeFirst()
            value.units.removeAll { $0.id == removed.id }
            shortened = true
            value.leases[id] = lease()
        }
        if !fits(value) {
            displayed = []
            rows = []
            identities = []
            shortened = true
            value.leases[id] = lease()
        }
        value.limited = value.limited || shortened
        return RecentActivitySnapshot(
            id: id, runID: run, scope: scope, units: retained, current: rows,
            present: identities, finalScan: final, endedAt: end, limited: shortened,
            target: limits.seconds,
            currentContextAvailable: currentAvailable && rows.count == current.count
                && identities.count == present.count, displayUnits: displayed,
            publish: { [self] source, display in republish(source, display: display) },
            release: { [self] id in state.withLock { $0.leases[id] = nil } })
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

    var retainedPayloadSize: MonitoringPayloadSize { state.withLock { usage($0) } }

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

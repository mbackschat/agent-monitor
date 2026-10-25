import Foundation

/// PID values identify failed reads, not distinct lifetimes or agent-owned workers.
/// The native listing targets the current UID; failures have no verified ownership and PID reuse cannot be resolved from these observations.
public struct ReadCoverage: Equatable, Codable, Sendable {
    public private(set) var deniedPIDs: Set<Int32> = []
    public private(set) var vanishedPIDs: Set<Int32> = []
    public private(set) var mismatchedPIDs: Set<Int32> = []
    public private(set) var otherFailedPIDs: Set<Int32> = []
    public private(set) var unidentifiedFailureObservations = 0
    public private(set) var failedPIDObservations = 0
    public private(set) var scanCount = 0
    public private(set) var maximumFailedPIDsPerScan = 0

    public private(set) var releasedDenied: LifetimeCountRange?
    public private(set) var releasedVanished: LifetimeCountRange?
    public private(set) var releasedMismatched: LifetimeCountRange?
    public private(set) var releasedOther: LifetimeCountRange?
    public private(set) var releasedAll: LifetimeCountRange?
    public private(set) var startedAt: Double?
    public private(set) var endedAt: Double?

    public init() {}
    public var failedPIDCount: LifetimeCountRange { Self.count(failedPIDs, releasedAll) }
    public var deniedPIDCount: LifetimeCountRange { Self.count(deniedPIDs, releasedDenied) }
    public var vanishedPIDCount: LifetimeCountRange { Self.count(vanishedPIDs, releasedVanished) }
    public var mismatchedPIDCount: LifetimeCountRange { Self.count(mismatchedPIDs, releasedMismatched) }
    public var otherPIDCount: LifetimeCountRange { Self.count(otherFailedPIDs, releasedOther) }
    /// Failures to read a listed process, excluding PIDs that had already exited (ESRCH).
    public var readFailurePIDCount: LifetimeCountRange {
        var result = Self.count(deniedPIDs.union(mismatchedPIDs).union(otherFailedPIDs), releasedDenied)
        for released in [releasedMismatched, releasedOther].compactMap({ $0 }) { result.union(released) }
        return result
    }
    private static func count(_ values: Set<Int32>, _ released: LifetimeCountRange?) -> LifetimeCountRange {
        var result = LifetimeCountRange(minimum: values.count, maximum: values.count)
        if let released { result.union(released) }
        return result
    }
    private static func combine(_ target: inout LifetimeCountRange?, _ other: LifetimeCountRange?) {
        guard let other else { return }
        if target == nil { target = other } else { target?.union(other) }
    }

    public var failedPIDs: Set<Int32> {
        deniedPIDs.union(vanishedPIDs).union(mismatchedPIDs).union(otherFailedPIDs)
    }
    public var meanFailedPIDsPerScan: Double {
        scanCount > 0 ? Double(failedPIDObservations) / Double(scanCount) : 0
    }

    mutating func append(_ snapshot: ProcessSnapshot?) {
        guard let snapshot else { return }
        var scan = ReadCoverage()
        for outcome in snapshot.nativeOutcomes {
            switch outcome.status {
            case .permissionDenied: scan.deniedPIDs.insert(outcome.pid)
            case .lookupUnavailable: scan.vanishedPIDs.insert(outcome.pid)
            case .identityMismatch: scan.mismatchedPIDs.insert(outcome.pid)
            case .shortRead, .otherFailure: scan.otherFailedPIDs.insert(outcome.pid)
            case .outOfScopeUser: break
            }
        }
        scan.startedAt = snapshot.listedAt
        scan.endedAt = snapshot.listedAt
        scan.scanCount = 1
        scan.failedPIDObservations = scan.failedPIDs.count
        scan.maximumFailedPIDsPerScan = scan.failedPIDObservations
        if snapshot.nativeOutcomes.isEmpty { scan.unidentifiedFailureObservations = snapshot.unreadableCount }
        merge(scan)
    }

    public mutating func merge(_ other: ReadCoverage) {
        Self.combine(&releasedDenied, other.releasedDenied)
        Self.combine(&releasedVanished, other.releasedVanished)
        Self.combine(&releasedMismatched, other.releasedMismatched)
        Self.combine(&releasedOther, other.releasedOther)
        Self.combine(&releasedAll, other.releasedAll)
        if let time = other.startedAt { startedAt = min(startedAt ?? time, time) }
        if let time = other.endedAt { endedAt = max(endedAt ?? time, time) }
        deniedPIDs.formUnion(other.deniedPIDs)
        vanishedPIDs.formUnion(other.vanishedPIDs)
        mismatchedPIDs.formUnion(other.mismatchedPIDs)
        otherFailedPIDs.formUnion(other.otherFailedPIDs)
        unidentifiedFailureObservations += other.unidentifiedFailureObservations
        failedPIDObservations += other.failedPIDObservations
        scanCount += other.scanCount
        maximumFailedPIDsPerScan = max(maximumFailedPIDsPerScan, other.maximumFailedPIDsPerScan)
        // Failed PID churn must not exhaust the accounting queue (CPU-01 pressure contract).
        // Identity is unavailable here; max/sum bounds remain valid across PID reuse.
        if retainedCount > 1_024 { releasePIDDetail() }
    }
    mutating func releasePIDDetail() {
        releasedDenied = deniedPIDCount
        releasedVanished = vanishedPIDCount
        releasedMismatched = mismatchedPIDCount
        releasedOther = otherPIDCount
        releasedAll = failedPIDCount
        deniedPIDs.removeAll()
        vanishedPIDs.removeAll()
        mismatchedPIDs.removeAll()
        otherFailedPIDs.removeAll()
    }
    var retainedCount: Int {
        deniedPIDs.count + vanishedPIDs.count + mismatchedPIDs.count + otherFailedPIDs.count
            + (releasedAll == nil ? 0 : 5)
    }
}

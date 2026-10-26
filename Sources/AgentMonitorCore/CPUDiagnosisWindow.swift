struct CPUWindowContributor: Sendable {
    var sample: ProcessSample
    var footprint: (bytes: UInt64, sampledAt: Double)?
    var cpuSeconds: Double = 0
    var observedSeconds: Double = 0
    var isMonitorHelper = false
    var validIntervals = 0
    var peakCPUPercent: Double = 0
    var meanCPUPercent: Double { 100 * cpuSeconds / observedSeconds }
}

public struct CPUWindowHost: Equatable, Sendable {
    public let meanBusyPercent: Double?
    public let logicalCPUCount: Int?
    public let observedSeconds: Double
    public let validIntervals: Int
}

/// Aggregates raw contributions independently of report thresholds, history and live rows.
/// Earlier contributors stay in the window even after Monitor drops their live node.
struct CPUDiagnosisWindow: Sendable {
    private static let maximumContributors = 10
    var monitor = Monitor()
    private let monitorPID: Int32?

    init(monitorPID: Int32? = nil) { self.monitorPID = monitorPID }
    private var lifetimes: [ProcessIdentity: CPUWindowContributor] = [:]
    private var firstListing: Double?
    private var previousListing: Double?
    private var scanEnd: Double = 0
    private var cpuCounts: Set<Int> = []
    private var hostWeightedPercent: Double = 0
    private var hostSeconds: Double = 0
    private var hostIntervals = 0
    private(set) var maximumScanSeconds: Double = 0
    private(set) var unmeasuredObservationCount = 0
    private(set) var unreadableObservationCount = 0

    mutating func ingest(_ snapshot: ProcessSnapshot) {
        let accounting = monitor.ingest(snapshot)
        if firstListing == nil { firstListing = snapshot.listedAt }
        if let previousListing {
            unmeasuredObservationCount += accounting.unmeasuredLifetimeCount
            let seconds = snapshot.listedAt - previousListing
            if seconds > 0, let busy = accounting.hostBusyPercent {
                hostWeightedPercent += busy * seconds
                hostSeconds += seconds
                hostIntervals += 1
            }
        }
        previousListing = snapshot.listedAt
        scanEnd = snapshot.listedAt + snapshot.scanSeconds
        cpuCounts.insert(snapshot.logicalCPUCount)
        maximumScanSeconds = max(maximumScanSeconds, snapshot.scanSeconds)
        unreadableObservationCount += snapshot.unreadableCount
        let helperRoots = Set(lifetimes.values.filter(\.isMonitorHelper).map(\.sample.identity))
            .union(
                snapshot.samples.filter { monitorPID != nil && $0.parentPID == monitorPID }.map(\.identity))
        for sample in snapshot.samples {
            var contributor = lifetimes[sample.identity] ?? CPUWindowContributor(sample: sample)
            contributor.sample = sample
            contributor.isMonitorHelper =
                contributor.isMonitorHelper
                || monitor.chain(from: sample.identity).contains(where: helperRoots.contains)
            if let bytes = sample.footprintBytes {
                contributor.footprint = (bytes, sample.sampledAt)
            }
            if let interval = monitor.cpuContribution(for: sample.identity) {
                contributor.cpuSeconds += interval.cpuSeconds
                contributor.observedSeconds += interval.observedSeconds
                contributor.validIntervals += 1
                contributor.peakCPUPercent = max(contributor.peakCPUPercent, interval.cpuPercent)
            }
            lifetimes[sample.identity] = contributor
        }
    }

    var rankedContributors: [CPUWindowContributor] {
        var ranked: [CPUWindowContributor] = []
        ranked.reserveCapacity(Self.maximumContributors)
        for contributor in lifetimes.values where contributor.validIntervals > 0 {
            let index = ranked.firstIndex { Self.ranksBefore(contributor, $0) } ?? ranked.endIndex
            guard index < Self.maximumContributors else { continue }
            if ranked.count == Self.maximumContributors { ranked.removeLast() }
            ranked.insert(contributor, at: index)
        }
        return ranked
    }

    private static func ranksBefore(_ lhs: CPUWindowContributor, _ rhs: CPUWindowContributor) -> Bool {
        if lhs.cpuSeconds != rhs.cpuSeconds { return lhs.cpuSeconds > rhs.cpuSeconds }
        if lhs.sample.identity.pid != rhs.sample.identity.pid {
            return lhs.sample.identity.pid < rhs.sample.identity.pid
        }
        return lhs.sample.identity.startMicroseconds < rhs.sample.identity.startMicroseconds
    }

    var contributors: [CPUWindowContributor] { rankedContributors }
    var observedLifetimeCount: Int { lifetimes.count }
    var measuredLifetimeCount: Int {
        lifetimes.values.reduce(0) { $0 + ($1.validIntervals > 0 ? 1 : 0) }
    }
    var omittedContributorCount: Int { max(0, measuredLifetimeCount - Self.maximumContributors) }
    var elapsedSeconds: Double { firstListing.map { scanEnd - $0 } ?? 0 }
    var cpuSeconds: Double? {
        var total: Double?
        for contributor in lifetimes.values where contributor.validIntervals > 0 {
            total = (total ?? 0) + contributor.cpuSeconds
        }
        return total
    }
    var windowCPUPercent: Double? { cpuSeconds.map { 100 * $0 / elapsedSeconds } }
    var host: CPUWindowHost {
        CPUWindowHost(
            meanBusyPercent: hostIntervals > 0 ? hostWeightedPercent / hostSeconds : nil,
            logicalCPUCount: cpuCounts.count == 1 ? cpuCounts.first : nil,
            observedSeconds: hostSeconds, validIntervals: hostIntervals)
    }
}

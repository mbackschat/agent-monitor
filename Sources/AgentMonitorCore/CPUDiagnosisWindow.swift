/// One valid R1 interval. Its duration is the lifetime's measured accounting window,
/// including zero before birth for a newborn (docs/architecture.md#cpu-accounting).
public struct CPUContribution: Equatable, Sendable {
    public let cpuSeconds: Double
    public let observedSeconds: Double
    public var cpuPercent: Double { 100 * cpuSeconds / observedSeconds }
}

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
        lifetimes.values.filter { $0.validIntervals > 0 }.sorted {
            if $0.cpuSeconds != $1.cpuSeconds { return $0.cpuSeconds > $1.cpuSeconds }
            if $0.sample.identity.pid != $1.sample.identity.pid {
                return $0.sample.identity.pid < $1.sample.identity.pid
            }
            return $0.sample.identity.startMicroseconds < $1.sample.identity.startMicroseconds
        }
    }

    var contributors: [CPUWindowContributor] { Array(rankedContributors.prefix(10)) }
    var observedLifetimeCount: Int { lifetimes.count }
    var measuredLifetimeCount: Int { lifetimes.values.filter { $0.validIntervals > 0 }.count }
    var omittedContributorCount: Int { max(0, measuredLifetimeCount - 10) }
    var elapsedSeconds: Double { firstListing.map { scanEnd - $0 } ?? 0 }
    var cpuSeconds: Double? {
        let measured = rankedContributors
        return measured.isEmpty ? nil : measured.reduce(0) { $0 + $1.cpuSeconds }
    }
    var windowCPUPercent: Double? { cpuSeconds.map { 100 * $0 / elapsedSeconds } }
    var host: CPUWindowHost {
        CPUWindowHost(
            meanBusyPercent: hostIntervals > 0 ? hostWeightedPercent / hostSeconds : nil,
            logicalCPUCount: cpuCounts.count == 1 ? cpuCounts.first : nil,
            observedSeconds: hostSeconds, validIntervals: hostIntervals)
    }
}

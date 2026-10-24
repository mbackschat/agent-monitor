import AgentMonitorCore
import Darwin
import Foundation
import Synchronization

@main enum LivePipeline {
    struct Report: Encodable, Sendable {
        let duration: Double
        let finalScan: UInt64
        let population: Int
        let unreadableAtFinalScan: Int
        let contributions: Int
        let recentUnits: Int
        let heapBytesInUse: UInt64
        let heapPeakBytes: UInt64?
        let retentionLimited: Bool
        let history: RecentActivityDiagnostics
        let coverage: AcquisitionCoverage
        let processCPUSeconds: Double
        let reapedChildCPUSeconds: Double?
        let hostBusyPercent: Double?
        let logicalCPUs: Int
        let measuredUserPercent: Double
        let acquisition: AcquisitionTiming?
    }
    struct Result: Encodable {
        let startedAt: Date
        let elapsedSeconds: Double
        let processCPUSeconds: Double
        let reapedChildCPUSeconds: Double?
        let providerListingsEnabled: Bool
        let error: String?
        let reports: [Report]
        let nativeScanPeriods: [Double]
        let periodP50: Double?
        let periodP99: Double?
        let maximumPeriod: Double?
        let providerCalls: Int
        let observedOwnRuntimeChildren: Int
    }
    static func childCPUSeconds() -> Double? {
        var usage = rusage()
        guard getrusage(RUSAGE_CHILDREN, &usage) == 0 else { return nil }
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }

    static func main() async throws {
        let reports = Mutex<[Report]>([])
        let start = ContinuousClock.now
        let date = Date()
        let reader = try TimedNativeReader()
        let history = RecentActivityStore()
        let providers = ProfileListings(enabled: CommandLine.arguments.contains("--providers"))
        let cpuStart = clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)
        let childCPUStart = childCPUSeconds()
        @Sendable func childDelta() -> Double? {
            guard let baseline = childCPUStart, let current = childCPUSeconds() else { return nil }
            return current - baseline
        }
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                intervalSeconds: 0.1, samples: CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 3,
                collectAgentLoad: true, reportIntervalSeconds: 5),
            reader: reader, clock: ContinuousSamplingClock(), registry: providers,
            excluding: [getpid()], recentActivity: history)
        var failure: String?
        do {
            try await session.run { snapshot in
                guard let window = snapshot.window else { return }
                var heap = malloc_statistics_t()
                malloc_zone_statistics(nil, &heap)
                let progress =
                    "scan \(window.finalScan) · \(snapshot.sampledProcessCount) processes · max gap \(window.acquisitionCoverage.maximumGapSeconds ?? 0) s · \(window.acquisitionCoverage.overrunCount) overruns · heap \(heap.size_in_use) · recent \(snapshot.recentActivity?.units.count ?? 0) units\n"
                try FileHandle.standardError.write(contentsOf: Data(progress.utf8))
                reports.withLock {
                    $0.append(
                        Report(
                            duration: window.durationSeconds, finalScan: window.finalScan,
                            population: snapshot.sampledProcessCount,
                            unreadableAtFinalScan: snapshot.unreadableProcessCount,
                            contributions: window.contributions.count,
                            recentUnits: snapshot.recentActivity?.units.count ?? 0,
                            heapBytesInUse: UInt64(heap.size_in_use),
                            heapPeakBytes: heap.max_size_in_use == 0 ? nil : UInt64(heap.max_size_in_use),
                            retentionLimited: snapshot.recentActivity?.retentionLimited ?? false,
                            history: history.diagnostics, coverage: window.acquisitionCoverage,
                            processCPUSeconds: Double(
                                clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID) - cpuStart) / 1e9,
                            reapedChildCPUSeconds: childDelta(),
                            hostBusyPercent: snapshot.cpuAccounting.hostBusyPercent,
                            logicalCPUs: snapshot.cpuAccounting.logicalCPUCount,
                            measuredUserPercent: snapshot.cpuAccounting.measuredUserPercent,
                            acquisition: snapshot.cpuAccounting.acquisition))
                }
            }
        } catch { failure = String(describing: error) }
        let duration = start.duration(to: .now).components
        let periods = reader.periods.withLock { $0.values }
        let sorted = periods.sorted()
        func percentile(_ p: Double) -> Double? {
            sorted.isEmpty ? nil : sorted[max(0, Int(ceil(Double(sorted.count) * p)) - 1)]
        }
        let result = Result(
            startedAt: date,
            elapsedSeconds: Double(duration.seconds) + Double(duration.attoseconds) / 1e18,
            processCPUSeconds: Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID) - cpuStart) / 1e9,
            reapedChildCPUSeconds: childDelta(), providerListingsEnabled: providers.enabled, error: failure,
            reports: reports.withLock { $0 },
            nativeScanPeriods: periods, periodP50: percentile(0.5), periodP99: percentile(0.99),
            maximumPeriod: sorted.last, providerCalls: providers.calls.withLock { $0 },
            observedOwnRuntimeChildren: reader.ownRuntimeChildren.withLock { $0.count })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(result)
        data.append(10)
        try FileHandle.standardOutput.write(contentsOf: data)
    }
}

private final class ProfileListings: SessionRegistryReading, Sendable {
    let enabled: Bool
    let calls = Mutex(0)
    init(enabled: Bool) { self.enabled = enabled }
    func output(of query: SessionRegistryQuery) throws -> Data {
        try output(of: query, checking: {})
    }
    func output(of query: SessionRegistryQuery, checking: @escaping @Sendable () throws -> Void) throws
        -> Data
    {
        guard enabled else { return Data("[]".utf8) }
        calls.withLock { $0 += 1 }
        return try CommandSessionRegistryReader().output(of: query, checking: checking)
    }
}

private final class TimedNativeReader: ProcessReading, Sendable {
    struct Periods {
        var previous: Double?
        var values: [Double] = []
    }
    let periods = Mutex(Periods())
    let ownRuntimeChildren = Mutex<Set<ProcessIdentity>>([])
    let reader: NativeProcessReader
    init() throws { reader = try NativeProcessReader() }
    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let now = ContinuousSamplingClock().monotonicNow()
        periods.withLock { state in
            if let previous = state.previous { state.values.append(now - previous) }
            state.previous = now
        }
        let snapshot = try reader.snapshot(excluding: excluding)
        ownRuntimeChildren.withLock { seen in
            seen.formUnion(
                snapshot.samples.filter { $0.parentPID == getpid() && $0.runtimeProvider != nil }.map(
                    \.identity))
        }
        return snapshot
    }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        reader.metadata(for: sample, includeCommand: includeCommand)
    }
    func metadata(for sample: ProcessSample, includeCommand: Bool, capturedLaunch: ProcessMetadata?)
        -> ProcessMetadata
    {
        reader.metadata(for: sample, includeCommand: includeCommand, capturedLaunch: capturedLaunch)
    }
    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        reader.captureLaunchEvidence(for: sample, maximumBytes: maximumBytes)
    }
    func isCurrent(_ sample: ProcessSample) -> Bool { reader.isCurrent(sample) }
}

import AgentMonitorCore
import Darwin
import Foundation
import Synchronization

@main enum LivePipeline {
    struct WindowCoverage: Encodable, Sendable {
        let durationSeconds: Double
        let coverage: AcquisitionCoverage
    }
    struct Provenance: Encodable {
        let commit: String
        let optimizedBuild = true
        let providersEnabled: Bool
        let noConcurrentBuilds: Bool
        let requestedAcquisitionSeconds = 0.1
        let displaySeconds = 5
        let liveIntervalEnabled = true
    }
    struct Result: Encodable {
        let provenance: Provenance
        let startedAt: Date
        let elapsedSeconds: Double
        let collectorCPUSeconds: Double
        let reapedHelperCPUSeconds: Double?
        let collectorAndHelperPercentOfOneCore: Double?
        let failure: String?
        let profiling: PipelineProfile.Snapshot
        let cadence: Distribution
        let processCountRange: [Int]
        let hostBusyPercentWeightedMean: Double?
        let hostBusyPercent: Distribution
        let maximumSampledHeapBytes: UInt64
        let allocatorReportedPeakBytes: UInt64?
        let maximumHistoryChargedRecords: Int
        let maximumHistoryChargedTextBytes: Int
        let historyCapacityEvictions: Int
        let historyDiscontinuities: Int
        let retentionLimitedWindows: Int
        let providerCalls: Int
        let coverage: [WindowCoverage]
    }
    struct Distribution: Encodable {
        let count: Int
        let total: Double
        let minimum: Double?
        let p50: Double?
        let p99: Double?
        let maximum: Double?
        init(_ values: [Double]) {
            let sorted = values.sorted()
            count = values.count
            total = values.reduce(0, +)
            minimum = sorted.first
            maximum = sorted.last
            p50 = sorted.isEmpty ? nil : sorted[max(0, Int(ceil(Double(sorted.count) * 0.5)) - 1)]
            p99 = sorted.isEmpty ? nil : sorted[max(0, Int(ceil(Double(sorted.count) * 0.99)) - 1)]
        }
    }
    struct Accumulated {
        var windows: [WindowCoverage] = []
        var host: [Double] = []
        var hostWeighted = 0.0
        var hostDuration = 0.0
        var heap: UInt64 = 0
        var allocatorPeak: UInt64?
        var historyRecords = 0
        var historyText = 0
        var evictions = 0
        var discontinuities = 0
        var limited = 0
    }
    static func childCPUSeconds() -> Double? {
        var usage = rusage()
        guard getrusage(RUSAGE_CHILDREN, &usage) == 0 else { return nil }
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }
    static func main() async throws {
        guard !CommandLine.arguments.contains("--providers") else {
            throw BoundedCommandFailure(ProviderRuntimeAvailability.sessionListingUnavailableReason)
        }
        let environment = ProcessInfo.processInfo.environment
        guard let commit = environment["AGENT_MONITOR_PROFILE_COMMIT"], commit.count == 40,
            commit.allSatisfy({ $0.isHexDigit }), environment["AGENT_MONITOR_PROFILE_NO_BUILDS"] == "1"
        else { throw ProfileError.missingProvenance }
        let reports = Mutex(Accumulated())
        let start = ContinuousClock.now
        let date = Date()
        let profile = PipelineProfile()
        let reader = try TimedNativeReader(profile: profile)
        let history = RecentActivityStore()
        let registry = OfflineSessionRegistryReader()
        let cpuStart = clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)
        let childCPUStart = childCPUSeconds()
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                intervalSeconds: 0.1,
                samples: CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 121,
                collectAgentLoad: true, reportIntervalSeconds: 5),
            reader: reader, clock: ContinuousSamplingClock(), registry: registry,
            excluding: [getpid()], recentActivity: history
        ).profiling(profile)
        var failure: String?
        do {
            try await session.run(interval: LiveInterval(0.1)) { snapshot in
                guard let window = snapshot.window else { return }
                var heap = malloc_statistics_t()
                malloc_zone_statistics(nil, &heap)
                let progress =
                    "window \(window.durationSeconds) s · \(snapshot.sampledProcessCount) processes · max gap \(window.acquisitionCoverage.maximumGapSeconds ?? 0) s · \(window.acquisitionCoverage.overrunCount) overruns\n"
                try FileHandle.standardError.write(contentsOf: Data(progress.utf8))
                let diagnostics = history.diagnostics
                reports.withLock { state in
                    state.windows.append(
                        WindowCoverage(
                            durationSeconds: window.durationSeconds, coverage: window.acquisitionCoverage))
                    if let host = snapshot.cpuAccounting.hostBusyPercent {
                        state.host.append(host)
                        state.hostWeighted += host * window.durationSeconds
                        state.hostDuration += window.durationSeconds
                    }
                    state.heap = max(state.heap, UInt64(heap.size_in_use))
                    if heap.max_size_in_use > 0 {
                        state.allocatorPeak = max(state.allocatorPeak ?? 0, UInt64(heap.max_size_in_use))
                    }
                    state.historyRecords = max(state.historyRecords, diagnostics.chargedRecords)
                    state.historyText = max(state.historyText, diagnostics.chargedTextBytes)
                    state.evictions = diagnostics.capacityEvictions
                    state.discontinuities = diagnostics.discontinuities
                    if snapshot.recentActivity?.retentionLimited == true { state.limited += 1 }
                }
            }
        } catch is CancellationError { failure = "cancelled" } catch is MonitoringError {
            failure = "monitoringError"
        } catch { failure = "otherError" }
        let duration = start.duration(to: .now).components
        let elapsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        let cpu = Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID) - cpuStart) / 1e9
        let childCPU = childCPUStart.flatMap { baseline in childCPUSeconds().map { $0 - baseline } }
        let native = reader.periods.withLock { $0 }
        let state = reports.withLock { $0 }
        let measuredProfile = profile.snapshot()
        let result = Result(
            provenance: Provenance(
                commit: commit, providersEnabled: registry.isAvailable, noConcurrentBuilds: true),
            startedAt: date, elapsedSeconds: elapsed, collectorCPUSeconds: cpu,
            reapedHelperCPUSeconds: childCPU,
            collectorAndHelperPercentOfOneCore: childCPU.map { 100 * (cpu + $0) / elapsed },
            failure: failure, profiling: measuredProfile, cadence: Distribution(native.values),
            processCountRange: [native.minimumPopulation ?? 0, native.maximumPopulation],
            hostBusyPercentWeightedMean: state.hostDuration > 0
                ? state.hostWeighted / state.hostDuration : nil,
            hostBusyPercent: Distribution(state.host), maximumSampledHeapBytes: state.heap,
            allocatorReportedPeakBytes: state.allocatorPeak,
            maximumHistoryChargedRecords: state.historyRecords,
            maximumHistoryChargedTextBytes: state.historyText, historyCapacityEvictions: state.evictions,
            historyDiscontinuities: state.discontinuities, retentionLimitedWindows: state.limited,
            providerCalls: measuredProfile.stages["providerRequest"]?.count ?? 0, coverage: state.windows)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(result)
        data.append(10)
        try FileHandle.standardOutput.write(contentsOf: data)
    }
    enum ProfileError: Error { case missingProvenance }
}

private final class TimedNativeReader: ProcessReading, Sendable {
    struct Periods {
        var previous: Double?
        var values: [Double] = []
        var minimumPopulation: Int?
        var maximumPopulation = 0
    }
    let periods = Mutex(Periods())
    let reader: NativeProcessReader
    init(profile: PipelineProfile) throws { reader = try NativeProcessReader().profiling(profile) }
    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let now = ContinuousSamplingClock().monotonicNow()
        let snapshot = try reader.snapshot(excluding: excluding)
        periods.withLock { state in
            if let previous = state.previous { state.values.append(now - previous) }
            state.previous = now
            state.minimumPopulation = min(
                state.minimumPopulation ?? snapshot.samples.count, snapshot.samples.count)
            state.maximumPopulation = max(state.maximumPopulation, snapshot.samples.count)
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

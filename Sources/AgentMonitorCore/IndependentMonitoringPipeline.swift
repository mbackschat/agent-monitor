import Foundation
import Synchronization

public enum AcquisitionQualityOfService: String, Codable, Sendable { case userInitiated }

public struct AcquisitionTiming: Equatable, Codable, Sendable {
    public let runID: UUID
    public let scanSequence: UInt64
    public let qualityOfService: AcquisitionQualityOfService
    public let requestedPeriodSeconds: Double
    public let achievedPeriodSeconds: Double?
    public let scanWorkSeconds: Double
    public let resolutionDelaySeconds: Double
    public let promptCapture: PromptCaptureSummary?

    public init(
        runID: UUID, scanSequence: UInt64, qualityOfService: AcquisitionQualityOfService,
        requestedPeriodSeconds: Double, achievedPeriodSeconds: Double?, scanWorkSeconds: Double,
        resolutionDelaySeconds: Double, promptCapture: PromptCaptureSummary? = nil
    ) {
        self.runID = runID
        self.scanSequence = scanSequence
        self.qualityOfService = qualityOfService
        self.requestedPeriodSeconds = requestedPeriodSeconds
        self.achievedPeriodSeconds = achievedPeriodSeconds
        self.scanWorkSeconds = scanWorkSeconds
        self.resolutionDelaySeconds = resolutionDelaySeconds
        self.promptCapture = promptCapture
    }
}

private final class PipelineCancellation: Sendable {
    private let stopped = Mutex(false)
    func cancel() { stopped.withLock { $0 = true } }
    func check() throws {
        if stopped.withLock({ $0 }) { throw CancellationError() }
    }
}

private struct AcquiredScan: Sendable {
    let snapshot: ProcessSnapshot
    let counters: CounterScan
    let timestamp: Date
    let startedAt: Double
    let finishedAt: Double
    let interval: Double
    let achievedPeriod: Double?
}

private struct AcquisitionState: Sendable {
    var ledger = CounterLedger()
    var previousStart: Double?
    var promptCapture = PromptEvidenceCapture()
    var sequence: UInt64 = 0
}

private struct ResolutionState: Sendable {
    var monitor = Monitor()
    var cadence = SessionRegistryCadence()
}

private struct ResolvedScan: Sendable {
    let acquired: AcquiredScan
    let accounting: CPUAccounting
    let findings: [HeavyProcess]
    let agentLoad: AgentLoadSummary?
}

struct IndependentMonitoringPipeline: Sendable {
    let configuration: MonitoringConfiguration
    let reader: any ProcessReading
    let clock: any SamplingClock
    let registry: any SessionRegistryReading
    let excluded: Set<Int32>

    func run(
        thresholds currentThresholds: (@Sendable () async -> Thresholds)?, interval live: LiveInterval?,
        _ receive: @Sendable (MonitoringSnapshot) async throws -> Void
    ) async throws {
        try Task.checkCancellation()
        let cancellation = PipelineCancellation()
        let acquisition = SerialBlockingWorker(name: "AgentMonitor acquisition", initial: AcquisitionState())
        let resolution = SerialBlockingWorker(name: "AgentMonitor resolution", initial: ResolutionState())
        let scans = MonitoringChannel<AcquiredScan>(stage: .resolution, limits: configuration.pipelineLimits)
        let reports = MonitoringChannel<ResolvedScan>(
            stage: .presentation, limits: configuration.pipelineLimits)
        do {
            try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        await acquire(
                            on: acquisition, into: scans, interval: live, cancellation: cancellation)
                    }
                    group.addTask {
                        await resolve(from: scans, on: resolution, into: reports, cancellation: cancellation)
                    }
                    do {
                        while let report = try await reports.next() {
                            try Task.checkCancellation()
                            let thresholds = await currentThresholds?() ?? configuration.thresholds
                            guard thresholds.cpuPercent.isFinite, thresholds.cpuPercent >= 0 else {
                                throw MonitoringError.invalidConfiguration
                            }
                            try await receive(
                                MonitoringSnapshot(
                                    cpuAccounting: report.accounting, timestamp: report.acquired.timestamp,
                                    intervalSeconds: report.acquired.interval,
                                    cpuThresholdPercent: thresholds.cpuPercent,
                                    memoryThresholdBytes: thresholds.memoryBytes,
                                    sampledProcessCount: report.acquired.snapshot.samples.count,
                                    unreadableProcessCount: report.acquired.snapshot.unreadableCount,
                                    findings: report.findings.filter {
                                        thresholds.includes(cpu: $0.cpuPercent, footprint: $0.footprintBytes)
                                    },
                                    agentLoad: report.agentLoad, observedFindings: report.findings))
                        }
                        try await group.waitForAll()
                    } catch {
                        cancellation.cancel()
                        group.cancelAll()
                        await scans.cancel()
                        await reports.cancel()
                        throw error
                    }
                }
            } onCancel: {
                cancellation.cancel()
            }
        } catch {
            await acquisition.close()
            await resolution.close()
            throw error
        }
        await acquisition.close()
        await resolution.close()
    }

    private func acquire(
        on worker: SerialBlockingWorker<AcquisitionState>, into scans: MonitoringChannel<AcquiredScan>,
        interval live: LiveInterval?, cancellation: PipelineCancellation
    ) async {
        do {
            var interval = live?.seconds ?? configuration.intervalSeconds
            guard interval.isFinite, (0.1...60).contains(interval) else {
                throw MonitoringError.invalidConfiguration
            }
            var count = 0
            while true {
                try cancellation.check()
                let requested = interval
                let scan = try await worker.perform { state in
                    try cancellation.check()
                    let start = clock.monotonicNow()
                    let raw = try reader.snapshot(excluding: excluded)
                    try cancellation.check()
                    let evidence = state.promptCapture.capture(
                        raw.samples, sequence: state.sequence, using: reader, clock: clock,
                        limits: configuration.promptCaptureLimits)
                    state.sequence += 1
                    let snapshot = ProcessSnapshot(
                        samples: raw.samples, enumeratedCount: raw.enumeratedCount,
                        unreadableCount: raw.unreadableCount,
                        listedAt: raw.listedAt, scanSeconds: raw.scanSeconds, hostCounters: raw.hostCounters,
                        logicalCPUCount: raw.logicalCPUCount, nativeOutcomes: raw.nativeOutcomes,
                        nativeTiming: raw.nativeTiming, promptEvidence: evidence)
                    try cancellation.check()
                    let counters = state.ledger.ingest(
                        snapshot.samples, listedAt: snapshot.listedAt, scanSeconds: snapshot.scanSeconds,
                        source: snapshot)
                    let period = state.previousStart.map { max(0, start - $0) }
                    state.previousStart = start
                    return AcquiredScan(
                        snapshot: snapshot, counters: counters, timestamp: clock.now(), startedAt: start,
                        finishedAt: clock.monotonicNow(), interval: requested, achievedPeriod: period)
                }
                try await scans.send(
                    scan, size: MonitoringPayloadSize(scan.snapshot), sequence: scan.counters.id.sequence)
                if configuration.samples > 0, count == configuration.samples { break }
                count += 1
                interval = try await wait(live, since: scan.startedAt)
            }
            await scans.finish()
        } catch {
            await scans.finish(throwing: error)
        }
    }

    private func resolve(
        from scans: MonitoringChannel<AcquiredScan>, on worker: SerialBlockingWorker<ResolutionState>,
        into reports: MonitoringChannel<ResolvedScan>, cancellation: PipelineCancellation
    ) async {
        do {
            while let scan = try await scans.next() {
                let result = try await worker.perform { state -> ResolvedScan? in
                    try cancellation.check()
                    let accounting = state.monitor.ingest(scan.snapshot, accounting: scan.counters)
                    for evidence in scan.snapshot.promptEvidence where evidence.status == .captured {
                        if let metadata = evidence.metadata {
                            state.monitor.enrich(metadata, for: evidence.process)
                        }
                    }
                    guard scan.counters.id.sequence > 0 else { return nil }
                    let prompt = Dictionary(
                        scan.snapshot.promptEvidence.filter { $0.status == .captured }.map {
                            ($0.process, $0.metadata)
                        },
                        uniquingKeysWith: { first, _ in first })
                    for sample in scan.snapshot.samples {
                        try cancellation.check()
                        state.monitor.enrich(
                            reader.metadata(
                                for: sample, includeCommand: configuration.includeCommands,
                                capturedLaunch: prompt[sample.identity] ?? nil), for: sample.identity)
                    }
                    var findings = state.monitor.findings(scope: configuration.scope)
                    try listSessions(for: findings, scan: scan, state: &state, cancellation: cancellation)
                    findings = state.monitor.findings(scope: configuration.scope)
                    let timing = AcquisitionTiming(
                        runID: scan.counters.id.runID, scanSequence: scan.counters.id.sequence,
                        qualityOfService: .userInitiated, requestedPeriodSeconds: scan.interval,
                        achievedPeriodSeconds: scan.achievedPeriod,
                        scanWorkSeconds: max(0, scan.finishedAt - scan.startedAt),
                        resolutionDelaySeconds: max(0, clock.monotonicNow() - scan.finishedAt),
                        promptCapture: PromptCaptureSummary(scan.snapshot.promptEvidence))
                    return ResolvedScan(
                        acquired: scan, accounting: accounting.withAcquisition(timing), findings: findings,
                        agentLoad: configuration.collectAgentLoad ? state.monitor.agentLoad() : nil)
                }
                if let result {
                    var size = MonitoringPayloadSize(result.findings)
                    let rawSize = MonitoringPayloadSize(scan.snapshot)
                    size.observations += rawSize.observations
                    size.textBytes += rawSize.textBytes
                    try await reports.send(result, size: size, sequence: scan.counters.id.sequence)
                }
            }
            await reports.finish()
        } catch {
            await scans.cancel()
            await reports.finish(throwing: error)
        }
    }

    private func listSessions(
        for findings: [HeavyProcess], scan: AcquiredScan, state: inout ResolutionState,
        cancellation: PipelineCancellation
    ) throws {
        let samples = Dictionary(
            scan.snapshot.samples.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
        for (provider, runtimes) in state.monitor.sessionRegistryRuntimes(in: findings)
        where state.cadence.due(provider, runtimes: runtimes, at: scan.timestamp) {
            guard let query = state.monitor.sessionRegistry(for: provider) else { continue }
            try cancellation.check()
            let output: Data?
            do {
                output = try registry.output(of: query, checking: cancellation.check)
            } catch is CancellationError {
                throw CancellationError()
            } catch { output = nil }
            try cancellation.check()
            let verified = Set(
                runtimes.filter { identity in samples[identity].map(reader.isCurrent) ?? false })
            state.monitor.bindSessions(output, provider: provider, restrictingTo: verified)
        }
    }

    private func wait(_ live: LiveInterval?, since start: Double) async throws -> Double {
        while true {
            try Task.checkCancellation()
            let (interval, generation) = live?.current() ?? (configuration.intervalSeconds, 0)
            guard interval.isFinite, (0.1...60).contains(interval) else {
                throw MonitoringError.invalidConfiguration
            }
            let remaining = interval - max(0, clock.monotonicNow() - start)
            guard remaining > 0 else { return interval }
            guard let live else {
                try await clock.wait(seconds: remaining)
                return interval
            }
            let changed = try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    try await clock.wait(seconds: remaining)
                    return false
                }
                group.addTask {
                    await live.changed(after: generation)
                    return true
                }
                defer { group.cancelAll() }
                return try await group.next() ?? false
            }
            try Task.checkCancellation()
            if !changed { return interval }
        }
    }
}

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
    var window: AccountingWindow?
    var pending: ResolvedScan?
    var recent: RecentActivityAccumulator?
}

private struct ResolvedScan: Sendable {
    let acquired: AcquiredScan
    let accounting: CPUAccounting
    let findings: [HeavyProcess]
    let window: AccountingWindow?
    var recent: RecentActivitySnapshot? = nil

    static func coalesced(_ old: ResolvedScan, _ new: ResolvedScan) throws -> (
        ResolvedScan, MonitoringPayloadSize
    ) {
        guard var window = old.window, let next = new.window else {
            preconditionFailure("Only accounting windows may coalesce")
        }
        try window.merge(next)
        return (
            ResolvedScan(
                acquired: new.acquired, accounting: new.accounting, findings: [],
                window: window, recent: new.recent?.coalescing(old.recent)), window.payloadSize
        )
    }
}

struct IndependentMonitoringPipeline: Sendable {
    let configuration: MonitoringConfiguration
    let reader: any ProcessReading
    let clock: any SamplingClock
    let registry: any SessionRegistryReading
    let excluded: Set<Int32>
    var recentActivity: RecentActivityStore? = nil

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
            stage: .presentation, limits: configuration.pipelineLimits,
            coalesce: configuration.reportIntervalSeconds == nil ? nil : ResolvedScan.coalesced)
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
                        var lastDelivery: ContinuousClock.Instant?
                        while true {
                            if await reports.isDrained {
                                _ = try await reports.next()
                                break
                            }
                            if let lastDelivery, let period = configuration.reportIntervalSeconds {
                                try await ContinuousClock().sleep(
                                    until: lastDelivery.advanced(by: .seconds(period)))
                            }
                            guard let report = try await reports.next() else { break }
                            try Task.checkCancellation()
                            let thresholds = await currentThresholds?() ?? configuration.thresholds
                            guard thresholds.cpuPercent.isFinite, thresholds.cpuPercent >= 0 else {
                                throw MonitoringError.invalidConfiguration
                            }
                            let projection = try report.window?.projection(scope: configuration.scope)
                            let rows = projection?.rows ?? report.findings
                            let summary = projection?.summary
                            let accounting: CPUAccounting
                            if let summary, let window = report.window {
                                let measured = projection?.counters.cpuSeconds ?? 0
                                accounting = CPUAccounting(
                                    hostBusyPercent: window.final.source?.hostCounters?.busyPercent(
                                        since: window.baseline.source?.hostCounters),
                                    logicalCPUCount: report.accounting.logicalCPUCount,
                                    measuredUserPercent: summary.durationSeconds > 0
                                        ? 100 * measured / summary.durationSeconds : 0,
                                    unmeasuredLifetimeCount: summary.unmeasuredLifetimeCount,
                                    previousScanSeconds: report.accounting.previousScanSeconds,
                                    acquisition: report.accounting.acquisition)
                            } else {
                                accounting = report.accounting
                            }
                            try await receive(
                                MonitoringSnapshot(
                                    cpuAccounting: accounting, timestamp: report.acquired.timestamp,
                                    intervalSeconds: report.acquired.interval,
                                    cpuThresholdPercent: thresholds.cpuPercent,
                                    memoryThresholdBytes: thresholds.memoryBytes,
                                    sampledProcessCount: report.acquired.snapshot.samples.count,
                                    unreadableProcessCount: report.acquired.snapshot.unreadableCount,
                                    findings: rows.filter {
                                        thresholds.includes(
                                            cpu: $0.cpuPercent,
                                            footprint: $0.isHistorical
                                                ? $0.accounting?.lastObservedFootprintBytes
                                                : $0.footprintBytes)
                                            || ($0.accounting?.recoveredCPUSeconds ?? 0) > 0
                                    },
                                    agentLoad: configuration.collectAgentLoad
                                        ? AgentLoadSummary(processes: rows, window: summary) : nil,
                                    observedFindings: rows, window: summary, recentActivity: report.recent))
                            lastDelivery = .now
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
            var windowStart: Double?
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
                if let refresh = configuration.reportIntervalSeconds {
                    let listed = scan.counters.listedAt ?? scan.startedAt
                    if let start = windowStart {
                        if listed - start + 1e-9 >= refresh {
                            count += 1
                            windowStart = listed
                        }
                    } else {
                        windowStart = listed
                    }
                    if configuration.samples > 0, count >= configuration.samples { break }
                } else {
                    if configuration.samples > 0, count == configuration.samples { break }
                    count += 1
                }
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
                            state.monitor.enrich(
                                metadata, for: evidence.process, observedAt: evidence.observedAt)
                        }
                    }
                    guard scan.counters.id.sequence > 0 else {
                        if configuration.reportIntervalSeconds != nil {
                            state.window = AccountingWindow(baseline: scan.counters)
                            state.pending = nil
                            if recentActivity != nil {
                                state.recent = RecentActivityAccumulator(baseline: scan.counters)
                            }
                        }
                        return nil
                    }
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
                                capturedLaunch: prompt[sample.identity] ?? nil), for: sample.identity,
                            observedAt: clock.monotonicNow(),
                            launchObservedAt: scan.snapshot.promptEvidence.first {
                                $0.process == sample.identity && $0.status == .captured
                            }?.observedAt)
                    }
                    var findings = state.monitor.findings(scope: .allProcesses)
                    try listSessions(for: findings, scan: scan, state: &state, cancellation: cancellation)
                    findings = state.monitor.findings(scope: .allProcesses)
                    let timing = AcquisitionTiming(
                        runID: scan.counters.id.runID, scanSequence: scan.counters.id.sequence,
                        qualityOfService: .userInitiated, requestedPeriodSeconds: scan.interval,
                        achievedPeriodSeconds: scan.achievedPeriod,
                        scanWorkSeconds: max(0, scan.finishedAt - scan.startedAt),
                        resolutionDelaySeconds: max(0, clock.monotonicNow() - scan.finishedAt),
                        promptCapture: PromptCaptureSummary(scan.snapshot.promptEvidence))
                    var window: AccountingWindow?
                    var recent = state.recent
                    recent?.append(
                        scan.counters, rows: findings,
                        runtimes: state.monitor.agentRuntimeIdentities,
                        attributionTimes: state.monitor.attributionObservationTimes())
                    if let refresh = configuration.reportIntervalSeconds {
                        guard var accumulated = state.window else { return nil }
                        try accumulated.append(
                            scan.counters, rows: findings,
                            attributionTimes: state.monitor.attributionObservationTimes())
                        var size = accumulated.payloadSize
                        if let extra = recent?.payloadSize {
                            size.observations += extra.observations
                            size.textBytes += extra.textBytes
                        }
                        guard size.observations <= configuration.pipelineLimits.pendingObservations,
                            size.textBytes <= configuration.pipelineLimits.pendingTextBytes
                        else {
                            throw MonitoringError.overloaded(
                                stage: .presentation, rejectedScan: scan.counters.id.sequence)
                        }
                        state.window = accumulated
                        state.recent = recent
                        state.pending = ResolvedScan(
                            acquired: scan, accounting: accounting.withAcquisition(timing), findings: [],
                            window: accumulated)
                        let opening =
                            accumulated.baseline.listedAt ?? accumulated.baseline.observations.map(
                                \.sample.sampledAt
                            ).min() ?? scan.startedAt
                        guard (scan.counters.listedAt ?? scan.startedAt) - opening + 1e-9 >= refresh else {
                            return nil
                        }
                        window = accumulated
                        if let recent = state.recent {
                            recentActivity?.append(
                                recent.seal(scope: configuration.scope),
                                current: recent.current, present: recent.present)
                            state.recent = RecentActivityAccumulator(baseline: scan.counters)
                        }
                        state.window = AccountingWindow(baseline: scan.counters)
                        state.pending = nil
                    }
                    return ResolvedScan(
                        acquired: scan, accounting: accounting.withAcquisition(timing),
                        findings: window == nil
                            ? findings.filter { configuration.scope.includes($0.attribution) } : [],
                        window: window, recent: recentActivity?.snapshot())
                }
                if let result {
                    var size = MonitoringPayloadSize(result.findings)
                    let rawSize = MonitoringPayloadSize(scan.snapshot)
                    size.observations += rawSize.observations
                    size.textBytes += rawSize.textBytes
                    try await reports.send(
                        result, size: result.window?.payloadSize ?? size,
                        sequence: result.window.map { $0.baseline.id.sequence + 1 }
                            ?? scan.counters.id.sequence)
                }
            }
            await reports.finish()
        } catch {
            await scans.cancel()
            if let pending = try? await worker.perform({ state in
                var pending = state.pending
                if let recent = state.recent, pending != nil {
                    recentActivity?.append(
                        recent.seal(scope: configuration.scope),
                        current: recent.current, present: recent.present)
                    pending?.recent = recentActivity?.snapshot()
                }
                state.pending = nil
                return pending
            }), let window = pending.window {
                do {
                    try await reports.send(
                        pending, size: window.payloadSize, sequence: window.baseline.id.sequence + 1)
                } catch {
                    await reports.finish(throwing: error)
                    return
                }
            }
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
            state.monitor.bindSessions(
                output, provider: provider, restrictingTo: verified, observedAt: clock.monotonicNow())
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

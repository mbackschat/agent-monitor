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
    var resolution = ResolutionState()
    var previousStart: Double?
    var promptCapture = PromptEvidenceCapture()
    var sequence: UInt64 = 0
}

private struct ResolutionState: Sendable {
    var monitor = Monitor()
    var cadence = SessionRegistryCadence()
    var window: AccountingWindow?
    var latest: ResolvedScan?
    var display: AccountingWindow?
    var published = false
}

private struct ReportEndpoint: Sendable {
    let timestamp: Date
    let interval: Double
    let sampledCount: Int
    let unreadableCount: Int
}

private struct ResolvedScan: Sendable {
    var acquired: ReportEndpoint
    var accounting: CPUAccounting
    let findings: [HeavyProcess]
    var window: AccountingWindow?
    var recent: RecentActivitySnapshot? = nil

    static func coalesced(_ old: inout ResolvedScan, _ new: ResolvedScan, limits: MonitoringPipelineLimits)
        throws -> MonitoringPayloadSize
    {
        guard old.window != nil, let next = new.window else {
            preconditionFailure("Only accounting windows may coalesce")
        }
        try old.window?.merge(next)
        let size = old.window!.compact(to: limits)
        old.acquired = new.acquired
        old.accounting = new.accounting
        old.recent = new.recent
        return size
    }
}

extension ResolvedScan {
    fileprivate init(
        acquired: AcquiredScan, accounting: CPUAccounting, findings: [HeavyProcess],
        window: AccountingWindow?, recent: RecentActivitySnapshot? = nil
    ) {
        self.init(
            acquired: ReportEndpoint(
                timestamp: acquired.timestamp, interval: acquired.interval,
                sampledCount: acquired.snapshot.samples.count,
                unreadableCount: acquired.snapshot.unreadableCount),
            accounting: accounting, findings: findings, window: window, recent: recent)
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
        let enrichment = PipelineEnrichment()
        let acquisition = SerialBlockingWorker(name: "AgentMonitor acquisition", initial: AcquisitionState())
        let limits = configuration.pipelineLimits
        let coalesce: (@Sendable (inout ResolvedScan, ResolvedScan) throws -> MonitoringPayloadSize)?
        if configuration.reportIntervalSeconds == nil {
            coalesce = nil
        } else {
            coalesce = { old, new in try ResolvedScan.coalesced(&old, new, limits: limits) }
        }
        let reports = MonitoringChannel<ResolvedScan>(
            stage: .presentation, limits: limits, coalesce: coalesce)
        do {
            try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        await collect(
                            on: acquisition, into: reports, interval: live,
                            enrichment: enrichment, cancellation: cancellation)
                    }
                    group.addTask {
                        try await enrichment.refreshMetadata(
                            reader: reader, clock: clock, includeCommand: configuration.includeCommands,
                            checking: cancellation.check)
                    }
                    group.addTask {
                        try await enrichment.refreshRegistries(
                            reader: reader, registry: registry, clock: clock, checking: cancellation.check)
                    }
                    do {
                        while true {
                            if await reports.isDrained {
                                _ = try await reports.next()
                                break
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
                                let measured =
                                    (projection?.counters.cpuSeconds ?? 0) + window.collapsedCPUSeconds
                                accounting = CPUAccounting(
                                    hostBusyPercent: window.final.source?.hostCounters?.busyPercent(
                                        since: window.baseline.source?.hostCounters),
                                    logicalCPUCount: report.accounting.logicalCPUCount,
                                    measuredUserPercent: summary.durationSeconds > 0
                                        ? 100 * measured / summary.durationSeconds : 0,
                                    unmeasuredLifetimeCount: summary.unmeasuredLifetimeCount,
                                    previousScanSeconds: report.accounting.previousScanSeconds,
                                    acquisition: report.accounting.acquisition,
                                    unmeasuredLifetimeCountRange: summary.unmeasuredLifetimeCountRange)
                            } else {
                                accounting = report.accounting
                            }
                            try await receive(
                                MonitoringSnapshot(
                                    cpuAccounting: accounting, timestamp: report.acquired.timestamp,
                                    intervalSeconds: report.acquired.interval,
                                    cpuThresholdPercent: thresholds.cpuPercent,
                                    memoryThresholdBytes: thresholds.memoryBytes,
                                    sampledProcessCount: report.acquired.sampledCount,
                                    unreadableProcessCount: report.acquired.unreadableCount,
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
                                    observedFindings: rows, window: summary,
                                    recentActivity: report.recent.map { recent in
                                        report.window.map {
                                            recent.displaying($0.seal(scope: configuration.scope))
                                        } ?? recent
                                    }))
                        }
                        try await group.waitForAll()
                    } catch {
                        enrichment.finish()
                        cancellation.cancel()
                        group.cancelAll()
                        await reports.cancel()
                        throw error
                    }
                }
            } onCancel: {
                cancellation.cancel()
            }
        } catch {
            await acquisition.close()
            throw error
        }
        await acquisition.close()
    }

    private func collect(
        on worker: SerialBlockingWorker<AcquisitionState>, into reports: MonitoringChannel<ResolvedScan>,
        interval live: LiveInterval?, enrichment: PipelineEnrichment, cancellation: PipelineCancellation
    ) async {
        defer { enrichment.finish() }
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
                    let scan = AcquiredScan(
                        snapshot: snapshot, counters: counters, timestamp: clock.now(), startedAt: start,
                        finishedAt: clock.monotonicNow(), interval: requested, achievedPeriod: period)
                    let report = try resolve(
                        scan, state: &state.resolution,
                        enrichment: enrichment, cancellation: cancellation)
                    return (startedAt: start, sequence: counters.id.sequence, report: report)
                }
                if let report = scan.report {
                    try await reports.send(
                        report, size: report.window?.payloadSize ?? MonitoringPayloadSize(report.findings),
                        sequence: report.window.map { $0.baseline.id.sequence + 1 } ?? scan.sequence)
                    count += 1
                    if configuration.samples > 0, count >= configuration.samples { break }
                }
                interval = try await wait(live, since: scan.startedAt)
            }
            if let pending = try await drainPending(on: worker), let window = pending.window {
                try await reports.send(
                    pending, size: window.payloadSize, sequence: window.baseline.id.sequence + 1)
            }
            await reports.finish()
        } catch {
            if let pending = try? await drainPending(on: worker), let window = pending.window {
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

    private func resolve(
        _ scan: AcquiredScan, state: inout ResolutionState,
        enrichment: PipelineEnrichment, cancellation: PipelineCancellation
    ) throws -> ResolvedScan? {
        try cancellation.check()
        let accounting = state.monitor.ingest(scan.snapshot, accounting: scan.counters)
        for evidence in scan.snapshot.promptEvidence where evidence.status == .captured {
            if let metadata = evidence.metadata {
                state.monitor.enrich(
                    metadata, for: evidence.process, observedAt: evidence.observedAt)
            }
        }
        let samples = Dictionary(
            scan.snapshot.samples.map { ($0.identity, $0) }, uniquingKeysWith: { _, last in last })
        let (metadata, registries) = enrichment.takeResults()
        for result in metadata {
            guard let current = samples[result.sample.identity],
                current.executable == result.sample.executable,
                current.name == result.sample.name
            else { continue }
            state.monitor.enrich(
                result.metadata, for: result.sample.identity, observedAt: result.observedAt,
                launchObservedAt: result.launchObservedAt)
        }
        for result in registries {
            state.monitor.bindSessions(
                result.output, provider: result.provider,
                restrictingTo: result.verified.intersection(samples.keys), observedAt: result.observedAt)
        }
        enrichment.requestMetadata(
            MetadataRefreshRequest(
                samples: scan.snapshot.samples,
                prompt: Dictionary(
                    scan.snapshot.promptEvidence.filter { $0.status == .captured }
                        .map { ($0.process, $0) }, uniquingKeysWith: { _, last in last }),
                requestedAt: scan.finishedAt))
        let findings = state.monitor.findings(scope: .allProcesses)
        var queries: [RegistryRefreshRequest] = []
        for (provider, runtimes) in state.monitor.sessionRegistryRuntimes(
            in: findings, excludingChildrenOf: getpid())
        where state.cadence.due(provider, runtimes: runtimes, at: scan.timestamp) {
            if let query = state.monitor.sessionRegistry(for: provider) {
                queries.append(
                    RegistryRefreshRequest(
                        provider: provider, query: query, samples: runtimes.compactMap { samples[$0] }))
            }
        }
        enrichment.requestRegistries(queries)
        guard scan.counters.id.sequence > 0 else {
            if configuration.reportIntervalSeconds != nil {
                state.window = AccountingWindow(baseline: scan.counters)
            }
            return nil
        }
        let timing = AcquisitionTiming(
            runID: scan.counters.id.runID, scanSequence: scan.counters.id.sequence,
            qualityOfService: .userInitiated, requestedPeriodSeconds: scan.interval,
            achievedPeriodSeconds: scan.achievedPeriod,
            scanWorkSeconds: max(0, scan.finishedAt - scan.startedAt),
            resolutionDelaySeconds: max(0, clock.monotonicNow() - scan.finishedAt),
            promptCapture: PromptCaptureSummary(scan.snapshot.promptEvidence))
        var window: AccountingWindow?
        if let refresh = configuration.reportIntervalSeconds {
            let times = state.monitor.attributionObservationTimes(for: findings)
            // Keep the last admitted partial intact until the next scan fits; a failed
            // admission must drain it with its matching endpoint (CPU-01 accounting contract).
            guard var accumulated = state.window else { return nil }
            try accumulated.append(
                scan.counters, rows: findings, attributionTimes: times,
                runtimes: state.monitor.agentRuntimeIdentities, timing: timing)
            let size = accumulated.compact(to: configuration.pipelineLimits)
            guard size.observations <= configuration.pipelineLimits.pendingObservations,
                size.textBytes <= configuration.pipelineLimits.pendingTextBytes
            else {
                throw MonitoringError.overloaded(
                    stage: .accounting, rejectedScan: scan.counters.id.sequence)
            }
            state.window = accumulated
            state.latest = ResolvedScan(
                acquired: scan, accounting: accounting.withAcquisition(timing), findings: [], window: nil)
            let opening = accumulated.baseline.listedAt ?? scan.startedAt
            guard (scan.counters.listedAt ?? scan.startedAt) - opening + 1e-9 >= min(1, refresh) else {
                return nil
            }
            recentActivity?.append(
                accumulated.seal(scope: configuration.scope),
                current: accumulated.current, present: accumulated.present)
            if state.display == nil {
                state.display = accumulated
            } else {
                try state.display?.merge(accumulated)
            }
            state.window = AccountingWindow(baseline: scan.counters)
            state.display?.compact(to: configuration.pipelineLimits)
            guard let display = state.display else { return nil }
            let start = display.baseline.listedAt ?? opening
            let period = state.published ? refresh : min(1, refresh)
            guard (scan.counters.listedAt ?? scan.startedAt) - start + 1e-9 >= period else {
                return nil
            }
            window = display
            state.display = nil
            state.published = true
        }
        return ResolvedScan(
            acquired: scan, accounting: accounting.withAcquisition(timing),
            findings: window == nil
                ? findings.filter { configuration.scope.includes($0.attribution) } : [],
            window: window,
            recent: recentActivity?.snapshot())
    }

    private func drainPending(on worker: SerialBlockingWorker<AcquisitionState>) async throws -> ResolvedScan?
    {
        try await worker.perform { collection in
            var state = collection.resolution
            defer {
                state.window = nil
                state.display = nil
                collection.resolution = state
            }
            guard let latest = state.latest else { return Optional<ResolvedScan>.none }
            var display = state.display
            if let partial = state.window, partial.final.id.sequence > partial.baseline.id.sequence {
                recentActivity?.append(
                    partial.seal(scope: configuration.scope), current: partial.current,
                    present: partial.present)
                if display == nil { display = partial } else { try display?.merge(partial) }
            }
            guard let display else { return nil }
            state.display = nil
            return ResolvedScan(
                acquired: latest.acquired, accounting: latest.accounting, findings: [], window: display,
                recent: recentActivity?.snapshot())
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

import Foundation
import Synchronization

public enum AcquisitionQualityOfService: String, Codable, Sendable { case userInitiated }

public struct AcquisitionTiming: Equatable, Codable, Sendable {
    public let runID: UUID
    public let scanSequence: UInt64
    public let qualityOfService: AcquisitionQualityOfService
    public let requestedPeriodSeconds: Double
    public let effectivePeriodSeconds: Double
    public let achievedPeriodSeconds: Double?
    public let scanWorkSeconds: Double
    public let resolutionDelaySeconds: Double
    public let promptCapture: PromptCaptureSummary?
    public let sampling: SamplingCoverage

    public init(
        runID: UUID, scanSequence: UInt64, qualityOfService: AcquisitionQualityOfService,
        requestedPeriodSeconds: Double, achievedPeriodSeconds: Double?, scanWorkSeconds: Double,
        resolutionDelaySeconds: Double, promptCapture: PromptCaptureSummary? = nil,
        sampling: SamplingCoverage = SamplingCoverage(), effectivePeriodSeconds: Double? = nil
    ) {
        self.runID = runID
        self.scanSequence = scanSequence
        self.qualityOfService = qualityOfService
        self.requestedPeriodSeconds = requestedPeriodSeconds
        self.effectivePeriodSeconds = effectivePeriodSeconds ?? requestedPeriodSeconds
        self.achievedPeriodSeconds = achievedPeriodSeconds
        self.scanWorkSeconds = scanWorkSeconds
        self.resolutionDelaySeconds = resolutionDelaySeconds
        self.promptCapture = promptCapture
        self.sampling = sampling
    }
}

private final class PipelineCancellation: Sendable {
    private let stopped = Mutex(false)
    let wake = AcquisitionWake()
    func cancel() {
        stopped.withLock { $0 = true }
        wake.signal()
    }
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
    let effectiveInterval: Double
    let achievedPeriod: Double?
    let carried: [HeldInspectionObservation]
    let inspectionCoverage: InspectionCoverage
    let sampling: SamplingCoverage
}

private struct AcquisitionState: Sendable {
    var ledger = CounterLedger()
    var resolution = ResolutionState()
    var previousStart: Double?
    var promptCapture = PromptEvidenceCapture()
    var sequence: UInt64 = 0
    var inspection: InspectionScheduler?
    var completedSampling = SamplingCoverage()
    var activeOverrides: Set<SamplingOverride> = []
}

private struct ResolutionState: Sendable {
    var monitor = Monitor()
    var window: AccountingWindow?
    var latest: ResolvedScan?
    var displayStartedAt: Double?
    var published = false
    var sampling = SamplingSession(
        LiveInterval.Value(settings: SamplingSettings(), panelVisible: true), at: 0)
}

struct ReportEndpoint: Sendable {
    let timestamp: Date
    let interval: Double
    let sampledCount: Int
    let unreadableCount: Int
}

struct ResolvedScan: Sendable {
    var acquired: ReportEndpoint
    var accounting: CPUAccounting
    let findings: [HeavyProcess]
    var window: AccountingWindow?
    var recent: RecentActivitySnapshot? = nil
    var reportDue = true

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
        old.reportDue = old.reportDue || new.reportDue
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
    let clock: any AcquisitionClock
    let excluded: Set<Int32>
    var recentActivity: (any RecentActivityCollecting)? = nil
    var profile: PipelineProfile? = nil
    var inspection: LiveInspection? = nil

    func run(
        thresholds currentThresholds: (@Sendable () async -> Thresholds)?, interval live: LiveInterval?,
        _ receive: @Sendable (MonitoringSnapshot) async throws -> Void
    ) async throws {
        try Task.checkCancellation()
        let cancellation = PipelineCancellation()
        let enrichment = PipelineEnrichment(profile: profile)
        let acquisition = SerialBlockingWorker(
            name: "AgentMonitor acquisition",
            initial: AcquisitionState(
                resolution: ResolutionState(monitor: Monitor(profile: profile)),
                inspection: configuration.inspectionObservations && inspection != nil
                    ? InspectionScheduler() : nil),
            profile: profile,
            role: .acquisition)
        let publication = SerialBlockingWorker<ResolvedScan?>(
            name: "AgentMonitor publication", initial: nil, profile: profile, role: .publication)
        let limits = configuration.pipelineLimits
        let coalesce: (@Sendable (inout ResolvedScan, ResolvedScan) throws -> MonitoringPayloadSize)?
        if configuration.reportIntervalSeconds == nil {
            coalesce = nil
        } else {
            coalesce = { old, new in
                try profile.measure(.pendingMerge) { try ResolvedScan.coalesced(&old, new, limits: limits) }
            }
        }
        let reports = MonitoringChannel<ResolvedScan>(
            stage: .presentation, limits: limits, coalesce: coalesce)
        let mergeUnits: (@Sendable (inout ResolvedScan, ResolvedScan) throws -> MonitoringPayloadSize)?
        if let coalesce {
            mergeUnits = { old, new in
                let size = try coalesce(&old, new)
                old.window?.coalescePublication()
                return size
            }
        } else {
            mergeUnits = nil
        }
        let handoff = AcquisitionHandoff<ResolvedScan>(limits: limits, profile: profile)
        let units = MonitoringChannel<ResolvedScan>(
            stage: .publication, limits: limits, coalesce: mergeUnits)

        do {
            try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        await collect(
                            on: acquisition, into: handoff, interval: live,
                            enrichment: enrichment, cancellation: cancellation)
                    }
                    group.addTask {
                        do {
                            while let unit = try await handoff.next() {
                                try await units.send(
                                    unit,
                                    size: unit.window?.payloadSize ?? MonitoringPayloadSize(unit.findings),
                                    sequence: unit.window.map { $0.baseline.id.sequence + 1 }
                                        ?? unit.accounting.acquisition?.scanSequence ?? 0)
                            }
                            await units.finish()
                        } catch {
                            cancellation.cancel()
                            await units.finish(throwing: error)
                        }
                    }
                    group.addTask {
                        await publish(from: units, on: publication, into: reports, cancellation: cancellation)
                    }
                    group.addTask {
                        try await enrichment.refreshMetadata(
                            reader: reader, clock: clock, includeCommand: configuration.includeCommands,
                            checking: cancellation.check)
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
                            let snapshot = try profile.measure(.reportProjection) {
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
                                return MonitoringSnapshot(
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
                                    })
                            }
                            try await receive(snapshot)
                        }
                        try await group.waitForAll()
                    } catch {
                        enrichment.finish()
                        cancellation.cancel()
                        group.cancelAll()
                        handoff.cancel()
                        await units.cancel()
                        await reports.cancel()
                        throw error
                    }
                }
            } onCancel: {
                cancellation.cancel()
                handoff.cancel()
            }
        } catch {
            await acquisition.close()
            await publication.close()
            throw error
        }
        await acquisition.close()
        await publication.close()
    }

    private func collect(
        on worker: SerialBlockingWorker<AcquisitionState>, into units: AcquisitionHandoff<ResolvedScan>,
        interval live: LiveInterval?, enrichment: PipelineEnrichment, cancellation: PipelineCancellation
    ) async {
        defer { enrichment.finish() }
        do {
            try await worker.perform(profileJob: false) { state in
                inspection?.finish(InspectionCoverage())
                if state.inspection != nil { inspection?.setWake(cancellation.wake) }
                defer { inspection?.setWake(nil) }
                let observation = live?.observe { cancellation.wake.signal() }
                defer { if let observation { live?.removeObserver(observation) } }
                do {
                    var count = 0
                    state.resolution.sampling = SamplingSession(samplingValue(live), at: clock.monotonicNow())
                    try state.resolution.sampling.synchronize(
                        samplingValue(live), at: clock.monotonicNow(), inspection: inspectionActive)
                    var interval = state.resolution.sampling.decision.requestedSeconds
                    var effectiveInterval = interval
                    while true {
                        guard interval.isFinite, (0.1...60).contains(interval) else {
                            throw MonitoringError.invalidConfiguration
                        }
                        try state.resolution.sampling.synchronize(
                            samplingValue(live), at: clock.monotonicNow(), inspection: inspectionActive)
                        let planned = state.resolution.sampling.decision
                        let scan = try autoreleasepool {
                            try acquire(
                                &state, interval: interval, effectiveInterval: effectiveInterval, live: live,
                                enrichment: enrichment,
                                cancellation: cancellation)
                        }
                        if let report = scan.report {
                            try units.send(
                                report,
                                size: report.window?.payloadSize
                                    ?? MonitoringPayloadSize(report.findings),
                                sequence: report.window.map { $0.baseline.id.sequence + 1 }
                                    ?? scan.sequence)
                            if report.reportDue { count += 1 }
                            if configuration.samples > 0, count >= configuration.samples { break }
                        }
                        try inspectBetweenScans(
                            &state, since: scan.startedAt,
                            interval: state.resolution.sampling.decision.requestedSeconds,
                            cancellation: cancellation)
                        let period = try waitSynchronously(
                            clock, live: live, since: scan.startedAt, planned: planned, state: &state,
                            cancellation: cancellation)
                        interval = period.requested
                        effectiveInterval = period.effective
                    }
                } catch {
                    discardInspection(&state)
                    units.finish(throwing: error, offering: drainPending(&state).flatMap(final))
                    throw error
                }
                discardInspection(&state)
                if let pending = drainPending(&state), let window = pending.window {
                    try units.send(
                        pending, size: window.payloadSize, sequence: window.baseline.id.sequence + 1)
                }
            }
            units.finish()
        } catch {
            units.finish(throwing: error, offering: (try? await drainPending(on: worker)).flatMap(final))
        }
    }

    private func final(_ pending: ResolvedScan) -> (
        value: ResolvedScan, size: MonitoringPayloadSize, sequence: UInt64
    )? {
        pending.window.map { (pending, $0.payloadSize, $0.baseline.id.sequence + 1) }
    }

    private func acquire(
        _ state: inout AcquisitionState, interval: Double, effectiveInterval: Double, live: LiveInterval?,
        enrichment: PipelineEnrichment,
        cancellation: PipelineCancellation
    ) throws -> (startedAt: Double, sequence: UInt64, report: ResolvedScan?) {
        let job = profile.map { _ in PipelineProfile.Stamp() }
        defer { if let job { profile?.endJob(.acquisition, since: job) } }
        try cancellation.check()
        let start = clock.monotonicNow()
        let raw = try profile.measure(.nativeSampling) {
            try reader.snapshot(excluding: excluded)
        }
        try cancellation.check()
        let evidence = profile.measure(.promptCapture) {
            state.promptCapture.capture(
                raw.samples, sequence: state.sequence, using: reader, clock: clock,
                limits: configuration.promptCaptureLimits)
        }
        state.sequence += 1
        let snapshot = ProcessSnapshot(
            samples: raw.samples, enumeratedCount: raw.enumeratedCount,
            unreadableCount: raw.unreadableCount,
            listedAt: raw.listedAt, scanSeconds: raw.scanSeconds, hostCounters: raw.hostCounters,
            logicalCPUCount: raw.logicalCPUCount, nativeOutcomes: raw.nativeOutcomes,
            nativeTiming: raw.nativeTiming, promptEvidence: evidence, listedPIDs: raw.listedPIDs)
        try cancellation.check()
        let carried: [HeldInspectionObservation]
        let inspectionCoverage: InspectionCoverage
        if let inspection, state.inspection != nil {
            carried = state.inspection!.admit(at: snapshot, inspection: inspection)
            inspectionCoverage = state.inspection!.takeCoverage(inspection: inspection)
            state.inspection!.prepare(census: snapshot, inspection: inspection)
        } else {
            carried = []
            inspectionCoverage = InspectionCoverage()
        }
        let counters = profile.measure(.counterAccounting) {
            state.ledger.ingest(
                snapshot.samples, listedAt: snapshot.listedAt, scanSeconds: snapshot.scanSeconds,
                source: snapshot, carried: carried.map(\.sample))
        }
        let period = state.previousStart.map { max(0, start - $0) }
        state.previousStart = start
        let scan = AcquiredScan(
            snapshot: snapshot, counters: counters, timestamp: clock.now(), startedAt: start,
            finishedAt: clock.monotonicNow(), interval: interval, effectiveInterval: effectiveInterval,
            achievedPeriod: period,
            carried: carried, inspectionCoverage: inspectionCoverage, sampling: state.completedSampling)
        let report = try resolve(
            scan, state: &state.resolution, live: live,
            enrichment: enrichment, cancellation: cancellation)
        return (startedAt: start, sequence: counters.id.sequence, report: report)
    }

    private func discardInspection(_ state: inout AcquisitionState) {
        guard state.inspection != nil, let inspection else { return }
        let coverage = state.inspection!.finish(inspection)
        state.resolution.window?.appendInspectionCoverage(coverage)
    }

    private func inspectBetweenScans(
        _ state: inout AcquisitionState, since start: Double, interval: Double,
        cancellation: PipelineCancellation
    ) throws {
        guard state.inspection != nil, let inspection, let reader = reader as? any InspectionReading,
            inspection.value.active
        else { return }
        let slot = start + InspectionLimits.offset
        let ready = clock.monotonicNow() <= slot
        while ready, clock.monotonicNow() < slot {
            try cancellation.check()
            if !inspection.value.active { return }
            try clock.wait(until: slot, wake: cancellation.wake)
        }
        try cancellation.check()
        if ready {
            try state.inspection!.observe(
                reader: reader, monitor: state.resolution.monitor,
                since: start, nextDeadline: start + interval, now: clock.monotonicNow,
                cancelled: { (try? cancellation.check()) == nil }, inspection: inspection, excluding: excluded
            )
        } else {
            state.inspection!.buffer.coverage.mode = .enabled
            state.inspection!.buffer.coverage.opportunitiesSkipped += 1
        }
    }

    private func waitSynchronously(
        _ blocking: any AcquisitionClock, live: LiveInterval?, since start: Double,
        planned: SamplingDecision,
        state: inout AcquisitionState, cancellation: PipelineCancellation
    ) throws -> (requested: Double, effective: Double) {
        var effectiveInterval = planned.requestedSeconds
        var current = planned
        var deadline = start + current.requestedSeconds
        var segmentStart = start
        var previousOverrides = state.activeOverrides
        var coverage = SamplingCoverage()
        var policyChanges = 0
        func record(until now: Double) {
            coverage.append(
                current, duration: max(0, now - segmentStart),
                activations: current.overrides.subtracting(previousOverrides), policyChanges: policyChanges)
            previousOverrides = current.overrides
            policyChanges = 0
            segmentStart = now
        }
        while true {
            if let inspection { state.inspection?.synchronize(inspection) }
            try cancellation.check()
            let now = clock.monotonicNow()
            // A due deadline is evidence already accrued; later settings cannot erase its overrun.
            if now >= deadline {
                record(until: now)
                state.completedSampling = coverage
                state.activeOverrides = current.overrides
                return (current.requestedSeconds, effectiveInterval)
            }
            try state.resolution.sampling.synchronize(
                samplingValue(live), at: now, inspection: inspectionActive)
            let next = state.resolution.sampling.decision
            let changes = state.resolution.sampling.takePolicyChanges()
            if next != current || changes > 0 {
                record(until: now)
                current = next
                policyChanges = changes
                deadline = max(now, start + current.requestedSeconds)
                effectiveInterval = max(current.requestedSeconds, now - start)
            }
            if clock.monotonicNow() >= deadline { continue }
            try blocking.wait(until: deadline, wake: cancellation.wake)
        }
    }

    private var inspectionActive: Bool {
        configuration.inspectionObservations && inspection?.value.active == true
    }

    private func samplingValue(_ live: LiveInterval?) -> LiveInterval.Value {
        live?.value ?? LiveInterval.Value(settings: configuration.sampling, panelVisible: true)
    }

    private func resolve(
        _ scan: AcquiredScan, state: inout ResolutionState, live: LiveInterval?,
        enrichment: PipelineEnrichment, cancellation: PipelineCancellation
    ) throws -> ResolvedScan? {
        try cancellation.check()
        let (accounting, findings) = try profile.measure(.attribution) {
            let accounting = state.monitor.ingest(scan.snapshot, accounting: scan.counters)
            try state.monitor.validateAttributionStorage(
                limits: configuration.pipelineLimits, sequence: scan.counters.id.sequence)
            for evidence in scan.snapshot.promptEvidence where evidence.status.hasMetadata {
                if let metadata = evidence.metadata {
                    state.monitor.enrich(
                        metadata, for: evidence.process, observedAt: evidence.observedAt)
                }
            }
            let samples = Dictionary(
                scan.snapshot.samples.map { ($0.identity, $0) }, uniquingKeysWith: { _, last in last })
            let metadata = enrichment.takeResults()
            for result in metadata {
                guard let current = samples[result.sample.identity],
                    current.executable == result.sample.executable,
                    current.name == result.sample.name
                else { continue }
                state.monitor.enrich(
                    result.metadata, for: result.sample.identity, observedAt: result.observedAt,
                    launchObservedAt: result.launchObservedAt, requestedAt: result.sample.sampledAt)
            }
            let findings = try state.monitor.accountingFindings(
                sorted: configuration.reportIntervalSeconds == nil,
                limits: configuration.pipelineLimits, sequence: scan.counters.id.sequence)
            enrichment.requestMetadata(
                MetadataRefreshRequest(
                    samples: scan.snapshot.samples,
                    prompt: Dictionary(
                        scan.snapshot.promptEvidence.filter { $0.status.hasMetadata }
                            .map { ($0.process, $0) }, uniquingKeysWith: { _, last in last }),
                    requestedAt: scan.finishedAt))
            return (accounting, findings)
        }
        try state.sampling.synchronize(
            samplingValue(live), at: clock.monotonicNow(), inspection: inspectionActive)
        state.sampling.observe(
            scan.counters, snapshot: scan.snapshot, rows: findings, monitor: &state.monitor,
            carried: scan.carried, excluding: excluded, at: clock.monotonicNow(), inspection: inspectionActive
        )
        guard scan.counters.id.sequence > 0 else {
            if configuration.reportIntervalSeconds != nil {
                state.window = AccountingWindow(baseline: scan.counters)
            }
            return nil
        }
        var sampling = scan.sampling
        sampling.setLatest(state.sampling.decision, policyChanges: state.sampling.takePolicyChanges())
        let timing = AcquisitionTiming(
            runID: scan.counters.id.runID, scanSequence: scan.counters.id.sequence,
            qualityOfService: .userInitiated, requestedPeriodSeconds: scan.interval,
            achievedPeriodSeconds: scan.achievedPeriod,
            scanWorkSeconds: max(0, scan.finishedAt - scan.startedAt),
            resolutionDelaySeconds: max(0, clock.monotonicNow() - scan.finishedAt),
            promptCapture: PromptCaptureSummary(scan.snapshot.promptEvidence), sampling: sampling,
            effectivePeriodSeconds: scan.effectiveInterval)
        if let refresh = configuration.reportIntervalSeconds {
            let accountingStart = profile.map { _ in PipelineProfile.Stamp() }
            var accountingEnded = false
            defer {
                if !accountingEnded, let accountingStart {
                    profile?.end(.windowAccounting, since: accountingStart)
                }
            }
            let times = state.monitor.attributionObservationTimes(for: findings)
            // Keep the last admitted partial intact until the next scan fits; a failed
            // admission must drain it with its matching endpoint (CPU-01 accounting contract).
            guard var accumulated = state.window else { return nil }
            try accumulated.append(
                scan.counters, rows: findings, attributionTimes: times,
                runtimes: state.monitor.agentRuntimeIdentities, timing: timing,
                carried: scan.carried, inspectionCoverage: scan.inspectionCoverage)
            let size = accumulated.compact(to: configuration.pipelineLimits)
            guard configuration.pipelineLimits.admits(size) else {
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
            if let accountingStart { profile?.end(.windowAccounting, since: accountingStart) }
            accountingEnded = true
            state.window = AccountingWindow(baseline: scan.counters)
            let displayStart = state.displayStartedAt ?? opening
            let period = state.published ? refresh : min(1, refresh)
            let due = (scan.counters.listedAt ?? scan.startedAt) - displayStart + 1e-9 >= period
            state.displayStartedAt = due ? nil : displayStart
            if due { state.published = true }
            var unit = ResolvedScan(
                acquired: scan, accounting: accounting.withAcquisition(timing), findings: [],
                window: accumulated)
            unit.reportDue = due
            return unit
        }
        return ResolvedScan(
            acquired: scan, accounting: accounting.withAcquisition(timing),
            findings: findings.filter { configuration.scope.includes($0.attribution) }, window: nil)
    }

    private func drainPending(on worker: SerialBlockingWorker<AcquisitionState>) async throws -> ResolvedScan?
    {
        try await worker.perform { collection in drainPending(&collection) }
    }

    private func drainPending(_ collection: inout AcquisitionState) -> ResolvedScan? {
        defer { collection.resolution.window = nil }
        guard let latest = collection.resolution.latest,
            let partial = collection.resolution.window,
            partial.final.id.sequence > partial.baseline.id.sequence
        else { return nil }
        return ResolvedScan(
            acquired: latest.acquired, accounting: latest.accounting, findings: [], window: partial)
    }

    private func publish(
        from units: MonitoringChannel<ResolvedScan>, on worker: SerialBlockingWorker<ResolvedScan?>,
        into reports: MonitoringChannel<ResolvedScan>, cancellation: PipelineCancellation
    ) async {
        func send(_ report: ResolvedScan?) async throws {
            guard let report else { return }
            try await reports.send(
                report, size: report.window?.payloadSize ?? MonitoringPayloadSize(report.findings),
                sequence: report.window.map { $0.baseline.id.sequence + 1 }
                    ?? report.accounting.acquisition?.scanSequence ?? 0)
        }
        func drain() async throws -> ResolvedScan? {
            try await worker.perform { pending in
                guard var report = pending else { return nil }
                pending = nil
                report.recent = profile.measure(.historyProjection) { recentActivity?.snapshot() }
                return report
            }
        }
        do {
            while let unit = try await units.next() {
                let report = try await worker.perform { pending -> ResolvedScan? in
                    guard let window = unit.window else { return unit }
                    var next = pending ?? unit
                    if pending != nil {
                        let size = try ResolvedScan.coalesced(
                            &next, unit, limits: configuration.pipelineLimits)
                        guard configuration.pipelineLimits.admits(size) else {
                            throw MonitoringError.overloaded(
                                stage: .publication, rejectedScan: window.baseline.id.sequence + 1)
                        }
                    }
                    profile.measure(.historyClosure) {
                        recentActivity?.append(
                            window.seal(scope: configuration.scope), current: window.current,
                            present: window.present)
                    }
                    pending = next
                    guard unit.reportDue else { return nil }
                    pending = nil
                    next.recent = profile.measure(.historyProjection) { recentActivity?.snapshot() }
                    return next
                }
                try await send(report)
            }
            try await send(drain())
            await reports.finish()
        } catch {
            cancellation.cancel()
            await units.cancel()
            do { try await send(drain()) } catch {
                await reports.finish(throwing: error)
                return
            }
            await reports.finish(throwing: error)
        }
    }

}

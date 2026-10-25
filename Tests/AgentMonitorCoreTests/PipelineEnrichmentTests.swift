import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

final class StalledEnrichment: ProcessReading, SamplingClock, SessionRegistryReading, Sendable {
    enum Stage: CaseIterable, Sendable { case metadata, provider }
    let stage: Stage
    let time = Mutex(0.0)
    let entered = AsyncStream<Void>.makeStream()
    let release = DispatchSemaphore(value: 0)
    let releasedByReport = Mutex(false)
    let metadataCalls = Mutex(0)
    init(stage: Stage) { self.stage = stage }
    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let at = monotonicNow()
        return diagnosisScan(
            [
                sample(
                    42,
                    executable: "/Users/test/.local/share/claude/versions/2.1.301", at: at, cpu: at / 10)
            ], at: at, scan: 0)
    }
    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        ProcessMetadata(status: .markerRead, invocation: "claude")
    }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        metadataCalls.withLock { $0 += 1 }
        if stage == .metadata { block() }
        return ProcessMetadata(status: .markerRead, invocation: "claude")
    }
    func metadata(for sample: ProcessSample, includeCommand: Bool, capturedLaunch: ProcessMetadata?)
        -> ProcessMetadata
    {
        metadata(for: sample, includeCommand: includeCommand)
    }
    func isCurrent(_ sample: ProcessSample) -> Bool { true }
    func output(of query: SessionRegistryQuery) throws -> Data {
        if stage == .provider { block() }
        return Data("[]".utf8)
    }
    private func block() {
        entered.continuation.yield(())
        let accepted = release.wait(timeout: .now() + 3) == .success
        releasedByReport.withLock { $0 = accepted }
    }
    func wait(seconds: Double) async throws {
        if monotonicNow() == 0 { for await _ in entered.stream { break } }
        try Task.checkCancellation()
        time.withLock { $0 += seconds }
    }
    func monotonicNow() -> Double { time.withLock { $0 } }
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }
}

@Suite struct PipelineEnrichmentTests {
    @Test(arguments: StalledEnrichment.Stage.allCases)
    func slowEnrichmentCannotHoldTheFirstAccountingReport(stage: StalledEnrichment.Stage) async throws {
        let fixture = StalledEnrichment(stage: stage)
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                intervalSeconds: 0.1, samples: 1, scope: .allProcesses, reportIntervalSeconds: 5),
            reader: fixture, clock: fixture, registry: fixture)
        let reports = Mutex<[MonitoringSnapshot]>([])
        try await session.run { snapshot in
            reports.withLock { $0.append(snapshot) }
            fixture.release.signal()
        }
        #expect(fixture.releasedByReport.withLock { $0 })
        let report = try #require(reports.withLock { $0.first })
        #expect(abs(try #require(report.window).durationSeconds - 1) < 1e-9)
        #expect(abs(try #require(report.window).contributions.reduce(0) { $0 + $1.cpuSeconds } - 0.1) < 1e-9)
    }

    @Test func delayedMetadataCannotOverwriteNewerMarkersAndEmptyParserReadsKeepThem() throws {
        var monitor = Monitor()
        let process = sample(42, at: 0, cpu: 0)
        monitor.ingest([process])
        monitor.enrich(
            ProcessMetadata(markers: [SessionMarker(threadID: sessionB, provider: .codex)]),
            for: process.identity, observedAt: 2)
        let stale = ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)])
        monitor.enrich(stale, for: process.identity, observedAt: 3, launchObservedAt: 1)
        #expect(monitor.finding(for: process.identity)?.attribution.threadID == sessionB)
        #expect(monitor.attributionObservationTimes()[process.identity] == 2)
        let empty = ProcessArguments.parse(argumentBuffer(environment: []))
        #expect(empty.status == .notObserved)
        monitor.enrich(empty, for: process.identity, observedAt: 4)
        monitor.enrich(stale, for: process.identity, observedAt: 5, launchObservedAt: 1)
        #expect(monitor.finding(for: process.identity)?.attribution.threadID == sessionB)
    }

    @Test func persistentReadFailuresCountPIDValuesInsteadOfScanMultiples() throws {
        var ledger = CounterLedger()
        var window = AccountingWindow(baseline: ledger.ingest([], listedAt: 0))
        for tick in 1...600 {
            let outcomes = (1...6).map {
                NativeCounterOutcome(
                    pid: Int32($0), identity: nil, operation: .bsdInfo,
                    status: $0 == 1 ? .permissionDenied : .lookupUnavailable, failure: nil,
                    observedAtTicks: UInt64(tick))
            }
            let source = ProcessSnapshot(
                samples: [], enumeratedCount: 6, unreadableCount: 6,
                listedAt: Double(tick) / 10, scanSeconds: 0, hostCounters: nil, logicalCPUCount: 1,
                nativeOutcomes: outcomes)
            let scan = ledger.ingest([], listedAt: source.listedAt, source: source)
            try window.append(scan, rows: [])
        }
        let coverage = window.seal(scope: .agentsOnly).readCoverage
        #expect(coverage.failedPIDs.count == 6)
        #expect(coverage.deniedPIDs.count == 1)
        #expect(coverage.vanishedPIDs.count == 5)
        #expect(coverage.failedPIDObservations == 3_600)
        #expect(coverage.meanFailedPIDsPerScan == 6)
        #expect(window.payloadSize.observations == 6)
    }
}

private final class MetadataBatchFixture: ProcessReading, SamplingClock, Sendable {
    let time = Mutex(0.0)
    let calls = Mutex<[Int32]>([])
    let onFirstRead: @Sendable () -> Void
    let readSeconds: Double
    init(readSeconds: Double = 0, onFirstRead: @escaping @Sendable () -> Void = {}) {
        self.onFirstRead = onFirstRead
        self.readSeconds = readSeconds
    }
    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot { diagnosisScan([], at: monotonicNow()) }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        let first = calls.withLock { value in
            value.append(sample.identity.pid)
            return value.count == 1
        }
        if first { onFirstRead() }
        time.withLock { $0 += readSeconds }
        return ProcessMetadata(status: .markerRead)
    }
    func wait(seconds: Double) async throws { time.withLock { $0 += seconds } }
    func monotonicNow() -> Double { time.withLock { $0 } }
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }
}

@Test(.timeLimit(.minutes(1))) func finishingEnrichmentSkipsTheRestOfAnAcceptedBatch() async throws {
    let enrichment = PipelineEnrichment()
    let fixture = MetadataBatchFixture(onFirstRead: { enrichment.finish() })
    let worker = Task {
        try await enrichment.refreshMetadata(
            reader: fixture, clock: fixture, includeCommand: false, checking: {})
    }
    enrichment.requestMetadata(
        MetadataRefreshRequest(
            samples: (1...100).map { sample(Int32($0), at: 0) }, prompt: [:], requestedAt: 0))
    try await worker.value
    #expect(fixture.calls.withLock { $0.count } == 1)
}

@Test(.timeLimit(.minutes(1))) func changedExecutablesPrecedePeriodicMetadataRefresh() async throws {
    let fixture = MetadataBatchFixture()
    let enrichment = PipelineEnrichment()
    let worker = Task {
        try await enrichment.refreshMetadata(
            reader: fixture, clock: fixture, includeCommand: false, checking: {})
    }
    for tick in 0...1 {
        fixture.time.withLock { $0 = Double(tick) }
        enrichment.requestMetadata(
            MetadataRefreshRequest(
                samples: [
                    sample(42, at: Double(tick)),
                    sample(43, executable: tick == 0 ? "/bin/a" : "/bin/b", at: Double(tick)),
                ],
                prompt: [:], requestedAt: Double(tick)))
        var completed = 0
        while completed < 2 {
            completed += enrichment.takeResults().0.count
            await Task.yield()
        }
    }
    enrichment.finish()
    try await worker.value
    #expect(fixture.calls.withLock { Array($0.suffix(2)) } == [43, 42])
}

@Test(.timeLimit(.minutes(1))) func stableMetadataRefreshHasBothACadenceAndProgress() async throws {
    let fixture = MetadataBatchFixture()
    let enrichment = PipelineEnrichment()
    let worker = Task {
        try await enrichment.refreshMetadata(
            reader: fixture, clock: fixture, includeCommand: false, checking: {})
    }
    for second in 0...3 {
        for tenth in 0...9 {
            let time = Double(second) + Double(tenth) / 10
            fixture.time.withLock { $0 = time }
            enrichment.requestMetadata(
                MetadataRefreshRequest(
                    samples: [sample(42, at: time)], prompt: [:], requestedAt: time))
            if tenth == 0 {
                while enrichment.takeResults().0.isEmpty { await Task.yield() }
            }
        }
    }
    enrichment.finish()
    try await worker.value
    #expect(fixture.calls.withLock { $0 } == [42, 42, 42, 42])
}

@Test func metadataCadenceUsesAdmissionTimeWhileEvidenceKeepsActualReadTime() throws {
    let fixture = MetadataBatchFixture(readSeconds: 0.005)
    let enrichment = PipelineEnrichment()
    var cache = PipelineEnrichment.Cache()
    for second in 0...2 {
        let at = Double(second)
        fixture.time.withLock { $0 = at }
        try enrichment.refreshMetadataBatch(
            MetadataRefreshRequest(
                samples: (1...100).map { sample(Int32($0), at: at) }, prompt: [:], requestedAt: at),
            cache: &cache, reader: fixture, clock: fixture, includeCommand: false, checking: {})
        let results = enrichment.takeResults().0
        #expect(results.count == 100)
        #expect(fixture.calls.withLock { $0.count } == (second + 1) * 100)
        if let first = results.map(\.observedAt).min(), let last = results.map(\.observedAt).max() {
            #expect(abs(first - at - 0.005) < 1e-9)
            #expect(abs(last - at - 0.5) < 1e-9)
        }
    }
}

private enum ExecBoundary: CaseIterable { case path, name, peak }

@Test(arguments: ExecBoundary.allCases)
private func parserMarkersSurviveEmptyReadsButNotDetectedExec(boundary: ExecBoundary) throws {
    var monitor = Monitor()
    var process = sample(42, at: 0)
    process.kernelPeakFootprintBytes = 100
    monitor.ingest([process])
    let marked = ProcessArguments.parse(argumentBuffer(environment: ["CODEX_THREAD_ID=\(sessionA)"]))
    let empty = ProcessArguments.parse(argumentBuffer(environment: []))
    monitor.enrich(marked, for: process.identity, observedAt: 1)
    monitor.enrich(empty, for: process.identity, observedAt: 2)
    #expect(monitor.finding(for: process.identity)?.attribution.threadID == sessionA)
    process.sampledAt = 3
    switch boundary {
    case .path: process.executable = "/bin/other"
    case .name: process.name = "other"
    case .peak: process.kernelPeakFootprintBytes = 20
    }
    monitor.ingest([process])
    #expect(monitor.finding(for: process.identity)?.attribution.threadID == nil)
    monitor.enrich(marked, for: process.identity, observedAt: 1)
    #expect(monitor.finding(for: process.identity)?.attribution.threadID == nil)
    monitor.enrich(empty, for: process.identity, observedAt: 4)
    #expect(monitor.finding(for: process.identity)?.attribution.threadID == nil)
}

private struct EmptyMarkerReader: ProcessReading, SamplingClock {
    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot { diagnosisScan([], at: 1) }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata { ProcessMetadata() }
    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        ProcessArguments.parse(argumentBuffer(environment: []))
    }
    func wait(seconds: Double) async throws {}
    func monotonicNow() -> Double { 1 }
    func now() -> Date { Date(timeIntervalSince1970: 1) }
}

@Test func successfulEmptyPromptReadIsCapturedRatherThanUnavailable() throws {
    var capture = PromptEvidenceCapture()
    let reader = EmptyMarkerReader()
    let evidence = capture.capture(
        [sample(42, at: 1)], sequence: 1, using: reader, clock: reader, limits: .init())
    #expect(evidence.first?.status.rawValue == "capturedWithoutMarker")
    #expect(PromptCaptureSummary(evidence).unavailable == 0)
    #expect(evidence.first?.metadata?.status == .notObserved)
}

@Test func anExecWithUnavailablePeakDoesNotCarryThePreviousExecutionPeak() {
    var process = sample(42)
    process.kernelPeakFootprintBytes = 100
    var execution = ObservedExecution(process)
    process.executable = "/new"
    process.kernelPeakFootprintBytes = nil
    let changedPath = execution.update(process)
    #expect(changedPath)
    process.kernelPeakFootprintBytes = 20
    let firstPeak = execution.update(process)
    #expect(!firstPeak)
    process.kernelPeakFootprintBytes = nil
    let unavailable = execution.update(process)
    #expect(!unavailable)
    process.kernelPeakFootprintBytes = 10
    let reset = execution.update(process)
    #expect(reset)
}

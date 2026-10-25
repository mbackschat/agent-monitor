import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private enum AncestorFixtureError: Error { case exhausted }

private enum ResolutionPopulation: CaseIterable {
    case chain, fanout

    var samples: [ProcessSample] {
        (0..<1_000).map { index in
            let pid = Int32(20_000 + index)
            let parent: Int32
            switch self {
            case .chain: parent = index == 0 ? 1 : pid - 1
            case .fanout: parent = index == 0 ? 1 : (index < 10 ? pid - 1 : 20_009)
            }
            return sample(pid, parent: parent)
        }
    }
}

private final class ResolutionGrowthFixture: ProcessReading, AcquisitionClock, SessionRegistryReading,
    Sendable
{
    private let tick = Mutex(0)
    private let time = Mutex(0.0)

    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let scan = try tick.withLock { value in
            guard value <= 2 else { throw AncestorFixtureError.exhausted }
            defer { value += 1 }
            return value
        }
        return diagnosisScan(
            (0..<100).map { index in
                let pid = Int32(30_000 + index)
                return sample(
                    pid, parent: index == 0 ? 1 : pid - 1,
                    executable: scan < 2 ? "/usr/bin/codex" : "/usr/bin/worker",
                    at: monotonicNow(), cpu: Double(scan) / 100)
            }, at: monotonicNow(), scan: 0)
    }

    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        ProcessMetadata(status: .markerRead, writerThreadIDs: [sessionA])
    }
    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        metadata(for: sample, includeCommand: false)
    }
    func output(of query: SessionRegistryQuery) throws -> Data { Data("[]".utf8) }
    func wait(until deadline: Double, wake: AcquisitionWake) throws { time.withLock { $0 = deadline } }
    func monotonicNow() -> Double { time.withLock { $0 } }
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }
}

private final class AncestorHandoffFixture: ProcessReading, AcquisitionClock, SessionRegistryReading, Sendable
{
    private struct State {
        var time = 0.0
        var nextScan = 0
    }
    private let state = Mutex(State())
    let reportReceived = ClockGate()
    let finalScan = 768

    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        try state.withLock { value in
            guard value.nextScan <= finalScan else { throw AncestorFixtureError.exhausted }
            let scan = value.nextScan
            value.nextScan += 1
            let parent = Int32(10_000 + scan)
            let samples = [
                sample(parent, parent: parent - 1, executable: "/usr/bin/codex", at: value.time, cpu: 0.01),
                sample(parent + 1, parent: parent, executable: "/usr/bin/codex", at: value.time, cpu: 0),
            ]
            return diagnosisScan(samples, at: value.time, scan: 0)
        }
    }

    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        ProcessMetadata(status: .markerRead, invocation: "codex", writerThreadIDs: [sessionA])
    }

    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        metadata(for: sample, includeCommand: false)
    }

    func output(of query: SessionRegistryQuery) throws -> Data { Data("[]".utf8) }

    func wait(until deadline: Double, wake: AcquisitionWake) throws {
        let completed = state.withLock { $0.nextScan - 1 }
        if completed > 0, completed.isMultiple(of: 10) {
            guard reportReceived.wait(wake: wake) else { return }
        }
        state.withLock { $0.time = max($0.time, deadline) }
    }

    func monotonicNow() -> Double { state.withLock { $0.time } }
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }
}

@Suite struct AttributionStorageTests {
    @Test(arguments: ResolutionPopulation.allCases, [false, true])
    private func cachePressureKeepsCompleteFindingsWithinItsReservation(
        population: ResolutionPopulation, constrainText: Bool
    ) throws {
        var monitor = Monitor()
        monitor.ingest(population.samples)
        monitor.enrich(
            ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]),
            for: population.samples[0].identity)
        let baseline = monitor.attributionPayloadSize
        let limits = MonitoringPipelineLimits(
            pendingObservations: constrainText ? 1_000_000 : 5_000,
            pendingTextBytes: constrainText ? baseline.textBytes + 100 : 16 * 1_024 * 1_024)
        let oracle = monitor.findings()
        for _ in 0..<3 {
            let rows = try monitor.accountingFindings(sorted: true, limits: limits, sequence: 1)
            #expect(rows == oracle)
            #expect(rows.allSatisfy { $0.attribution.threadID == sessionA })
            #expect(monitor.attributionPayloadSize.observations <= limits.pendingObservations)
            #expect(monitor.attributionPayloadSize.textBytes <= limits.pendingTextBytes)
            #expect(monitor.attributionPayloadSize == monitor.recountedAttributionPayloadSize)
        }
    }

    @Test(arguments: [false, true])
    func evidenceGrowthReclaimsOptionalCacheBeforeRejectingTheGraph(constrainText: Bool) throws {
        var samples = (0..<10).map { sample(Int32(100 + $0)) }
        var monitor = Monitor()
        monitor.ingest(samples)
        for value in samples {
            monitor.enrich(
                ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]),
                for: value.identity)
        }
        _ = monitor.accountingFindings()
        let originalSize = monitor.attributionPayloadSize
        let limits = MonitoringPipelineLimits(
            pendingObservations: constrainText ? 65_536 : originalSize.observations,
            pendingTextBytes: constrainText ? originalSize.textBytes : 16 * 1_024 * 1_024)
        var copy = monitor
        samples.append(sample(200))
        monitor.ingest(samples)
        try monitor.validateAttributionStorage(limits: limits, sequence: 2)
        #expect(monitor.attributionPayloadSize.observations <= limits.pendingObservations)
        #expect(monitor.attributionPayloadSize == monitor.recountedAttributionPayloadSize)
        #expect(monitor.findings().count == 11)
        #expect(copy.accountingFindings().count == 10)
        #expect(copy.attributionPayloadSize == originalSize)
    }

    @Test func staleDetachedResolutionReplacementDoesNotDoubleChargeItsExistingEntry() throws {
        let runtime = sample(10, executable: "/usr/bin/codex")
        let otherRuntime = sample(11, executable: "/usr/bin/codex")
        let worker = sample(20)
        var monitor = Monitor()
        monitor.ingest([runtime, worker])
        monitor.enrich(ProcessMetadata(writerThreadIDs: [sessionA]), for: runtime.identity)
        monitor.enrich(
            ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)]),
            for: worker.identity)
        _ = monitor.accountingFindings()
        monitor.ingest([runtime, otherRuntime, worker])
        monitor.enrich(ProcessMetadata(writerThreadIDs: [sessionB]), for: otherRuntime.identity)
        var reference = monitor
        _ = reference.accountingFindings()
        let expected = reference.recountedAttributionPayloadSize
        let limits = MonitoringPipelineLimits(
            pendingObservations: expected.observations, pendingTextBytes: expected.textBytes)
        let rows = try monitor.accountingFindings(limits: limits, sequence: 1)
        #expect(rows.first { $0.process == worker.identity }?.attribution.runtime == runtime.identity)
        #expect(monitor.attributionPayloadSize == expected)
        #expect(monitor.attributionPayloadSize == monitor.recountedAttributionPayloadSize)
    }

    @Test(.timeLimit(.minutes(1)))
    func productionCollectionContinuesWhenResolutionCacheDoesNotFit() async throws {
        let fixture = ResolutionGrowthFixture()
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                intervalSeconds: 0.1, samples: 2, scope: .allProcesses,
                pipelineLimits: MonitoringPipelineLimits(pendingObservations: 5_500)
            ),
            reader: fixture, clock: fixture, registry: fixture)
        let reports = Mutex<[MonitoringSnapshot]>([])
        try await session.run { value in reports.withLock { $0.append(value) } }
        let delivered = reports.withLock { $0 }
        #expect(delivered.count == 2)
        #expect(delivered.allSatisfy { $0.observedFindings.count == 100 })
        let cpu = delivered.flatMap(\.observedFindings).reduce(0) { $0 + ($1.cpuPercent ?? 0) * 0.001 }
        #expect(abs(cpu - 2) < 1e-9)
    }

    @Test func incrementalChargesFollowSpellingExecInvalidationPruningAndValueCopies() throws {
        let composed = "caf\u{e9}"
        let decomposed = "cafe\u{301}"
        var runtime = sample(10, executable: "/\(composed)/codex", terminal: composed, at: 0)
        runtime.name = composed
        runtime.kernelPeakFootprintBytes = 100
        let child = sample(11, parent: 10, at: 0)
        let leaf = sample(12, parent: 11, at: 0)
        var monitor = Monitor()
        monitor.ingest([runtime, child, leaf])
        monitor.enrich(
            ProcessMetadata(
                status: .markerRead, cwd: "/\(composed)", command: ["codex", composed],
                invocation: "codex", terminal: composed, writerThreadIDs: [sessionA],
                listeningSockets: ["/\(composed).sock"]),
            for: runtime.identity)
        monitor.enrich(
            ProcessMetadata(markers: [
                SessionMarker(
                    threadID: sessionB, rootSessionID: sessionA, provider: .codex,
                    inboxSocket: "/\(composed).sock")
            ]), for: child.identity)
        _ = monitor.accountingFindings()
        #expect(monitor.attributionPayloadSize == monitor.recountedAttributionPayloadSize)
        let before = monitor.attributionPayloadSize

        runtime.executable = "/\(decomposed)/codex"
        runtime.name = decomposed
        runtime.terminal = decomposed
        monitor.ingest([runtime, child, leaf])
        monitor.enrich(
            ProcessMetadata(
                status: .markerRead, cwd: "/\(decomposed)", command: ["codex", decomposed],
                invocation: "codex", terminal: decomposed, writerThreadIDs: [sessionA],
                listeningSockets: ["/\(decomposed).sock"]),
            for: runtime.identity)
        monitor.enrich(
            ProcessMetadata(markers: [
                SessionMarker(
                    threadID: sessionB, rootSessionID: sessionA, provider: .codex,
                    inboxSocket: "/\(decomposed).sock")
            ]), for: child.identity)
        _ = monitor.accountingFindings()
        #expect(monitor.attributionPayloadSize == monitor.recountedAttributionPayloadSize)
        #expect(monitor.attributionPayloadSize.textBytes > before.textBytes)
        var exhausted = monitor
        #expect(throws: MonitoringError.overloaded(stage: .attribution, rejectedScan: 7)) {
            try exhausted.validateAttributionStorage(
                limits: MonitoringPipelineLimits(
                    pendingTextBytes: 1),
                sequence: 7)
        }

        let originalSize = monitor.attributionPayloadSize
        var copy = monitor
        runtime.kernelPeakFootprintBytes = 10
        copy.ingest([runtime, child, leaf])
        _ = copy.accountingFindings()
        #expect(copy.attributionPayloadSize == copy.recountedAttributionPayloadSize)
        #expect(copy.attributionPayloadSize.textBytes < originalSize.textBytes)
        #expect(monitor.attributionPayloadSize == originalSize)

        runtime.executable = "/bin/worker"
        copy.ingest([runtime, child, leaf])
        copy.enrich(
            ProcessMetadata(command: ["fresh", "arguments"], invocation: "worker"), for: runtime.identity)
        _ = copy.accountingFindings()
        #expect(copy.attributionPayloadSize == copy.recountedAttributionPayloadSize)
        copy.ingest([leaf])
        _ = copy.accountingFindings()
        #expect(copy.attributionPayloadSize == copy.recountedAttributionPayloadSize)
        #expect(copy.chain(from: leaf.identity) == [leaf.identity, child.identity, runtime.identity])
        copy.ingest([])
        #expect(copy.attributionPayloadSize == MonitoringPayloadSize(observations: 0, textBytes: 0))
        #expect(copy.attributionPayloadSize == copy.recountedAttributionPayloadSize)
        #expect(monitor.attributionPayloadSize == monitor.recountedAttributionPayloadSize)
    }

    @Test func listingRenamesAndRuntimeWithdrawalReleaseTheirCharges() throws {
        let runtime = sample(20, executable: "/usr/bin/claude")
        var monitor = Monitor()
        monitor.ingest([runtime])
        for name in ["caf\u{e9}", "cafe\u{301}", "A longer session name"] {
            let output = try JSONSerialization.data(withJSONObject: [
                [
                    "pid": Int(runtime.identity.pid), "sessionId": sessionA, "status": "idle", "name": name,
                ]
            ])
            let bound = monitor.bindSessions(output, provider: .claude, observedAt: 1)
            #expect(bound)
            _ = monitor.accountingFindings()
            #expect(monitor.attributionPayloadSize == monitor.recountedAttributionPayloadSize)
        }
        monitor.enrich(ProcessMetadata(invocation: "ugrep"), for: runtime.identity)
        _ = monitor.accountingFindings()
        #expect(monitor.attributionPayloadSize == monitor.recountedAttributionPayloadSize)
        monitor.ingest([])
        #expect(monitor.attributionPayloadSize == MonitoringPayloadSize(observations: 0, textBytes: 0))
    }

    @Test func threeThousandProcessesAtDepthTenFitWithoutRepeatedVariableStorageWalks() throws {
        let samples = (0..<3_000).map { index in
            let pid = Int32(10_000 + index)
            return sample(
                pid, parent: index.isMultiple(of: 10) ? 1 : pid - 1,
                executable: index.isMultiple(of: 10) ? "/usr/bin/codex" : "/usr/bin/worker", at: 1)
        }
        var monitor = Monitor()
        monitor.ingest(samples)
        for runtime in samples where runtime.identity.pid.isMultiple(of: 10) {
            monitor.enrich(
                ProcessMetadata(status: .markerRead, invocation: "codex", writerThreadIDs: [sessionA]),
                for: runtime.identity)
        }
        let rows = monitor.accountingFindings()
        #expect(rows.count == 3_000)
        #expect(rows.allSatisfy { $0.attribution.threadID == sessionA })
        #expect(rows.map(\.attribution.ancestry.count).max() == 10)
        #expect(monitor.attributionPayloadSize == monitor.recountedAttributionPayloadSize)
        try monitor.validateAttributionStorage(limits: MonitoringPipelineLimits(), sequence: 0)
        let visits = monitor.attributionStorageRecordVisits
        let size = monitor.attributionPayloadSize
        for tick in 2...5 {
            monitor.ingest(
                samples.map { value in
                    var next = value
                    next.sampledAt = Double(tick)
                    next.cpuSeconds = Double(tick)
                    return next
                })
            _ = monitor.accountingFindings()
            try monitor.validateAttributionStorage(limits: MonitoringPipelineLimits(), sequence: UInt64(tick))
            #expect(monitor.attributionPayloadSize == size)
            #expect(monitor.attributionStorageRecordVisits == visits)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func departedRuntimeAncestorsExhaustTheirOwnBudgetBeforeAcceptedAccountingIsLost() async throws {
        let fixture = AncestorHandoffFixture()
        let limits = MonitoringPipelineLimits(pendingObservations: 512, pendingTextBytes: 65_536)
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(
                intervalSeconds: 0.1, samples: 0, scope: .allProcesses,
                pipelineLimits: limits, reportIntervalSeconds: 1),
            reader: fixture, clock: fixture, registry: fixture)
        let reports = Mutex<[MonitoringSnapshot]>([])
        var failure: MonitoringError?
        do {
            try await session.run { report in
                reports.withLock { $0.append(report) }
                fixture.reportReceived.signal()
            }
        } catch let error as MonitoringError {
            failure = error
        } catch {
            Issue.record(
                "Expected attribution storage exhaustion before fixture completion, received \(error)")
        }
        let error = try #require(failure)
        guard case .overloaded(let stage, let rejectedScan) = error else {
            Issue.record("Expected a storage overload, received \(error)")
            return
        }
        #expect(stage.rawValue == "attribution")
        #expect(rejectedScan > 1)
        #expect(rejectedScan < UInt64(fixture.finalScan))

        let delivered = reports.withLock { $0 }
        let windows = delivered.compactMap(\.window)
        let last = try #require(windows.last)
        #expect(last.finalScan == rejectedScan - 1)
        #expect(windows.first?.baselineScan == 0)
        for pair in zip(windows, windows.dropFirst()) {
            #expect(pair.0.finalScan == pair.1.baselineScan)
        }
        let cpu = windows.reduce(0) { total, window in
            total + window.contributions.reduce(0) { $0 + $1.cpuSeconds }
                + window.collapsedContributions.reduce(0) { $0 + $1.cpuSeconds }
        }
        let intervals = windows.reduce(0) { total, window in
            total + window.contributions.reduce(0) { $0 + $1.intervalCount }
                + window.collapsedContributions.reduce(0) { $0 + $1.intervalCount }
        }
        #expect(abs(cpu - Double(rejectedScan - 1) * 0.01) < 1e-9)
        #expect(intervals == Int(rejectedScan - 1))
        #expect(delivered.allSatisfy { $0.sampledProcessCount == 2 })
        #expect(
            delivered.flatMap(\.observedFindings).allSatisfy { row in
                row.attribution.threadID == sessionA && row.attribution.ancestry.count == 1
            })
    }
}

import AgentMonitorPresentation
import Darwin
import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private let measuresOwnershipAllocations =
    ProcessInfo.processInfo.environment["AGENT_MONITOR_OWNERSHIP_ALLOCATOR"] == "1"

@Suite struct SimultaneousOwnershipTests {
    @Test(
        .enabled(if: !measuresOwnershipAllocations), .timeLimit(.minutes(1)), arguments: [90, 613],
        [MergeAdmission.accept, .reject])
    func pendingMergeCoexistsWithPausedHistoryEnrichmentAndDiagnosis(
        population: Int, admission: MergeAdmission
    ) async throws {
        try await exerciseHolders(population: population, admission: admission)
    }

    @Test(.enabled(if: measuresOwnershipAllocations), .timeLimit(.minutes(1)))
    func isolatedAllocatorReadingsAtProvedCoexistence() async throws {
        allocationReading("before", population: 613)
        try await exerciseHolders(population: 613, measure: true)
        allocationReading("afterRelease", population: 613)
    }

    enum MergeAdmission: Sendable { case accept, reject }

    private func exerciseHolders(
        population: Int, admission: MergeAdmission = .accept, measure: Bool = false
    ) async throws {
        let fixture = OwnershipFixture(population: population)
        let store = RecentActivityStore()
        var ledger = CounterLedger()
        var previous = ledger.ingest(fixture.samples(at: 0), listedAt: 0)
        var state = LiveReportState(grouping: .session)
        var reports: [MonitoringSnapshot] = []
        var pending: [ResolvedScan] = []
        for tick in 1...4 {
            let samples = fixture.samples(at: Double(tick))
            let source = ProcessSnapshot(
                samples: samples, enumeratedCount: population + (tick >= 3 ? 1 : 0),
                unreadableCount: tick >= 3 ? 1 : 0,
                listedAt: Double(tick), scanSeconds: 0, hostCounters: nil, logicalCPUCount: 8,
                nativeOutcomes: tick >= 3
                    ? [
                        NativeCounterOutcome(
                            pid: Int32(10_000 + tick), identity: nil, operation: .bsdInfo,
                            status: .permissionDenied, failure: nil, observedAtTicks: UInt64(tick))
                    ] : [])
            let scan = ledger.ingest(samples, listedAt: Double(tick), source: source)
            var window = AccountingWindow(baseline: previous)
            let rows = samples.map(fixture.row)
            try window.append(scan, rows: rows)
            previous = scan
            if tick >= 3 {
                pending.append(
                    ResolvedScan(
                        acquired: ReportEndpoint(
                            timestamp: Date(timeIntervalSince1970: Double(tick)), interval: 1,
                            sampledCount: population, unreadableCount: 1),
                        accounting: CPUAccounting(
                            hostBusyPercent: nil, logicalCPUCount: 8,
                            measuredUserPercent: Double(population) * 25,
                            unmeasuredLifetimeCount: 1, previousScanSeconds: nil),
                        findings: rows, window: window))
            } else {
                store.append(
                    window.seal(scope: .agentsOnly), current: window.current, present: window.present)
                let snapshot = fixture.report(window: window, rows: rows, history: store.snapshot())
                reports.append(snapshot)
                state.receive(snapshot)
                if tick == 1 { state.toggleFreeze() }
            }
        }
        let frozenProjection = state.projection
        let frozenHistory = try #require(state.snapshot?.recentActivity)
        let currentHistory = try #require(reports.last?.recentActivity)
        let accepted = pending.removeFirst()
        let incoming = pending.removeFirst()
        let acceptedWindow = try #require(accepted.window)
        let incomingWindow = try #require(incoming.window)
        let limits: MonitoringPipelineLimits =
            switch admission {
            case .accept: MonitoringPipelineLimits()
            case .reject:
                MonitoringPipelineLimits(pendingObservations: acceptedWindow.payloadSize.observations)
            }
        #expect(incomingWindow.payloadSize.observations <= limits.pendingObservations)
        #expect(incomingWindow.payloadSize.textBytes <= limits.pendingTextBytes)
        let mergeCalls = Mutex(0)
        let channel = MonitoringChannel<ResolvedScan>(
            stage: .presentation, limits: limits,
            coalesce: { old, new in
                #expect(fixture.metadataCalls.withLock { $0 } == 1)
                #expect(fixture.diagnosisScans.withLock { $0 } == 4)
                #expect(!fixture.gateTimedOut.withLock { $0 })
                let size = try ResolvedScan.coalesced(&old, new, limits: limits)
                #expect(fixture.metadataCalls.withLock { $0 } == 1)
                #expect(fixture.diagnosisScans.withLock { $0 } == 4)
                #expect(!fixture.gateTimedOut.withLock { $0 })
                #expect(
                    old.window?.summary.contributions.reduce(0) { $0 + $1.cpuSeconds } == Double(population)
                        / 2)
                #expect(
                    new.window?.summary.contributions.reduce(0) { $0 + $1.cpuSeconds } == Double(population)
                        / 4)
                #expect((size.observations > limits.pendingObservations) == (admission == .reject))
                if measure { allocationReading("coexistence", population: population) }
                mergeCalls.withLock { $0 += 1 }
                return size
            })
        try await channel.send(accepted, size: acceptedWindow.payloadSize, sequence: 3)
        let enrichment = PipelineEnrichment()
        let metadata = Task {
            try await enrichment.refreshMetadata(
                reader: fixture, clock: fixture, includeCommand: true,
                checking: { try Task.checkCancellation() })
        }
        var events = fixture.events.stream.makeAsyncIterator()
        enrichment.requestMetadata(
            MetadataRefreshRequest(samples: fixture.samples(at: 0), prompt: [:], requestedAt: 0))
        #expect(await events.next() == .firstMetadata)
        enrichment.requestMetadata(
            MetadataRefreshRequest(samples: fixture.samples(at: 2), prompt: [:], requestedAt: 2))
        let diagnosis = Task {
            try await CPUDiagnosisSession(reader: fixture, clock: fixture, registry: fixture).run()
        }
        do {
            #expect(await events.next() == .diagnosis)
            // Both callbacks are inside production workers. Their release gates prove that
            // the executing requests remain alive while the UI and publication holders are inspected.
            #expect(fixture.metadataCalls.withLock { $0 } == 1)
            #expect(fixture.diagnosisScans.withLock { $0 } == 4)
            switch admission {
            case .accept:
                try await channel.send(incoming, size: incomingWindow.payloadSize, sequence: 4)
            case .reject:
                await #expect(throws: MonitoringError.overloaded(stage: .presentation, rejectedScan: 4)) {
                    try await channel.send(incoming, size: incomingWindow.payloadSize, sequence: 4)
                }
            }
            #expect(mergeCalls.withLock { $0 } == 1)
            #expect(store.diagnostics.leases == 2)
            #expect(state.frozen)
            #expect(state.snapshot?.recentActivity?.id == frozenHistory.id)
            #expect(frozenHistory.id != currentHistory.id)
            #expect(frozenHistory.finalScan == 1)
            #expect(currentHistory.finalScan == 2)
            #expect(state.snapshot?.window?.finalScan == frozenHistory.finalScan)
            #expect(reports.last?.window?.finalScan == currentHistory.finalScan)
            #expect(reports.last?.window?.runID == currentHistory.runID)
            #expect(frozenHistory.cpuSeconds == Double(population) / 4)
            #expect(currentHistory.cpuSeconds == Double(population) / 2)
            #expect(frozenHistory.present == fixture.identities)
            #expect(currentHistory.present == fixture.identities)
            #expect(state.overview.totals.recentCPU == Double(population) / 4)
            #expect(state.overview.totals.memoryBytes == UInt64(population) * 1_000_001)

            fixture.firstMetadata.signal()
            #expect(await events.next() == .secondMetadata)
            let returned = enrichment.takeResults().0
            #expect(returned.count == population)
            #expect(Set(returned.map { $0.sample.identity }) == fixture.identities)
            #expect(returned.allSatisfy { $0.sample.sampledAt == 0 })
            #expect(returned.allSatisfy { $0.metadata.command?.count == 2 })

            let delivered = try #require(await channel.next())
            let queued = try #require(delivered.window)
            let finalScan: UInt64 = admission == .accept ? 4 : 3
            let expectedCPU = Double(population) * (admission == .accept ? 0.5 : 0.25)
            #expect(queued.baseline.id.sequence == 2)
            #expect(queued.final.id.sequence == finalScan)
            #expect(delivered.acquired.timestamp == Date(timeIntervalSince1970: Double(finalScan)))
            #expect(queued.summary.contributions.reduce(0) { $0 + $1.cpuSeconds } == expectedCPU)
            #expect(queued.summary.contributions.count == population)
            #expect(Set(queued.summary.contributions.map(\.process)) == fixture.identities)
            for contribution in queued.summary.contributions {
                #expect(contribution.cpuSeconds == (admission == .accept ? 0.5 : 0.25))
                let session =
                    contribution.process.pid.isMultiple(of: 2)
                    ? "11111111-1111-1111-1111-111111111111" : "22222222-2222-2222-2222-222222222222"
                #expect(contribution.attribution.provider == .codex)
                #expect(contribution.attribution.threadID == session)
            }
            #expect(queued.present == fixture.identities)
            #expect(queued.payloadSize == queued.recountedPayloadSize)
            #expect(
                queued.summary.readCoverage.deniedPIDs
                    == (admission == .accept ? [10_003, 10_004] : [10_003]))
            #expect(accepted.window?.summary == acceptedWindow.summary)
            #expect(incoming.window?.summary == incomingWindow.summary)
            if admission == .reject {
                #expect(queued.summary == acceptedWindow.summary)
                #expect(queued.payloadSize == acceptedWindow.payloadSize)
                try await channel.send(incoming, size: incomingWindow.payloadSize, sequence: 4)
                let retried = try #require(await channel.next())
                #expect(retried.window?.summary == incomingWindow.summary)
            }
            state.toggleFreeze()
            #expect(state.snapshot?.recentActivity?.id == currentHistory.id)
            #expect(state.overview.totals.recentCPU == Double(population) / 2)
            #expect(state.overview.totals.memoryBytes == UInt64(population) * 1_000_002)
            #expect(frozenHistory.cpuSeconds == Double(population) / 4)
            #expect(frozenProjection.unpinnedRows.count == 2)

            fixture.secondMetadata.signal()
            #expect(await events.next() == .metadataFinished)
            enrichment.finish()
            try await metadata.value
            fixture.diagnosisRelease.signal()
            let result = try await diagnosis.value
            #expect(result.observedLifetimeCount == population)
            #expect(result.measuredLifetimeCount == population)
            #expect(result.cpuSeconds == Double(population) * 3 / 4)
            #expect(result.contributors.map { $0.sample.identity.pid } == Array(1...10).map(Int32.init))
            #expect(result.omittedContributorCount == population - 10)
            #expect(fixture.providerCalls.withLock { $0 } == 0)
            #expect(!fixture.gateTimedOut.withLock { $0 })
            #expect(fixture.metadataCalls.withLock { $0 } == population * 2)
            let newest = enrichment.takeResults().0
            #expect(newest.count == population)
            #expect(newest.allSatisfy { $0.sample.sampledAt == 2 })
            await channel.finish()
            #expect(try await channel.next() == nil)
        } catch {
            enrichment.finish()
            metadata.cancel()
            diagnosis.cancel()
            fixture.firstMetadata.signal()
            fixture.secondMetadata.signal()
            fixture.diagnosisRelease.signal()
            _ = try? await metadata.value
            _ = try? await diagnosis.value
            throw error
        }
    }
}

private func allocationReading(_ stage: String, population: Int) {
    // Xcode 27's malloc/malloc.h defines nil-zone statistics as the sum of all zones.
    // Summed per-zone high-water marks are not a simultaneous process peak, so omit them.
    var value = malloc_statistics_t()
    malloc_zone_statistics(nil, &value)
    print(
        "OWNERSHIP_ALLOCATOR stage=\(stage) population=\(population) "
            + "allocatedBytesInUse=\(value.size_in_use) reservedBytes=\(value.size_allocated)")
}

private final class OwnershipFixture: ProcessReading, DiagnosisReading, SamplingClock, SessionRegistryReading,
    Sendable
{
    enum Event: Sendable { case firstMetadata, secondMetadata, metadataFinished, diagnosis }
    let population: Int
    let events = AsyncStream<Event>.makeStream()
    let firstMetadata = DispatchSemaphore(value: 0)
    let secondMetadata = DispatchSemaphore(value: 0)
    let diagnosisRelease = DispatchSemaphore(value: 0)
    let metadataCalls = Mutex(0)
    let diagnosisScans = Mutex(0)
    let providerCalls = Mutex(0)
    let diagnosisReads = Mutex(0)
    let gateTimedOut = Mutex(false)
    let time = Mutex(0.0)

    init(population: Int) { self.population = population }

    var identities: Set<ProcessIdentity> {
        Set((1...population).map { ProcessIdentity(pid: Int32($0), startMicroseconds: UInt64($0)) })
    }

    func samples(at time: Double) -> [ProcessSample] {
        (1...population).map { index in
            ProcessSample(
                identity: ProcessIdentity(pid: Int32(index), startMicroseconds: UInt64(index)),
                parentPID: 0, executable: "/fixture/worker-\(index)", name: "worker-\(index)",
                sampledAt: time, cpuSeconds: time / 4, footprintBytes: 1_000_000 + UInt64(time))
        }
    }

    func row(_ sample: ProcessSample) -> HeavyProcess {
        HeavyProcess(
            process: sample.identity, executable: sample.executable, name: sample.name,
            cpuPercent: 25, footprintBytes: sample.footprintBytes,
            cwd: "/fixture/project-\(sample.identity.pid)",
            command: [sample.executable, "--worker=\(sample.identity.pid)"],
            metadataStatus: .markerRead,
            attribution: Attribution(
                provider: .codex, evidence: .marker, context: .unverified,
                threadID: sample.identity.pid.isMultiple(of: 2)
                    ? "11111111-1111-1111-1111-111111111111" : "22222222-2222-2222-2222-222222222222",
                rootSessionID: nil, runtime: nil, terminal: nil, runtimeDirectory: nil,
                candidateThreadIDs: [], ancestry: []))
    }

    func report(window: AccountingWindow, rows: [HeavyProcess], history: RecentActivitySnapshot?)
        -> MonitoringSnapshot
    {
        MonitoringSnapshot(
            cpuAccounting: CPUAccounting(
                hostBusyPercent: nil, logicalCPUCount: 8, measuredUserPercent: Double(population) * 25,
                unmeasuredLifetimeCount: 0, previousScanSeconds: nil),
            timestamp: Date(timeIntervalSince1970: Double(window.final.id.sequence)), intervalSeconds: 1,
            cpuThresholdPercent: 0, memoryThresholdBytes: 0, sampledProcessCount: population,
            unreadableProcessCount: 0, findings: rows, window: window.summary, recentActivity: history)
    }

    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        diagnosisScans.withLock { $0 += 1 }
        let at = monotonicNow()
        return ProcessSnapshot(
            samples: samples(at: at), enumeratedCount: population, unreadableCount: 0,
            listedAt: at, scanSeconds: 0, hostCounters: nil, logicalCPUCount: 8)
    }

    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        let call = metadataCalls.withLock {
            $0 += 1
            return $0
        }
        if call == 1 {
            events.continuation.yield(.firstMetadata)
            waitForRelease(firstMetadata)
        } else if call == population + 1 {
            events.continuation.yield(.secondMetadata)
            waitForRelease(secondMetadata)
        }
        if call == population * 2 { events.continuation.yield(.metadataFinished) }
        return ProcessMetadata(
            status: .markerRead,
            command: includeCommand ? [sample.executable, "--worker=\(sample.identity.pid)"] : nil)
    }

    func observation(for sample: ProcessSample) -> DiagnosisObservation {
        if diagnosisReads.withLock({
            $0 += 1
            return $0
        }) == 1 {
            events.continuation.yield(.diagnosis)
            waitForRelease(diagnosisRelease)
        }
        return .observed(ProcessMetadata(status: .notObserved))
    }

    private func waitForRelease(_ gate: DispatchSemaphore) {
        if gate.wait(timeout: .now() + 10) != .success { gateTimedOut.withLock { $0 = true } }
    }

    func isCurrent(_ sample: ProcessSample) -> Bool { true }
    func output(of query: SessionRegistryQuery) throws -> Data {
        providerCalls.withLock { $0 += 1 }
        return Data("[]".utf8)
    }
    func wait(seconds: Double) async throws { time.withLock { $0 += seconds } }
    func monotonicNow() -> Double { time.withLock { $0 } }
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }
}

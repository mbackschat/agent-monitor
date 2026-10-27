import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

struct AdaptiveWorkloadLife: Sendable {
    enum CPU: Sendable {
        case steady(Double)
        case heartbeat(amount: Double, period: Double)
        case burst(from: Double, until: Double, rate: Double)
    }
    var pid: Int32
    var birth: Double
    var end: Double
    var cpu: CPU = .steady(1)
    var resolution: AdaptiveSamplingEvidence.Resolution = .supported
    var resolutionDelay = 0.0
    var inScope = true
    var helper = false
    var failures: Range<Double>?
    var verifiedFailure = true
    var execAt: Double?
    var readOffset: Double?
    var parentPID: Int32 = 1
    var sessionID: String = sessionA

    var identity: ProcessIdentity {
        ProcessIdentity(pid: pid, startMicroseconds: UInt64(((birth + 10_000) * 1_000_000).rounded()))
    }
    func alive(_ time: Double) -> Bool { birth <= time && time < end }
    func cumulative(_ time: Double) -> Double {
        let age = max(0, min(end, time) - birth)
        switch cpu {
        case .steady(let rate): return age * rate
        case .heartbeat(let amount, let period):
            return floor((age + 1e-9) / period) * amount
        case .burst(let from, let until, let rate):
            return max(0, min(time, end, until) - max(birth, from)) * rate
        }
    }
    func reading(_ time: Double) -> ProcessSample {
        let failed = failures?.contains(time) == true
        let executable =
            execAt.map { time >= $0 ? "/fixture/compiled-worker" : "/fixture/worker" }
            ?? "/fixture/worker"
        var value = sample(
            pid, parent: parentPID, start: identity.startMicroseconds, executable: executable,
            at: time, cpu: failed ? nil : cumulative(time), memory: failed ? nil : 128)
        value.startedAt = birth
        if !failed {
            value.rawCPU = NativeCPUCounters(
                user: UInt64((cumulative(time) * 1e9).rounded()), system: 0,
                numerator: 1, denominator: 1)
        }
        return value
    }
}

enum AdaptiveWorkloadArm: String, CaseIterable { case adaptive, fixedMinimum, fixedMaximum }
enum AdaptiveWorkloadEnd: Error { case horizon, failedListing }

struct AdaptiveWorkloadScenario {
    var name: String
    var lives: [AdaptiveWorkloadLife]
    var horizon = 240.0
    var scanSeconds = 0.002
    var maximum = 0.625
    var window = 60.0
    var calibration = AdaptiveSamplingPrototype.Calibration()
    var relaxPersistentFailures = false
    var failedListingAt: Double?
}

final class AdaptiveWorkloadReader: ProcessReading, AcquisitionClock, SessionRegistryReading {
    struct Tick {
        var start: Double
        var end: Double
        var requested: Double
        var decision: AdaptiveSamplingPrototype.Decision
        var persistent: Int
    }
    struct State {
        var time = 0.0
        var ledger = CounterLedger()
        var evidence: AdaptiveSamplingEvidence
        var policy: AdaptiveSamplingPrototype
        var ticks: [Tick] = []
        var accepted: [ProcessIdentity: Double] = [:]
        var intervals: [ProcessIdentity: Int] = [:]
        var lastReads: [ProcessIdentity: Double] = [:]
        var firstReads: [ProcessIdentity: Double] = [:]
        var identities: Set<ProcessIdentity> = []
        var executables: [ProcessIdentity: String] = [:]
        var requested = 0.1
    }
    let state: Mutex<State>
    let scenario: AdaptiveWorkloadScenario
    let arm: AdaptiveWorkloadArm
    let live: LiveInterval
    let productionController: Bool

    init(
        _ scenario: AdaptiveWorkloadScenario, arm: AdaptiveWorkloadArm, productionController: Bool = false
    ) {
        self.scenario = scenario
        self.arm = arm
        self.productionController = productionController
        if productionController {
            live = LiveInterval(
                settings: SamplingSettings(
                    enabled: true, visibleMaximum: scenario.maximum, window: scenario.window))
        } else {
            live = LiveInterval(arm == .fixedMaximum ? scenario.maximum : 0.1)
        }
        state = Mutex(
            State(
                evidence: AdaptiveSamplingEvidence(relaxPersistentFailures: scenario.relaxPersistentFailures),
                policy: AdaptiveSamplingPrototype(
                    maximum: scenario.maximum, window: scenario.window,
                    calibration: scenario.calibration)))
    }
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }
    func monotonicNow() -> Double { state.withLock { $0.time } }
    func wait(until deadline: Double, wake: AcquisitionWake) throws {
        try state.withLock {
            guard deadline + scenario.scanSeconds <= scenario.horizon else {
                throw AdaptiveWorkloadEnd.horizon
            }
            if productionController, let last = $0.ticks.last { $0.requested = deadline - last.start }
            $0.time = max($0.time, deadline)
        }
    }
    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let output = try state.withLock { state -> (ProcessSnapshot, Double) in
            let start = state.time
            let end = start + scenario.scanSeconds
            guard end <= scenario.horizon else { throw AdaptiveWorkloadEnd.horizon }
            if let failure = scenario.failedListingAt, start >= failure {
                throw AdaptiveWorkloadEnd.failedListing
            }
            let listed = scenario.lives.filter { $0.alive(start) && !excluding.contains($0.pid) }
            var readings: [ProcessSample] = []
            let observations = listed.map { life -> AdaptiveSamplingEvidence.Observation in
                let readAt = start + (life.readOffset ?? scenario.scanSeconds)
                let failed = life.failures?.contains(readAt) == true
                let identityVerified = life.alive(readAt) && (!failed || life.verifiedFailure)
                let resolution: AdaptiveSamplingEvidence.Resolution? =
                    readAt - life.birth >= life.resolutionDelay ? life.resolution : nil
                var invalidated = false
                if identityVerified && life.inScope {
                    let reading = life.reading(readAt)
                    invalidated = state.executables[life.identity].map { $0 != reading.executable } ?? false
                    state.executables[life.identity] = reading.executable
                    state.identities.insert(life.identity)
                    readings.append(reading)
                    if !failed {
                        state.lastReads[life.identity] = readAt
                        if state.firstReads[life.identity] == nil { state.firstReads[life.identity] = readAt }
                    }
                }
                return .init(
                    pid: life.pid, identity: identityVerified ? life.identity : nil,
                    birth: identityVerified ? life.birth : nil,
                    resolution: identityVerified ? resolution : nil,
                    invalidated: invalidated,
                    inScope: life.inScope, provenHelper: identityVerified && life.helper,
                    read: identityVerified && !failed
                        ? .available : .failure(code: 3, verified: identityVerified))
            }
            let snapshot = ProcessSnapshot(
                samples: readings, enumeratedCount: listed.count,
                unreadableCount: observations.filter { $0.inScope && $0.read != .available }.count,
                listedAt: start, scanSeconds: scenario.scanSeconds, hostCounters: nil, logicalCPUCount: 8,
                listedPIDs: listed.map(\.pid))
            let counters = state.ledger.ingest(
                readings, listedAt: start, scanSeconds: scenario.scanSeconds, source: snapshot)
            for contribution in counters.contributions {
                let id = contribution.id.closing.process
                state.accepted[id, default: 0] += contribution.cpuSeconds
                state.intervals[id, default: 0] += contribution.intervalCount
            }
            let evidence = state.evidence.ingest(
                observations, contributions: counters.contributions,
                listedAt: start, closedAt: end, window: scenario.window)
            let decision = state.policy.observe(evidence.aggregate, uncertain: evidence.uncertain)
            let interval: Double
            switch arm {
            case .adaptive: interval = decision.requested
            case .fixedMinimum: interval = 0.1
            case .fixedMaximum: interval = scenario.maximum
            }
            state.ticks.append(
                Tick(
                    start: start, end: end, requested: productionController ? state.requested : interval,
                    decision: decision,
                    persistent: evidence.persistentlyUnreadable))
            state.time = end
            return (snapshot, interval)
        }
        if !productionController { live.set(output.1) }
        return output.0
    }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        guard let life = scenario.lives.first(where: { $0.identity == sample.identity }),
            sample.sampledAt - life.birth >= life.resolutionDelay,
            life.resolution == .supported, !life.helper
        else { return ProcessMetadata() }
        return ProcessMetadata(
            markers: [SessionMarker(threadID: life.sessionID, provider: .codex)], status: .markerRead)
    }
    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        metadata(for: sample, includeCommand: false)
    }
    func output(of query: SessionRegistryQuery) throws -> Data { Data("[]".utf8) }
}

struct AdaptiveWorkloadResult {
    let ticks: [AdaptiveWorkloadReader.Tick]
    let accepted: [ProcessIdentity: Double]
    let lastReads: [ProcessIdentity: Double]
    let firstReads: [ProcessIdentity: Double]
    let identities: Set<ProcessIdentity>
    let contributions: [FrozenCPUContribution]
    let sampling: SamplingCoverage

    func scans(in range: Range<Double>) -> Int { ticks.filter { range.contains($0.start) }.count }
    func fraction(in range: Range<Double>, matching predicate: (AdaptiveWorkloadReader.Tick) -> Bool)
        -> Double
    {
        var duration = 0.0
        for (index, tick) in ticks.enumerated() where predicate(tick) {
            let end = index + 1 < ticks.count ? ticks[index + 1].start : range.upperBound
            duration += max(0, min(end, range.upperBound) - max(tick.start, range.lowerBound))
        }
        return duration / (range.upperBound - range.lowerBound)
    }
    func partition(_ scenario: AdaptiveWorkloadScenario) -> (
        total: Double, accepted: Double, unseen: Double, unreadable: Double, tail: Double, initial: Double
    ) {
        var total = 0.0
        var unseen = 0.0
        var tail = 0.0
        var initial = 0.0
        var unreadable = 0.0
        for life in scenario.lives where life.inScope {
            let endCPU = life.cumulative(scenario.horizon)
            let openingCPU = life.cumulative(0)
            let work = endCPU - openingCPU
            total += work
            if let last = lastReads[life.identity] {
                tail += endCPU - life.cumulative(last)
                if life.birth <= 0, let first = firstReads[life.identity] {
                    initial += life.cumulative(first) - openingCPU
                }
            } else if identities.contains(life.identity) {
                unreadable += work
            } else {
                unseen += work
            }
        }
        let cpu = scenario.lives.filter(\.inScope).reduce(0) { $0 + (accepted[$1.identity] ?? 0) }
        return (total, cpu, unseen, unreadable, tail, initial)
    }
}

func runAdaptiveWorkload(
    _ scenario: AdaptiveWorkloadScenario, arm: AdaptiveWorkloadArm, productionController: Bool = false
) async throws
    -> AdaptiveWorkloadResult
{
    let reader = AdaptiveWorkloadReader(scenario, arm: arm, productionController: productionController)
    // Virtual time can outrun publication; reserve the finite scenario's maximum unit population.
    let limits = MonitoringPipelineLimits(
        pendingScans: Int(scenario.horizon) + 2,
        pendingObservations: 1_000_000, pendingTextBytes: 64 * 1_024 * 1_024)
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(
            intervalSeconds: reader.live.seconds, samples: 0, scope: .allProcesses, pipelineLimits: limits,
            promptCaptureLimits: PromptCaptureLimits(attempts: 512, bytes: 512 * 65_536),
            reportIntervalSeconds: 1, sampling: productionController ? reader.live.settings : nil),
        reader: reader, clock: reader, registry: reader)
    let windows = Mutex<[FrozenCPUContribution]>([])
    let sampling = Mutex(SamplingCoverage())
    do {
        try await session.run(interval: reader.live) { value in
            #expect(value.window?.collapsedContributions.isEmpty != false)
            windows.withLock { $0.append(contentsOf: value.window?.contributions ?? []) }
            if let coverage = value.window?.acquisitionCoverage.sampling {
                sampling.withLock { $0.merge(coverage) }
            }
        }
        Issue.record("The bounded fixture must end at its explicit horizon or listing failure")
    } catch AdaptiveWorkloadEnd.horizon {
    } catch AdaptiveWorkloadEnd.failedListing {
        #expect(scenario.failedListingAt != nil)
    }
    let contributions = windows.withLock { $0 }
    let state = reader.state.withLock { $0 }
    let delivered = Dictionary(grouping: contributions, by: \.process)
    #expect(Set(delivered.keys) == Set(state.accepted.keys))
    for (id, cpu) in state.accepted {
        #expect(abs((delivered[id] ?? []).reduce(0) { $0 + $1.cpuSeconds } - cpu) < 1e-7)
        #expect((delivered[id] ?? []).reduce(0) { $0 + $1.intervalCount } == state.intervals[id])
    }
    let result = AdaptiveWorkloadResult(
        ticks: state.ticks, accepted: state.accepted, lastReads: state.lastReads,
        firstReads: state.firstReads, identities: state.identities,
        contributions: contributions, sampling: sampling.withLock { $0 })
    let partition = result.partition(scenario)
    #expect(
        abs(
            partition.total - partition.accepted - partition.unseen - partition.unreadable - partition.tail
                - partition.initial) < 1e-6)
    return result
}

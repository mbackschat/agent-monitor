import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

enum WorkloadCPUShape: CaseIterable, Sendable {
    case uniform, firstFiftyMilliseconds, lastFiftyMilliseconds
}

private struct WorkloadLife: Sendable {
    let pid: Int32
    let birth: Int
    let end: Int
    var shape: WorkloadCPUShape = .uniform
    var rate = 1
    var execAt: Int?

    var identity: ProcessIdentity {
        ProcessIdentity(pid: pid, startMicroseconds: UInt64(max(1, birth + 10_000)) * 1_000)
    }
    func alive(at time: Int) -> Bool { birth <= time && time < end }
    func cpuMilliseconds(at time: Int) -> Int {
        let age = max(0, min(time, end) - birth)
        switch shape {
        case .uniform: return age * rate
        case .firstFiftyMilliseconds: return min(age, 50) * rate
        case .lastFiftyMilliseconds: return max(0, age - max(0, end - birth - 50)) * rate
        }
    }
    func reading(at time: Int) -> ProcessSample {
        let executable = execAt.map { time >= $0 ? "/fixture/tsc" : "/fixture/node" } ?? "/fixture/node"
        var result = sample(
            pid, start: identity.startMicroseconds, executable: executable,
            at: Double(time) / 1_000, cpu: Double(cpuMilliseconds(at: time)) / 1_000, memory: 128)
        result.startedAt = Double(birth) / 1_000
        result.rawCPU = NativeCPUCounters(
            user: UInt64(cpuMilliseconds(at: time)) * 1_000_000, system: 0, numerator: 1, denominator: 1)
        return result
    }
}

private final class WorkloadCoverageReader: ProcessReading, AcquisitionClock, InspectionReading {
    struct State {
        var time = 0.0
        var lastReadTimes: [ProcessIdentity: Int] = [:]
    }
    let state = Mutex(State())
    let lives: [WorkloadLife]

    init(_ lives: [WorkloadLife]) { self.lives = lives }
    func monotonicNow() -> Double { state.withLock { $0.time } }
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }
    func wait(until deadline: Double, wake: AcquisitionWake) { state.withLock { $0.time = deadline } }
    private var milliseconds: Int { Int((monotonicNow() * 1_000).rounded()) }

    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let time = milliseconds
        let values = lives.filter { $0.alive(at: time) && !excluding.contains($0.pid) }.map {
            $0.reading(at: time)
        }
        state.withLock { state in
            for value in values { state.lastReadTimes[value.identity] = time }
        }
        return ProcessSnapshot(
            samples: values, enumeratedCount: values.count, unreadableCount: 0,
            listedAt: Double(time) / 1_000, scanSeconds: 0, hostCounters: nil, logicalCPUCount: 8,
            listedPIDs: values.map(\.identity.pid))
    }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata { ProcessMetadata() }
    func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? { nil }
    func inspectionPIDs(allowance: InspectionAllowance) throws -> [Int32] {
        guard allowance.permitsOperation() else { return [] }
        return lives.filter { $0.alive(at: milliseconds) }.map(\.pid)
    }
    func inspectionRead(_ pid: Int32, allowance: InspectionAllowance) -> InspectionRead? {
        guard allowance.permitsOperation(),
            let life = lives.first(where: { $0.pid == pid && $0.alive(at: milliseconds) })
        else {
            return nil
        }
        let time = milliseconds
        let value = life.reading(at: time)
        state.withLock { $0.lastReadTimes[value.identity] = time }
        return InspectionRead(sample: value, parent: nil, cwd: nil)
    }
}

private struct WorkloadCoverageResult {
    let lastReadTimes: [ProcessIdentity: Int]
    let contributions: [FrozenCPUContribution]
    let findings: [HeavyProcess]
    let final: MonitoringSnapshot
    let inspection: InspectionCoverage
    var readings: Set<ProcessIdentity> { Set(lastReadTimes.keys) }

    func cpu(_ identities: Set<ProcessIdentity>) -> Double {
        contributions.filter { identities.contains($0.process) }.reduce(0) { $0 + $1.cpuSeconds }
    }
    func partition(_ lives: [WorkloadLife]) -> (accepted: Double, unseen: Double, tail: Double, total: Double)
    {
        let identities = Set(lives.map(\.identity))
        let total = Double(lives.reduce(0) { $0 + $1.cpuMilliseconds(at: $1.end) }) / 1_000
        let unseen =
            Double(
                lives.filter { !readings.contains($0.identity) }.reduce(0) {
                    $0 + $1.cpuMilliseconds(at: $1.end)
                }) / 1_000
        let accepted = cpu(identities)
        let tail =
            Double(
                lives.reduce(0) { sum, life in
                    guard let lastRead = lastReadTimes[life.identity] else { return sum }
                    return sum + life.cpuMilliseconds(at: life.end) - life.cpuMilliseconds(at: lastRead)
                }) / 1_000
        return (accepted, unseen, tail, total)
    }
}

private func collectWorkload(_ lives: [WorkloadLife], inspection enabled: Bool) async throws
    -> WorkloadCoverageResult
{
    let reader = WorkloadCoverageReader(lives)
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(
            intervalSeconds: 0.1, samples: 2, scope: .allProcesses,
            reportIntervalSeconds: 1, inspectionObservations: enabled),
        reader: reader, clock: reader)
    let snapshots = Mutex<[MonitoringSnapshot]>([])
    try await session.run(inspection: LiveInspection(active: true)) { value in
        snapshots.withLock { $0.append(value) }
    }
    let values = snapshots.withLock { $0 }
    let final = try #require(values.last)
    var coverage = InspectionCoverage()
    for value in values { coverage.merge(try #require(value.window).inspectionCoverage) }
    return WorkloadCoverageResult(
        lastReadTimes: reader.state.withLock { $0.lastReadTimes },
        contributions: values.flatMap { $0.window?.contributions ?? [] },
        findings: values.flatMap(\.observedFindings), final: final, inspection: coverage)
}

@Suite struct WorkloadCoverageTests {
    @Test(arguments: [500, 1_000], WorkloadCPUShape.allCases)
    func subsecondDiscoveryDoesNotEstablishFinalCPU(milliseconds: Int, shape: WorkloadCPUShape) async throws {
        // The playbook distinguishes observed ages from lifetimes; these phase and CPU shapes are assumptions.
        let lives = (0..<10).map { offset in
            WorkloadLife(
                pid: Int32(100 + offset), birth: 5 + offset * 10, end: 5 + offset * 10 + milliseconds,
                shape: shape)
        }
        let baseline = try await collectWorkload(lives, inspection: false)
        let discovery = try await collectWorkload(lives, inspection: true)
        let identities = Set(lives.map(\.identity))
        #expect(baseline.readings == identities)
        #expect(discovery.readings == identities)
        let expected: Double
        switch shape {
        case .uniform: expected = Double(milliseconds * 10 - 500) / 1_000
        case .firstFiftyMilliseconds: expected = 0.5
        case .lastFiftyMilliseconds: expected = 0.125
        }
        for result in [baseline, discovery] {
            let loss = result.partition(lives)
            #expect(abs(loss.accepted - expected) < 1e-9)
            #expect(loss.unseen == 0)
            #expect(abs(loss.tail - (loss.total - expected)) < 1e-9)
            #expect(abs(loss.accepted + loss.unseen + loss.tail - loss.total) < 1e-9)
            #expect(result.final.sampledProcessCount == 0)
        }
        #expect(discovery.inspection.candidatesRead == 5)
        #expect(discovery.inspection.supersededReadings == 5)
        #expect(discovery.inspection.carriedObservations == 0)
    }

    @Test(arguments: [false, true])
    func overlapExecAndReuseSeparateNeverReadCPUFromFinalTails(enabled: Bool) async throws {
        let lives = [
            WorkloadLife(pid: 100, birth: 10, end: 40),
            WorkloadLife(pid: 101, birth: 20, end: 80),
            WorkloadLife(pid: 102, birth: 60, end: 180),
            WorkloadLife(pid: 103, birth: 10, end: 260, execAt: 130),
            WorkloadLife(pid: 104, birth: 10, end: 120),
            WorkloadLife(pid: 104, birth: 130, end: 180),
        ]
        let background = WorkloadLife(pid: 200, birth: -1_000, end: 3_000, rate: 2)
        let result = try await collectWorkload(lives + [background], inspection: enabled)
        let loss = result.partition(lives)
        let expectedSeen = Set(
            [lives[2], lives[3], lives[4], background].map(\.identity) + (enabled ? [lives[1].identity] : []))
        #expect(result.readings == expectedSeen)
        #expect(abs(loss.accepted - (enabled ? 0.35 : 0.32)) < 1e-9)
        #expect(abs(loss.unseen - (enabled ? 0.08 : 0.14)) < 1e-9)
        #expect(abs(loss.tail - (enabled ? 0.19 : 0.16)) < 1e-9)
        #expect(abs(loss.total - 0.62) < 1e-9)
        #expect(abs(loss.accepted + loss.unseen + loss.tail - loss.total) < 1e-9)
        #expect(abs(result.cpu([background.identity]) - 4) < 1e-9)
        let exec = result.contributions.filter { $0.process == lives[3].identity }
        let changed = try #require(exec.first { $0.executableChangedIntervalCount > 0 })
        #expect(abs(changed.cpuSeconds - 0.1) < 1e-9)
        #expect(abs(result.cpu([lives[3].identity]) - 0.19) < 1e-9)
        #expect(
            result.findings.contains { $0.process == lives[3].identity && $0.executable == "/fixture/tsc" })
        #expect(result.final.sampledProcessCount == 1)
        let current = result.final.observedFindings.filter { !$0.isHistorical }
        #expect(current.map(\.process) == [background.identity])
        #expect(current.first?.footprintBytes == 128)
    }

    @Test(arguments: [false, true])
    func simultaneousBurstRespectsDiscoveryAdmissionAndPreservesOnlyObservedCPU(enabled: Bool) async throws {
        let lives = (0..<24).map { WorkloadLife(pid: Int32(100 + $0), birth: 20, end: 80) }
        let result = try await collectWorkload(lives, inspection: enabled)
        let loss = result.partition(lives)
        #expect(result.readings == Set(enabled ? lives.prefix(16).map(\.identity) : []))
        #expect(abs(loss.accepted - (enabled ? 0.48 : 0)) < 1e-9)
        #expect(abs(loss.unseen - (enabled ? 0.48 : 1.44)) < 1e-9)
        #expect(abs(loss.tail - (enabled ? 0.48 : 0)) < 1e-9)
        #expect(abs(loss.accepted + loss.unseen + loss.tail - loss.total) < 1e-9)
        #expect(result.inspection.candidatesLeftUnread == (enabled ? 8 : 0))
        #expect(result.inspection.carriedObservations == (enabled ? 16 : 0))
        #expect(result.final.sampledProcessCount == 0)
        let historical = result.findings.filter { result.readings.contains($0.process) }
        #expect(Set(historical.map(\.process)).count == (enabled ? 16 : 0))
        #expect(historical.allSatisfy { $0.isHistorical && $0.footprintBytes == nil })
    }
}

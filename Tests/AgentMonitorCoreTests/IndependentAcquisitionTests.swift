import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private final class IndependentReader: ProcessReading, SamplingClock, SessionRegistryReading, Sendable {
    enum BlockingStage { case metadata, provider }
    let blockingStage: BlockingStage
    let providerCalls = Mutex(0)
    init(blockingStage: BlockingStage = .metadata) { self.blockingStage = blockingStage }
    let scans = Mutex(0)
    let acquisitionThreads = Mutex<[String]>([])
    let resolutionThreads = Mutex<[String]>([])
    let progressedDuringMetadata = Mutex(false)
    let thirdScan = DispatchSemaphore(value: 0)
    let events = AsyncStream<Int>.makeStream()

    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        acquisitionThreads.withLock { $0.append(Thread.current.name ?? "unnamed") }
        let index = scans.withLock { value in
            defer { value += 1 }
            return value
        }
        if index == 2 { thirdScan.signal() }
        events.continuation.yield(index)
        let executable =
            blockingStage == .provider ? "/Users/test/.local/share/claude/versions/2.1.301" : "/bin/worker"
        return diagnosisScan(
            [sample(42, executable: executable, at: Double(index), cpu: Double(index))], at: Double(index))
    }

    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        let first = resolutionThreads.withLock { names in
            defer { names.append(Thread.current.name ?? "unnamed") }
            return names.isEmpty
        }
        if first, blockingStage == .metadata {
            let progressed = thirdScan.wait(timeout: .now() + 1) == .success
            progressedDuringMetadata.withLock { $0 = progressed }
        }
        if blockingStage == .provider { return ProcessMetadata(status: .markerRead, invocation: "claude") }
        return ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)])
    }

    func isCurrent(_ sample: ProcessSample) -> Bool { true }
    func output(of query: SessionRegistryQuery) throws -> Data {
        providerCalls.withLock { $0 += 1 }
        resolutionThreads.withLock { $0.append(Thread.current.name ?? "unnamed") }
        let progressed = thirdScan.wait(timeout: .now() + 1) == .success
        progressedDuringMetadata.withLock { $0 = progressed }
        return Data("[{\"pid\":42,\"sessionId\":\"\(sessionB)\",\"status\":\"busy\"}]".utf8)
    }

    func wait(seconds: Double) async throws { try Task.checkCancellation() }
    func monotonicNow() -> Double { now().timeIntervalSinceReferenceDate }
    func now() -> Date { Date(timeIntervalSince1970: 0) }
}

@Suite struct IndependentAcquisitionTests {
    @Test func blockedMetadataCannotStopCounterAcquisition() async throws {
        let fixture = IndependentReader()
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(samples: 3), reader: fixture, clock: fixture)
        let results = Mutex<[MonitoringSnapshot]>([])
        try await session.run { snapshot in results.withLock { $0.append(snapshot) } }
        #expect(fixture.progressedDuringMetadata.withLock { $0 })
        #expect(fixture.scans.withLock { $0 } == 4)
        #expect(results.withLock { $0.count } == 3)
        #expect(results.withLock { $0.allSatisfy { $0.findings.first?.attribution.threadID == sessionA } })
        #expect(Set(fixture.acquisitionThreads.withLock { $0 }) == ["AgentMonitor acquisition"])
        #expect(Set(fixture.resolutionThreads.withLock { $0 }) == ["AgentMonitor resolution"])
    }

    @Test func blockedProviderCannotStopCountersAndStillResolvesTheExactSession() async throws {
        let fixture = IndependentReader(blockingStage: .provider)
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(samples: 3), reader: fixture, clock: fixture,
            registry: fixture)
        let results = Mutex<[MonitoringSnapshot]>([])
        try await session.run { snapshot in results.withLock { $0.append(snapshot) } }
        #expect(fixture.progressedDuringMetadata.withLock { $0 })
        #expect(fixture.scans.withLock { $0 } == 4)
        #expect(fixture.providerCalls.withLock { $0 } == 1)
        #expect(results.withLock { $0.allSatisfy { $0.findings.first?.attribution.threadID == sessionB } })
        #expect(Set(fixture.resolutionThreads.withLock { $0 }) == ["AgentMonitor resolution"])
    }

    @Test func waitingConsumerDoesNotHoldAcquisition() async throws {
        let fixture = IndependentReader()
        let session = MonitoringSession(
            configuration: try MonitoringConfiguration(samples: 3), reader: fixture, clock: fixture)
        let count = Mutex(0)
        try await session.run { _ in
            let first = count.withLock {
                $0 += 1
                return $0 == 1
            }
            if first {
                let completed = await withTaskGroup(of: Bool.self) { group in
                    group.addTask {
                        for await scan in fixture.events.stream where scan == 3 { return true }
                        return false
                    }
                    group.addTask {
                        try? await Task.sleep(for: .seconds(2))
                        return false
                    }
                    defer { group.cancelAll() }
                    return await group.next() ?? false
                }
                #expect(completed)
            }
        }
        #expect(count.withLock { $0 } == 3)
    }
}

private final class CadenceFixture: ProcessReading, SamplingClock, Sendable {
    struct State {
        var time = 0.0
        var waits: [Double] = []
    }
    let state = Mutex(State())
    let scanDuration: Double
    init(scanDuration: Double) { self.scanDuration = scanDuration }

    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        state.withLock { state in
            let start = state.time
            state.time += scanDuration
            return diagnosisScan(
                [sample(42, at: state.time, cpu: state.time)], at: start, scan: scanDuration)
        }
    }
    func metadata(for sample: ProcessSample, includeCommand: Bool) -> ProcessMetadata {
        ProcessMetadata(markers: [SessionMarker(threadID: sessionA, provider: .codex)])
    }
    func wait(seconds: Double) async throws {
        try Task.checkCancellation()
        state.withLock {
            $0.waits.append(seconds)
            $0.time += seconds
        }
    }
    func now() -> Date { Date(timeIntervalSince1970: monotonicNow()) }
    func monotonicNow() -> Double { state.withLock { $0.time } }
}

@Test(arguments: [0.2, 1.5]) func acquisitionUsesStartToStartCadenceWithoutCatchup(scanDuration: Double)
    async throws
{
    let fixture = CadenceFixture(scanDuration: scanDuration)
    let session = MonitoringSession(
        configuration: try MonitoringConfiguration(intervalSeconds: 1, samples: 3), reader: fixture,
        clock: fixture)
    let reports = Mutex<[MonitoringSnapshot]>([])
    try await session.run { report in reports.withLock { $0.append(report) } }
    let values = reports.withLock { $0 }
    #expect(values.count == 3)
    for report in values {
        let timing = try #require(report.cpuAccounting.acquisition)
        #expect(abs(try #require(timing.achievedPeriodSeconds) - max(1, scanDuration)) < 0.000_001)
        #expect(abs(timing.scanWorkSeconds - scanDuration) < 0.000_001)
        #expect(timing.qualityOfService == .userInitiated)
    }
    let waits = fixture.state.withLock { $0.waits }
    if scanDuration < 1 {
        #expect(waits.count == 3)
        #expect(waits.allSatisfy { abs($0 - 0.8) < 0.000_001 })
    } else {
        #expect(waits.isEmpty)
    }
}

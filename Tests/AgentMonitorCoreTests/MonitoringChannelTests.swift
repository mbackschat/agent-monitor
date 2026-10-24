import Testing

@testable import AgentMonitorCore

@Suite struct MonitoringChannelTests {
    @Test(arguments: ["scans", "observations", "text"])
    func everyRetentionLimitRejectsWithoutDroppingAcceptedWork(bound: String) async throws {
        let channel = MonitoringChannel<Int>(
            stage: .resolution,
            limits: MonitoringPipelineLimits(
                pendingScans: bound == "scans" ? 1 : 10,
                pendingObservations: bound == "observations" ? 1 : 10,
                pendingTextBytes: bound == "text" ? 1 : 10))
        let size = MonitoringPayloadSize(observations: 1, textBytes: 1)
        try await channel.send(1, size: size, sequence: 1)
        await #expect(throws: MonitoringError.self) { try await channel.send(2, size: size, sequence: 2) }
        await channel.finish(throwing: MonitoringError.overloaded(stage: .resolution, rejectedScan: 2))
        #expect(try await channel.next() == 1)
        await #expect(throws: MonitoringError.self) { try await channel.next() }
    }

    @Test func consumedEntriesReleaseCapacityAndKeepOrder() async throws {
        let channel = MonitoringChannel<Int>(
            stage: .resolution,
            limits: MonitoringPipelineLimits(
                pendingScans: 2, pendingObservations: 2, pendingTextBytes: 2))
        let size = MonitoringPayloadSize(observations: 1, textBytes: 1)
        for value in 0..<100 {
            try await channel.send(value, size: size, sequence: UInt64(value))
            #expect(try await channel.next() == value)
        }
        await channel.finish()
        #expect(try await channel.next() == nil)
    }

    @Test func cancellingAnEmptyWaitDoesNotLeakAContinuation() async throws {
        let channel = MonitoringChannel<Int>(stage: .resolution, limits: MonitoringPipelineLimits())
        let task = Task { try await channel.next() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func oneOversizedScanCannotBypassTheBudget() async throws {
        let channel = MonitoringChannel<Int>(
            stage: .resolution,
            limits: MonitoringPipelineLimits(
                pendingObservations: 1))
        await #expect(throws: MonitoringError.self) {
            try await channel.send(1, size: .init(observations: 2, textBytes: 0), sequence: 0)
        }
        await channel.finish()
        #expect(try await channel.next() == nil)
    }
}

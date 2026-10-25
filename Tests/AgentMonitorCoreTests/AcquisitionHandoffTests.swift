import Testing

@testable import AgentMonitorCore

@Suite struct AcquisitionHandoffTests {
    @Test func rejectedUnitLeavesAcceptedUnitsInOrder() async throws {
        let handoff = AcquisitionHandoff<Int>(
            limits: MonitoringPipelineLimits(pendingScans: 2, pendingObservations: 2, pendingTextBytes: 2))
        let size = MonitoringPayloadSize(observations: 1, textBytes: 1)
        try handoff.send(1, size: size, sequence: 1)
        try handoff.send(2, size: size, sequence: 2)
        #expect(throws: MonitoringError.overloaded(stage: .publication, rejectedScan: 3)) {
            try handoff.send(3, size: size, sequence: 3)
        }
        handoff.finish(throwing: MonitoringError.overloaded(stage: .publication, rejectedScan: 3))
        #expect(try await handoff.next() == 1)
        #expect(try await handoff.next() == 2)
        await #expect(throws: MonitoringError.overloaded(stage: .publication, rejectedScan: 3)) {
            try await handoff.next()
        }
    }

    @Test func ringReleasesConsumedCapacity() async throws {
        let handoff = AcquisitionHandoff<Int>(limits: MonitoringPipelineLimits(pendingScans: 2))
        for i in 0..<1000 {
            try handoff.send(i, size: .init(observations: 1, textBytes: 0), sequence: UInt64(i))
            #expect(try await handoff.next() == i)
        }
        handoff.finish()
        #expect(try await handoff.next() == nil)
    }

    @Test func cancelledEmptyConsumerFinishes() async {
        let handoff = AcquisitionHandoff<Int>(limits: MonitoringPipelineLimits())
        let task = Task { try await handoff.next() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

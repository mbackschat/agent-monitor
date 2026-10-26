import Testing

@testable import AgentMonitorCore

@Suite struct AcquisitionHandoffTests {
    enum Budget: CaseIterable { case units, records, text }

    @Test(arguments: Budget.allCases)
    func eachBudgetRejectsWithoutDisplacingAcceptedUnits(budget: Budget) async throws {
        let handoff = AcquisitionHandoff<Int>(
            limits: MonitoringPipelineLimits(
                pendingScans: budget == .units ? 2 : 10,
                pendingObservations: budget == .records ? 2 : 10,
                pendingTextBytes: budget == .text ? 2 : 10))
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

    private enum Stopped: Error { case acquisition }

    /// Locks the failure path: a full ring rejecting the drained partial must not replace the
    /// error that stopped acquisition with a publication overload.
    @Test func failedAcquisitionKeepsItsErrorWhenTheDrainedUnitDoesNotFit() async throws {
        let handoff = AcquisitionHandoff<Int>(limits: MonitoringPipelineLimits(pendingScans: 1))
        let size = MonitoringPayloadSize(observations: 1, textBytes: 0)
        try handoff.send(1, size: size, sequence: 1)
        handoff.finish(throwing: Stopped.acquisition, offering: (2, size, 2))
        #expect(try await handoff.next() == 1)
        await #expect(throws: Stopped.acquisition) { try await handoff.next() }
    }

    @Test func failedAcquisitionDeliversTheDrainedUnitBeforeItsError() async throws {
        let handoff = AcquisitionHandoff<Int>(limits: MonitoringPipelineLimits(pendingScans: 1))
        handoff.finish(throwing: Stopped.acquisition, offering: (2, .init(observations: 1, textBytes: 0), 2))
        #expect(try await handoff.next() == 2)
        await #expect(throws: Stopped.acquisition) { try await handoff.next() }
    }

    @Test func ringReleasesConsumedCapacity() async throws {
        let handoff = AcquisitionHandoff<Int>(
            limits: MonitoringPipelineLimits(pendingScans: 2, pendingObservations: 2, pendingTextBytes: 2))
        for i in 0..<100 {
            try handoff.send(i, size: .init(observations: 1, textBytes: 1), sequence: UInt64(i))
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

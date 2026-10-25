import Testing

@testable import AgentMonitorCore

@Test func argumentProfileSeparatesCompleteReadsFromFallbacksAndFailures() {
    let profile = PipelineProfile()
    let bytes = argumentBuffer(environment: [])
    _ = NativeProcessArguments.read(maximumBytes: 131_072, profile: profile) { buffer in
        guard let buffer else { return bytes.count }
        bytes.withUnsafeBytes { buffer.copyMemory(from: $0) }
        return bytes.count
    }
    _ = NativeProcessArguments.read(maximumBytes: 131_072, profile: profile) { buffer in
        buffer?.count ?? 200_000
    }
    _ = NativeProcessArguments.read(maximumBytes: 131_072, profile: profile) { _ in 4 }
    #expect(profile.snapshot().counters["argumentShortReads"] == 1)
    #expect(profile.snapshot().counters["argumentReadFallbacks"] == 1)
}

@Test func handoffProfileMeasuresAcceptedOccupancyAndRemainingHeadroom() async throws {
    let profile = PipelineProfile()
    let handoff = AcquisitionHandoff<Int>(
        limits: MonitoringPipelineLimits(pendingScans: 3, pendingObservations: 10, pendingTextBytes: 20),
        profile: profile)
    let empty = try #require(profile.snapshot().handoff)
    #expect(empty.maximumQueuedUnits == 0)
    #expect(empty.minimumFreeUnits == 3)
    #expect(empty.minimumFreeRecords == 10)
    #expect(empty.minimumFreeTextBytes == 20)
    try handoff.send(1, size: .init(observations: 3, textBytes: 4), sequence: 1)
    try handoff.send(2, size: .init(observations: 2, textBytes: 3), sequence: 2)
    #expect(try await handoff.next() == 1)
    try handoff.send(3, size: .init(observations: 4, textBytes: 6), sequence: 3)
    #expect(throws: MonitoringError.overloaded(stage: .publication, rejectedScan: 4)) {
        try handoff.send(4, size: .init(observations: 5, textBytes: 1), sequence: 4)
    }
    let result = try #require(profile.snapshot().handoff)
    #expect(result.maximumQueuedUnits == 2)
    #expect(result.maximumQueuedRecords == 6)
    #expect(result.maximumQueuedTextBytes == 9)
    #expect(result.minimumFreeUnits == 1)
    #expect(result.minimumFreeRecords == 4)
    #expect(result.minimumFreeTextBytes == 11)
    #expect(try await handoff.next() == 2)
    #expect(try await handoff.next() == 3)
    handoff.finish()
}

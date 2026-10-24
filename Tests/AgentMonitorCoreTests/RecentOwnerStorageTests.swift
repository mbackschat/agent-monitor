import Testing

@testable import AgentMonitorCore

@Test func repeatedRecentOwnerContextUsesSharedStorageAndOneCharge() throws {
    var ledger = CounterLedger()
    var window = AccountingWindow(baseline: ledger.ingest([], listedAt: 0))
    let samples = (1...100).map { sample(Int32($0), at: 1, cpu: 1) }
    let rows = samples.map { sample in
        HeavyProcess(
            process: sample.identity, executable: sample.executable, name: sample.name,
            cpuPercent: nil, footprintBytes: sample.footprintBytes,
            cwd: nil, command: nil, metadataStatus: .markerRead,
            attribution: Attribution(
                provider: .codex, evidence: .ambiguous, context: .unverified,
                threadID: nil, rootSessionID: nil, runtime: nil, terminal: nil,
                runtimeDirectory: nil, candidateThreadIDs: (1...100).map { "candidate-\($0)" }, ancestry: []))
    }
    try window.append(ledger.ingest(samples, listedAt: 1), rows: rows)
    let unit = window.seal(scope: .agentsOnly)
    #expect(unit.records.count == 100)
    #expect(unit.size.observations <= 205)
    let buffers = Set(
        unit.records.map { record in
            record.category.owner.candidates.withUnsafeBufferPointer { Int(bitPattern: $0.baseAddress) }
        })
    #expect(buffers.count == 1)
}

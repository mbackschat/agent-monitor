import Testing

@testable import AgentMonitorCore

@Test func categoryReuseKeepsRuntimeRoleChangesSeparate() throws {
    var ledger = CounterLedger()
    var monitor = Monitor()
    var process = sample(42, at: 0, cpu: 0)
    var window = AccountingWindow(baseline: ledger.ingest([process], listedAt: 0))
    for tick in 1...2 {
        process.sampledAt = Double(tick)
        process.cpuSeconds = Double(tick)
        let scan = ledger.ingest([process], listedAt: Double(tick))
        monitor.ingest([process])
        try window.append(
            scan, rows: monitor.accountingFindings(), runtimes: tick == 1 ? [] : [process.identity])
    }
    let records = window.seal(scope: .allProcesses).records
    #expect(records.count == 2)
    #expect(Set(records.map { $0.category.isAgentRuntime }) == [false, true])
    #expect(records.allSatisfy { $0.cpuSeconds == 1 && $0.measuredIntervals == 1 })
    #expect(Set(records.map { $0.category.owner }).count == 1)
    #expect(Set(records.map { $0.category.executable }).count == 1)
    #expect(window.payloadSize == window.recountedPayloadSize)
}

@Test(arguments: [80, 10_000])
func incrementalPayloadMatchesRetainedStorageThroughUpdatesMergesAndCollapse(limit: Int) throws {
    var ledger = CounterLedger()
    var monitor = Monitor()
    var baseline = ledger.ingest([], listedAt: 0)
    var enclosing = AccountingWindow(baseline: baseline)
    var expectedCPU = 0.0
    for unit in 0..<8 {
        var window = AccountingWindow(baseline: baseline)
        for step in 1...10 {
            let tick = unit * 10 + step
            let samples = (1...8).map { index in
                sample(
                    Int32(index <= 4 ? index : unit * 10 + index), at: Double(tick),
                    cpu: index == 1 && (4...14).contains(tick) ? nil : Double(tick),
                    memory: UInt64(100 + tick))
            }
            let scan = ledger.ingest(samples, listedAt: Double(tick))
            expectedCPU += scan.contributions.reduce(0) { $0 + $1.cpuSeconds }
            monitor.ingest(samples, listedAt: Double(tick))
            for value in samples {
                monitor.enrich(
                    ProcessMetadata(
                        markers: [
                            SessionMarker(threadID: tick % 3 == 0 ? sessionB : sessionA, provider: .codex)
                        ],
                        cwd: tick % 2 == 0 ? "/project" : nil,
                        command: tick % 4 == 0 ? [String(repeating: "x", count: tick * 10), "arg"] : nil),
                    for: value.identity)
            }
            try window.append(scan, rows: monitor.accountingFindings())
            #expect(window.payloadSize == window.recountedPayloadSize)
            baseline = scan
        }
        try enclosing.merge(window)
        #expect(enclosing.payloadSize == enclosing.recountedPayloadSize)
        enclosing.compact(to: MonitoringPipelineLimits(pendingObservations: limit))
        #expect(enclosing.payloadSize == enclosing.recountedPayloadSize)
        #expect(enclosing.payloadSize.observations >= 0 && enclosing.payloadSize.textBytes >= 0)
    }
    let summary = enclosing.summary
    let actual =
        summary.contributions.reduce(0) { $0 + $1.cpuSeconds }
        + summary.collapsedContributions.reduce(0) { $0 + $1.cpuSeconds }
    #expect(actual == expectedCPU)
    if limit == 80 { #expect(!summary.collapsedContributions.isEmpty) }
}

@Test func incrementalTextChargeUsesBytesRatherThanUnicodeEquivalence() throws {
    var ledger = CounterLedger()
    var monitor = Monitor()
    let initial = sample(42, at: 0)
    var window = AccountingWindow(baseline: ledger.ingest([initial], listedAt: 0))
    let texts = ["é", "e\u{301}"]
    #expect(texts[0] == texts[1])
    #expect(texts[0].utf8.count != texts[1].utf8.count)
    var sizes: [Int] = []
    for (index, text) in texts.enumerated() {
        var value = sample(42, at: Double(index + 1), cpu: Double(index + 1))
        value.name = text
        let scan = ledger.ingest([value], listedAt: value.sampledAt)
        monitor.ingest([value])
        monitor.enrich(ProcessMetadata(cwd: text, command: [text]), for: value.identity)
        try window.append(scan, rows: monitor.accountingFindings())
        #expect(window.payloadSize == window.recountedPayloadSize)
        sizes.append(window.payloadSize.textBytes)
    }
    // Canonically equal directories share one frozen category, which retains the first spelling;
    // only the observation and run name/command charges grow by the extra UTF-8 byte.
    #expect(sizes[1] == sizes[0] + 5)
}

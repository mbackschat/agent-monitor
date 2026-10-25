import Testing

@testable import AgentMonitorCore

@Suite struct RecentLeaseBoundsTests {
    @Test func exhaustedSnapshotsDoNotAccumulateEmptyLeaseBookkeeping() throws {
        let store = RecentActivityStore(limits: RecentActivityLimits(records: 1, textBytes: 1))
        store.append(try unit())
        let snapshots = try (0..<200).map { _ in try #require(store.snapshot()) }
        #expect(snapshots.allSatisfy { $0.units.isEmpty && $0.retentionLimited })
        #expect(store.diagnostics.leases == 0)
        #expect(store.diagnostics.chargedRecords <= 1)
    }

    @Test func sharedBackingDoesNotMakeLeaseHeadersFree() throws {
        let store = RecentActivityStore(limits: RecentActivityLimits(records: 64, textBytes: 100_000))
        store.append(try unit(), current: [], present: [])
        var snapshots = try (0..<200).map { _ in try #require(store.snapshot()) }
        #expect(snapshots.first?.cpuSeconds == 1)
        #expect(snapshots.last?.retentionLimited == true)
        #expect(store.diagnostics.leases <= 64)
        #expect(store.diagnostics.chargedRecords <= 64)
        snapshots.removeAll()
        #expect(store.diagnostics.leases == 0)
    }

    private func unit() throws -> RecentActivityUnit {
        var ledger = CounterLedger()
        let baseline = ledger.ingest([sample(42, at: 0, cpu: 0)], listedAt: 0)
        var window = AccountingWindow(baseline: baseline)
        let value = sample(42, at: 1, cpu: 1)
        try window.append(
            ledger.ingest([value], listedAt: 1), rows: [recentRow(value, session: sessionA)])
        return window.seal(scope: .agentsOnly)
    }
}

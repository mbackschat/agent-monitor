import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct RecentMembershipTests {
    @Test(arguments: [ProcessScope.agentsOnly, .allProcesses])
    func membershipWorkDoesNotGrowWithRetainedHistory(scope: ProcessScope) throws {
        let store = RecentActivityStore()
        var ledger = CounterLedger()
        var baseline = ledger.ingest([], listedAt: 0)
        for tick in 1...120 {
            let values = (1...100).map { sample(Int32($0), at: Double(tick), cpu: Double(tick)) }
            let scan = ledger.ingest(values, listedAt: Double(tick))
            var window = AccountingWindow(baseline: baseline)
            try window.append(scan, rows: values.map { recentRow($0, session: sessionA) })
            store.append(window.seal(scope: scope), current: window.current, present: window.present)
            #expect(store.membershipMatchesRetainedRecords)
            baseline = scan
        }
        let snapshot = try #require(store.snapshot())
        #expect(snapshot.current.count == 100)
        #expect(snapshot.duration == 60)
        #expect(store.membershipRecordVisitCount <= 24_000)
    }

    @Test func historicalMembershipExpiresWithoutKeepingStaleCurrentMemory() throws {
        let store = RecentActivityStore(limits: RecentActivityLimits(seconds: 2))
        var ledger = CounterLedger()
        var baseline = ledger.ingest([], listedAt: 0)
        for tick in 1...4 {
            var value = sample(42, at: Double(tick), cpu: Double(tick))
            value.footprintBytes = UInt64(tick * 100)
            let scan = ledger.ingest([value], listedAt: Double(tick))
            var window = AccountingWindow(baseline: baseline)
            try window.append(scan, rows: [recentRow(value, session: tick == 1 ? sessionA : nil)])
            store.append(window.seal(scope: .agentsOnly), current: window.current, present: window.present)
            let snapshot = try #require(store.snapshot())
            #expect(store.membershipMatchesRetainedRecords)
            if tick <= 2 {
                #expect(snapshot.current.count == 1)
                #expect(snapshot.current.first?.latestFootprint == UInt64(tick * 100))
            } else {
                #expect(snapshot.current.isEmpty)
            }
            baseline = scan
        }
    }

    @Test func membershipMatchesRecountThroughPressureGapsAndScopeChanges() throws {
        let store = RecentActivityStore(
            limits: RecentActivityLimits(seconds: 4, records: 90, textBytes: 4096))
        var held: RecentActivitySnapshot?
        for run in 0..<2 {
            var ledger = CounterLedger()
            var baseline = ledger.ingest([], listedAt: 0)
            for tick in 1...40 {
                let values = (1...12).map { sample(Int32($0), at: Double(tick), cpu: Double(tick)) }
                let scan = ledger.ingest(values, listedAt: Double(tick))
                var window = AccountingWindow(baseline: baseline)
                try window.append(
                    scan, rows: values.map { recentRow($0, session: tick % 3 == 0 ? nil : sessionA) })
                if tick != 12 {
                    let scope: ProcessScope = tick < 20 ? .agentsOnly : .allProcesses
                    let unit = window.seal(scope: scope)
                    store.append(unit, current: window.current, present: window.present)
                    #expect(store.membershipMatchesRetainedRecords)
                    let snapshot = try #require(store.snapshot())
                    #expect(store.membershipMatchesRetainedRecords)
                    if tick == 8 { held = snapshot }
                    if tick == 16 { held = nil }
                    _ = snapshot.displaying(unit)
                    #expect(store.membershipMatchesRetainedRecords)
                    #expect(store.retainedPayloadSize.observations <= 90)
                }
                baseline = scan
            }
            #expect(held == nil, "Run \(run) releases its paused projection")
        }
    }
}

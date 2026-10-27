import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct SamplingAttributionTests {
    private func eligibility(_ monitor: inout Monitor, _ samples: [ProcessSample], excluded: Set<Int32> = [])
        -> [Int32: Bool]
    {
        let raw = ProcessSnapshot(
            samples: samples, enumeratedCount: samples.count, unreadableCount: 0,
            listedAt: samples.first?.sampledAt ?? 0, scanSeconds: 0, hostCounters: nil, logicalCPUCount: 8,
            listedPIDs: samples.map(\.identity.pid) + Array(excluded))
        let rows = monitor.accountingFindings()
        return Dictionary(
            uniqueKeysWithValues: monitor.samplingObservations(
                raw, rows: rows, collectorPID: 999,
                excluding: excluded
            ).map { ($0.pid, $0.eligible) })
    }

    @Test func ownNegativeSurvivesUnavailableRefreshButNotMalformedResolutionOrExec() {
        var monitor = Monitor()
        var worker = sample(10, at: 0)
        monitor.ingest([worker])
        #expect(eligibility(&monitor, [worker])[10] == true)
        monitor.enrich(ProcessMetadata(), for: worker.identity, observedAt: 0)
        #expect(eligibility(&monitor, [worker])[10] == false)
        monitor.enrich(ProcessMetadata(status: .unavailable), for: worker.identity, observedAt: 1)
        #expect(eligibility(&monitor, [worker])[10] == false)
        monitor.enrich(ProcessMetadata(status: .malformed), for: worker.identity, observedAt: 2)
        #expect(eligibility(&monitor, [worker])[10] == true)
        monitor.enrich(ProcessMetadata(status: .unavailable), for: worker.identity, observedAt: 3)
        #expect(eligibility(&monitor, [worker])[10] == true)
        monitor.enrich(ProcessMetadata(), for: worker.identity, observedAt: 4)
        #expect(eligibility(&monitor, [worker])[10] == false)
        worker.executable = "/fixture/changed"
        worker.sampledAt = 5
        monitor.ingest([worker])
        #expect(eligibility(&monitor, [worker])[10] == true)
    }

    @Test func negativeParentCannotExcludeAnUnresolvedOrAgentChild() {
        var monitor = Monitor()
        let parent = sample(10, start: 1)
        let child = sample(20, parent: 10, start: 2)
        monitor.ingest([parent, child])
        monitor.enrich(ProcessMetadata(), for: parent.identity, observedAt: 0)
        #expect(eligibility(&monitor, [parent, child])[20] == true)
        monitor.enrich(
            ProcessMetadata(
                markers: [SessionMarker(threadID: sessionA, provider: .codex)], status: .markerRead),
            for: child.identity, observedAt: 1)
        #expect(eligibility(&monitor, [parent, child])[20] == true)
        #expect(monitor.finding(for: child.identity)?.attribution.threadID == sessionA)
    }

    @Test func helperAncestrySurvivesDepartureButNotReusedIdentity() {
        var monitor = Monitor()
        let helper = sample(10, parent: 999, start: 1)
        var child = sample(20, parent: 10, start: 2)
        monitor.ingest([helper, child])
        #expect(eligibility(&monitor, [helper, child]).values.allSatisfy { !$0 })
        child.parentPID = 1
        child.sampledAt = 2
        monitor.ingest([child])
        #expect(eligibility(&monitor, [child])[20] == false)
        let replacement = sample(20, parent: 1, start: 3, at: 3)
        monitor.ingest([replacement])
        #expect(eligibility(&monitor, [replacement])[20] == true)
        #expect(eligibility(&monitor, [replacement], excluded: [42])[42] == false)
    }

    @Test func productionControllerMatchesTheIndependentReference() {
        var production = AdaptiveSamplingController(maximum: 0.625)
        var reference = AdaptiveSamplingPrototype(maximum: 0.625)
        for tick in 1...1_300 {
            let time = Double(tick) / 10
            let cpu = tick.isMultiple(of: 97) ? 0.05 : 0.0002
            let event = tick.isMultiple(of: 113)
            let held = (700...710).contains(tick)
            let actual = production.observe(
                .init(
                    opening: time - 0.1, closing: time, cpu: cpu,
                    youngCPU: tick < 600 ? cpu : 0, arrivals: event ? 1 : 0, event: event), uncertain: held)
            let expected = reference.observe(
                .init(
                    opening: time - 0.1, closing: time, cpu: cpu,
                    youngCPU: tick < 600 ? cpu : 0, arrivals: event ? 1 : 0, event: event), uncertain: held)
            #expect(abs(actual.requested - expected.requested) < 1e-12)
            #expect(abs(actual.rolling.cpu - expected.rolling.cpu) < 1e-12)
            #expect(Set(actual.reasons.map(\.rawValue)) == Set(expected.reasons.map(\.rawValue)))
        }
    }
}

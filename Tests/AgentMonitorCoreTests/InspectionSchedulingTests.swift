import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

private final class InspectionReaderFixture: InspectionReading, Sendable {
    struct State {
        var calls: [Int32] = []
        var listings = 0
        var now = 0.05
    }
    let state = Mutex(State())
    let delay: Double
    let fails: Bool
    init(delay: Double = 0, fails: Bool = false) {
        self.delay = delay
        self.fails = fails
    }
    var pids: [Int32] { (1...40).map(Int32.init) }
    func inspectionPIDs(allowance: InspectionAllowance) throws -> [Int32] {
        state.withLock {
            $0.listings += 1
            $0.now += delay
        }
        if fails { throw CancellationError() }
        return pids
    }
    func inspectionRead(_ pid: Int32, allowance: InspectionAllowance) -> InspectionRead? {
        guard allowance.permitsOperation() else { return nil }
        state.withLock { $0.calls.append(pid) }
        return InspectionRead(sample: inspectionReading(pid: pid).sample, parent: nil, cwd: nil)
    }
}

@Suite struct InspectionSchedulingTests {
    @Test func capsAndRotatesDiscoveryWithoutReadingCensusMembers() throws {
        let reader = InspectionReaderFixture()
        var scheduler = InspectionScheduler()
        let live = LiveInspection(active: true)
        let monitor = Monitor()
        for _ in 0..<2 {
            scheduler.prepare(census: inspectionCensus([], listed: [1, 2]), inspection: live)
            try scheduler.observe(
                reader: reader, monitor: monitor, since: 0, nextDeadline: 0.1,
                now: { 0.05 }, cancelled: { false }, inspection: live, excluding: [])
        }
        let calls = reader.state.withLock { $0.calls }
        #expect(calls.count == 2 * InspectionLimits.maximumReads)
        #expect(Set(calls).count == calls.count)
        #expect(!calls.contains(1) && !calls.contains(2))
        #expect(scheduler.buffer.count <= InspectionLimits.maximumHeldReadings)
        #expect(scheduler.buffer.coverage.candidatesLeftUnread > 0)
    }

    @Test func lateOpportunitySkipsWithoutNativeWork() throws {
        let reader = InspectionReaderFixture()
        var scheduler = InspectionScheduler()
        let live = LiveInspection(active: true)
        scheduler.prepare(census: inspectionCensus([], listed: []), inspection: live)
        try scheduler.observe(
            reader: reader, monitor: Monitor(), since: 0, nextDeadline: 0.1,
            now: { 0.07 }, cancelled: { false }, inspection: live, excluding: [])
        #expect(reader.state.withLock { $0.listings } == 0)
        #expect(scheduler.buffer.coverage.opportunitiesSkipped == 1)
    }

    @Test func pauseAndResumeDiscardsHeldEvidenceEvenBeforeNextCensus() throws {
        let reader = InspectionReaderFixture()
        var scheduler = InspectionScheduler()
        let live = LiveInspection(active: true)
        scheduler.prepare(census: inspectionCensus([], listed: []), inspection: live)
        try scheduler.observe(
            reader: reader, monitor: Monitor(), since: 0, nextDeadline: 0.1,
            now: { 0.05 }, cancelled: { false }, inspection: live, excluding: [])
        live.set(false)
        live.set(true)
        let carried = scheduler.admit(at: inspectionCensus([], listed: []), inspection: live)
        #expect(carried.isEmpty)
        #expect(scheduler.buffer.coverage.discardedReadings == InspectionLimits.maximumHeldReadings)
    }
}

extension InspectionSchedulingTests {
    @Test(arguments: [false, true]) func enumerationOverrunIsVisibleEvenWithoutCandidates(fails: Bool) throws
    {
        let reader = InspectionReaderFixture(delay: 0.1, fails: fails)
        var scheduler = InspectionScheduler()
        let live = LiveInspection(active: true)
        scheduler.prepare(census: inspectionCensus([], listed: reader.pids), inspection: live)
        try scheduler.observe(
            reader: reader, monitor: Monitor(), since: 0, nextDeadline: 0.1,
            now: { reader.state.withLock { $0.now } }, cancelled: { false }, inspection: live, excluding: [])
        #expect(abs(scheduler.buffer.coverage.maximumCompleteScanLateness - 0.05) < 1e-9)
    }

    @Test func enabledThenPausedBeforeTheOpportunityStillMarksMixedCoverage() {
        let live = LiveInspection(active: true)
        var scheduler = InspectionScheduler()
        scheduler.prepare(census: inspectionCensus([], listed: []), inspection: live)
        live.set(false)
        let coverage = scheduler.takeCoverage(inspection: live)
        #expect(coverage.mode == .mixed)
    }
}

extension InspectionSchedulingTests {
    @Test func terminalDiscardNeedsNoSyntheticScan() {
        let live = LiveInspection(active: true)
        var scheduler = InspectionScheduler()
        scheduler.prepare(census: inspectionCensus([], listed: []), inspection: live)
        _ = scheduler.buffer.retain(inspectionReading())
        let final = scheduler.finish(live)
        #expect(final.discardedReadings == 1)
        #expect(live.terminalCoverage == final)
        #expect(scheduler.buffer.count == 0)
    }

    @Test func briefActivationBetweenCompleteScansIsNotReportedDisabled() {
        let live = LiveInspection()
        var scheduler = InspectionScheduler()
        scheduler.prepare(census: inspectionCensus([], listed: []), inspection: live)
        live.set(true)
        live.set(false)
        let coverage = scheduler.takeCoverage(inspection: live)
        #expect(coverage.mode == .mixed)
    }
}

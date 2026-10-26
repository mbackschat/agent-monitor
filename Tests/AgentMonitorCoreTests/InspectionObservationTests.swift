import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct InspectionObservationTests {
    @Test(arguments: [
        NativeCounterStatus.permissionDenied, .lookupUnavailable, .shortRead,
        .identityMismatch, .outOfScopeUser, .otherFailure,
    ])
    func admissionDistinguishesDisappearanceFromFailedReads(status: NativeCounterStatus) throws {
        var held = InspectionBuffer()
        let reading = inspectionReading()
        let retained = held.retain(reading)
        #expect(retained)
        let census = inspectionCensus(
            [], listed: [reading.sample.identity.pid],
            outcomes: [
                NativeCounterOutcome(
                    pid: reading.sample.identity.pid, identity: nil, operation: .bsdInfo,
                    status: status, failure: nil, observedAtTicks: 100)
            ])
        let result = held.admit(at: census)
        #expect(result.count == (status == .lookupUnavailable ? 1 : 0))
        #expect(held.coverage.carriedObservations == result.count)
        #expect(held.coverage.droppedReadings == (result.isEmpty ? 1 : 0))
        #expect(held.count == 0)
    }

    @Test func completeSuccessSupersedesHeldCPUAndFootprint() throws {
        var held = InspectionBuffer()
        let reading = inspectionReading()
        let retained = held.retain(reading)
        #expect(retained)
        var current = reading.sample
        current.sampledAt = 0.1
        current.cpuSeconds = 0.04
        current.footprintBytes = 2
        let noCarriedReading = held.admit(at: inspectionCensus([current], listed: [current.identity.pid]))
            .isEmpty
        #expect(noCarriedReading)
        #expect(held.coverage.supersededReadings == 1)
    }

    @Test func failedResourceReadDoesNotTurnAReadableIdentityIntoDisappearance() {
        var held = InspectionBuffer()
        let reading = inspectionReading()
        let retained = held.retain(reading)
        #expect(retained)
        var current = reading.sample
        current.cpuSeconds = nil
        let result = held.admit(
            at: inspectionCensus(
                [current], listed: [current.identity.pid],
                outcomes: [
                    NativeCounterOutcome(
                        pid: current.identity.pid, identity: current.identity,
                        operation: .resourceUsage, status: .lookupUnavailable, failure: nil,
                        observedAtTicks: 100)
                ]))
        #expect(result.isEmpty)
        #expect(held.coverage.droppedReadings == 1)
    }

    @Test func mismatchNeedsAProvenReplacementIdentity() {
        let reading = inspectionReading()
        for verified in [nil, reading.sample.identity, ProcessIdentity(pid: 42, startMicroseconds: 3)] {
            var held = InspectionBuffer()
            let retained = held.retain(reading)
            #expect(retained)
            let result = held.admit(
                at: inspectionCensus(
                    [], listed: [42],
                    outcomes: [
                        NativeCounterOutcome(
                            pid: 42, identity: nil, operation: .identityVerification,
                            status: .identityMismatch, failure: nil, observedAtTicks: 100,
                            verifiedIdentity: verified)
                    ]))
            #expect(result.count == (verified?.startMicroseconds == 3 ? 1 : 0))
        }
    }

    @Test func heldCapacityRefusesNewEvidenceWithoutEvictingAcceptedReadings() {
        var held = InspectionBuffer()
        for index in 0..<InspectionLimits.maximumHeldReadings {
            let retained = held.retain(inspectionReading(pid: Int32(42 + index)))
            #expect(retained)
        }
        let overflowRejected = !held.retain(inspectionReading(pid: 1000))
        #expect(overflowRejected)
        #expect(held.count == InspectionLimits.maximumHeldReadings)
        let accepted =
            held.admit(at: inspectionCensus([], listed: [])).count == InspectionLimits.maximumHeldReadings
        #expect(accepted)
        var oversized = InspectionBuffer()
        let oversizedRejected = !oversized.retain(
            inspectionReading(name: String(repeating: "x", count: InspectionLimits.maximumHeldTextBytes + 1)))
        #expect(oversizedRejected)
        #expect(oversized.count == 0)
    }
}

func inspectionReading(pid: Int32 = 42, name: String = "worker") -> HeldInspectionObservation {
    var sample = ProcessSample(
        identity: ProcessIdentity(pid: pid, startMicroseconds: 2), parentPID: 1,
        executable: "/bin/" + name, name: name, sampledAt: 0.05, cpuSeconds: 0.02, footprintBytes: 100)
    sample.startedAt = 0.02
    sample.startedAtTicks = 20
    sample.sampledAtTicks = 50
    let row = HeavyProcess(
        process: sample.identity, executable: sample.executable, name: name,
        cpuPercent: nil, footprintBytes: sample.footprintBytes, cwd: "/work", command: nil,
        metadataStatus: .unavailable,
        attribution: Attribution(
            provider: nil, evidence: .unknown, context: .unverified,
            threadID: nil, rootSessionID: nil, runtime: nil, terminal: nil, runtimeDirectory: nil,
            candidateThreadIDs: [], ancestry: [sample.identity]))
    return HeldInspectionObservation(
        sample: sample, row: row, evidenceAt: nil,
        isAgentRuntime: false, corroboratedRoot: nil)
}

func inspectionCensus(_ samples: [ProcessSample], listed: [Int32], outcomes: [NativeCounterOutcome] = [])
    -> ProcessSnapshot
{
    ProcessSnapshot(
        samples: samples, enumeratedCount: listed.count, unreadableCount: outcomes.count,
        listedAt: 0.1, scanSeconds: 0, hostCounters: nil, logicalCPUCount: 8,
        nativeOutcomes: outcomes, listedPIDs: listed)
}

extension InspectionObservationTests {
    @Test func ancestryContextAndNativeOperationsShareFixedBounds() {
        let reading = inspectionReading()
        let owner = Attribution(
            provider: nil, evidence: .unknown, context: .unverified,
            threadID: nil, rootSessionID: nil, runtime: nil, terminal: nil, runtimeDirectory: nil,
            candidateThreadIDs: [],
            ancestry: (0...InspectionLimits.maximumHeldRecords).map {
                ProcessIdentity(pid: Int32($0), startMicroseconds: UInt64($0))
            })
        let large = HeldInspectionObservation(
            sample: reading.sample,
            row: reading.row.usingAttribution(owner), evidenceAt: nil,
            isAgentRuntime: false, corroboratedRoot: nil)
        var buffer = InspectionBuffer()
        let retained = buffer.retain(large)
        #expect(!retained)
        #expect(buffer.count == 0)
        let allowance = InspectionAllowance(deadline: 1, now: { 0 }, cancelled: { false })
        for _ in 0..<InspectionLimits.maximumNativeOperations { #expect(allowance.permitsOperation()) }
        #expect(!allowance.permitsOperation())
    }
}

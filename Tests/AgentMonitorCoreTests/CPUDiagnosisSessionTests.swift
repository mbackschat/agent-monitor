import Foundation
import Synchronization
import Testing

@testable import AgentMonitorCore

final class DiagnosisFixture: DiagnosisReading, SamplingClock, SessionRegistryReading, Sendable {
    struct State {
        var scans = 0
        var waits: [Double] = []
        var metadata: [ProcessIdentity] = []
        var lookups = 0
        var exclusions: [Set<Int32>] = []
    }
    let state = Mutex(State())
    let snapshots: [ProcessSnapshot]
    let metadata: [ProcessIdentity: DiagnosisObservation]
    let missing: Set<ProcessIdentity>
    let failingScan: Int?
    let registryOutput: Data?

    init(
        _ snapshots: [ProcessSnapshot], metadata: [ProcessIdentity: DiagnosisObservation] = [:],
        missing: Set<ProcessIdentity> = [], failingScan: Int? = nil,
        registryOutput: Data? = Data("[]".utf8)
    ) {
        self.snapshots = snapshots
        self.metadata = metadata
        self.missing = missing
        self.failingScan = failingScan
        self.registryOutput = registryOutput
    }

    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot {
        let index = state.withLock {
            $0.exclusions.append(excluding)
            defer { $0.scans += 1 }
            return $0.scans
        }
        if index == failingScan { throw NativeReadError.enumeration(1) }
        return snapshots[index]
    }
    func observation(for sample: ProcessSample) -> DiagnosisObservation {
        state.withLock { $0.metadata.append(sample.identity) }
        #expect(state.withLock { $0.scans } == 4)
        return metadata[sample.identity] ?? .observed(ProcessMetadata())
    }
    func isCurrent(_ sample: ProcessSample) -> Bool { !missing.contains(sample.identity) }
    func wait(seconds: Double) async throws { state.withLock { $0.waits.append(seconds) } }
    func now() -> Date { Date(timeIntervalSince1970: Double(state.withLock { $0.scans }) * 100) }
    func output(of query: SessionRegistryQuery) throws -> Data {
        state.withLock { $0.lookups += 1 }
        #expect(query.command == ["claude", "agents", "--json"])
        guard let registryOutput else { throw BoundedCommandFailure("private provider error") }
        return registryOutput
    }
}

@Suite struct CPUDiagnosisSessionTests {
    private let runtimePath = "/Users/test/.local/share/claude/versions/2.1.301"

    private func scans(_ processes: (Int) -> [ProcessSample]) -> [ProcessSnapshot] {
        (0...3).map { index in
            diagnosisScan(processes(index), at: 10 + Double(index) * 2, scan: 0.5)
        }
    }

    @Test func collectsFixedWindowWithIndependentClocksAndExactSessionEvidence() async throws {
        let values = scans { index in
            [
                sample(10, executable: runtimePath, at: 10.25 + Double(index) * 2, cpu: nil),
                sample(20, parent: 10, at: 10.1 + Double(index) * 2.1, cpu: Double(index)),
            ]
        }
        let output = Data("[{\"pid\":10,\"sessionId\":\"\(sessionA)\",\"status\":\"busy\"}]".utf8)
        let fake = DiagnosisFixture(values, registryOutput: output)
        let result = try await CPUDiagnosisSession(
            reader: fake, clock: fake, registry: fake, excluding: [999]
        ).run()
        #expect(result.elapsedSeconds == 6.5)
        #expect(result.endedAt.timeIntervalSince(result.startedAt) == 400)
        #expect(result.contributors.first?.cpuSeconds == 3)
        #expect(abs(try #require(result.contributors.first).observedSeconds - 6.3) < 1e-10)
        #expect(fake.state.withLock { $0.waits } == [1, 1, 1])
        #expect(fake.state.withLock { $0.exclusions } == Array(repeating: [999], count: 4))
        #expect(Set(fake.state.withLock { $0.metadata }) == Set(values[3].samples.map(\.identity)))
        #expect(fake.state.withLock { $0.lookups } == 1)
        #expect(result.providerLookups == [DiagnosisLookup(provider: .claude, status: .succeeded)])
        guard case .available(_, let attribution) = try #require(result.contributors.first).attribution else {
            Issue.record("Expected available attribution")
            return
        }
        #expect(attribution.threadID == sessionA)
        #expect(attribution.evidence == .sessionRegistry)
        #expect(attribution.runtime == values[3].samples[0].identity)
    }

    @Test(arguments: [0, 1, 2, 3]) func requiredScanFailureProducesNoResult(index: Int) async {
        let fake = DiagnosisFixture(scans { _ in [] }, failingScan: index)
        await #expect(throws: CPUDiagnosisError.collectionFailed) {
            try await CPUDiagnosisSession(reader: fake, clock: fake, registry: fake).run()
        }
        #expect(fake.state.withLock { $0.metadata.isEmpty && $0.lookups == 0 })
    }

    @Test func earlierLifetimeAndReuseNeverRequestOldMetadata() async throws {
        let values = scans { index in
            index < 2
                ? [sample(20, start: 1, at: 10 + Double(index) * 2, cpu: Double(index))]
                : [sample(20, start: 2, at: 10 + Double(index) * 2, cpu: nil)]
        }
        let fake = DiagnosisFixture(values)
        let result = try await CPUDiagnosisSession(reader: fake, clock: fake, registry: fake).run()
        #expect(result.contributors.first?.attribution == .unavailable(.notObservedAtEnrichment))
        #expect(fake.state.withLock { $0.metadata.isEmpty })
        #expect(result.contributors.first?.footprint?.sampledAt == Date(timeIntervalSince1970: 199.5))
    }

    @Test func observedButUnreadableMetadataDiffersFromDisappearance() async throws {
        let values = scans { index in
            [
                sample(1, at: 10 + Double(index) * 2, cpu: Double(index)),
                sample(2, at: 10 + Double(index) * 2, cpu: Double(index)),
            ]
        }
        let fake = DiagnosisFixture(
            values,
            metadata: [
                values[3].samples[0].identity: .observed(ProcessMetadata(status: .unavailable)),
                values[3].samples[1].identity: .notObserved,
            ])
        let result = try await CPUDiagnosisSession(reader: fake, clock: fake, registry: fake).run()
        #expect(
            result.contributors.map(\.attribution) == [
                .unavailable(.metadataUnavailable), .unavailable(.notObservedAtEnrichment),
            ])
    }

    @Test(arguments: [Data("invalid".utf8), nil]) func providerFailurePreservesCPUAndRecordsOneOutcome(
        output: Data?
    ) async throws {
        let values = scans { index in
            [sample(10, executable: runtimePath, at: 10 + Double(index) * 2, cpu: Double(index))]
        }
        let fake = DiagnosisFixture(values, registryOutput: output)
        let result = try await CPUDiagnosisSession(reader: fake, clock: fake, registry: fake).run()
        #expect(result.contributors.first?.cpuSeconds == 3)
        #expect(result.contributors.first?.attribution == .unavailable(.providerLookupFailed))
        #expect(result.providerLookups == [DiagnosisLookup(provider: .claude, status: .failed)])
        #expect(fake.state.withLock { $0.lookups } == 1)
    }

    @Test func vanishedRuntimeDoesNotTriggerARegistryLookup() async throws {
        let values = scans { index in
            [
                sample(10, executable: runtimePath, at: 10 + Double(index) * 2, cpu: nil),
                sample(20, parent: 10, at: 10 + Double(index) * 2, cpu: Double(index)),
            ]
        }
        let fake = DiagnosisFixture(values, metadata: [values[3].samples[0].identity: .notObserved])
        let result = try await CPUDiagnosisSession(reader: fake, clock: fake, registry: fake).run()
        #expect(result.providerLookups.isEmpty)
        #expect(fake.state.withLock { $0.lookups } == 0)
    }

    @Test func reusedRuntimeCannotSupplyALaterSessionToAnEarlierLifetime() async throws {
        let values = scans { index in
            [
                sample(10, executable: runtimePath, at: 10 + Double(index) * 2, cpu: nil),
                sample(20, parent: 10, at: 10 + Double(index) * 2, cpu: Double(index)),
            ]
        }
        let output = Data("[{\"pid\":10,\"sessionId\":\"\(sessionA)\",\"status\":\"busy\"}]".utf8)
        let fake = DiagnosisFixture(values, missing: [values[3].samples[0].identity], registryOutput: output)
        let result = try await CPUDiagnosisSession(reader: fake, clock: fake, registry: fake).run()
        guard case .available(_, let attribution) = try #require(result.contributors.first).attribution else {
            Issue.record("Expected observed unresolved evidence")
            return
        }
        #expect(attribution.evidence == .runtimeOnly)
        #expect(attribution.threadID == nil)
    }

    @Test func emptyAndUnavailableScansRemainValidPartialResults() async throws {
        for values in [scans { _ in [] }, scans { index in [sample(1, at: Double(index), cpu: nil)] }] {
            let fake = DiagnosisFixture(values)
            let result = try await CPUDiagnosisSession(reader: fake, clock: fake, registry: fake).run()
            #expect(result.cpuSeconds == nil)
            #expect(result.windowCPUPercent == nil)
            #expect(result.contributors.isEmpty)
            #expect(result.diagnostics.contains(.noMeasuredLifetimes))
            #expect(fake.state.withLock { $0.metadata.isEmpty && $0.lookups == 0 })
        }
    }

    @Test func topTenScopeDoesNotEnrichOrListOmittedRuntime() async throws {
        let values = scans { index in
            (1...11).map { pid in
                sample(
                    Int32(pid), executable: pid == 11 ? runtimePath : "/bin/worker",
                    at: 10 + Double(index) * 2, cpu: Double(index * (12 - pid)))
            }
        }
        let fake = DiagnosisFixture(values)
        let result = try await CPUDiagnosisSession(reader: fake, clock: fake, registry: fake).run()
        #expect(result.contributors.count == 10)
        #expect(result.omittedContributorCount == 1)
        #expect(fake.state.withLock { $0.metadata.map(\.pid).sorted() } == Array(1...10).map(Int32.init))
        #expect(fake.state.withLock { $0.lookups } == 0)
    }

    @Test func exactMarkersInSameDirectoryAndAmbiguousCandidatesRemainEvidence() async throws {
        let values = scans { index in
            [
                sample(1, at: 10 + Double(index) * 2, cpu: Double(index)),
                sample(2, at: 10 + Double(index) * 2, cpu: Double(index)),
                sample(3, executable: "/bin/codex", at: 10 + Double(index) * 2, cpu: Double(index)),
            ]
        }
        let fake = DiagnosisFixture(
            values,
            metadata: [
                values[3].samples[0].identity: .observed(
                    ProcessMetadata(
                        markers: [SessionMarker(threadID: sessionA, provider: .codex)], status: .markerRead,
                        cwd: "/same")),
                values[3].samples[1].identity: .observed(
                    ProcessMetadata(
                        markers: [SessionMarker(threadID: sessionB, provider: .codex)], status: .markerRead,
                        cwd: "/same")),
                values[3].samples[2].identity: .observed(
                    ProcessMetadata(writerThreadIDs: [sessionA, sessionB])),
            ])
        let result = try await CPUDiagnosisSession(reader: fake, clock: fake, registry: fake).run()
        let associations = result.contributors.compactMap { contributor -> Attribution? in
            guard case .available(_, let value) = contributor.attribution else { return nil }
            return value
        }
        #expect(associations.map(\.threadID) == [sessionA, sessionB, nil])
        #expect(associations.last?.candidateThreadIDs == [sessionA, sessionB])
        #expect(associations.last?.evidence == .ambiguous)
        #expect(result.providerLookups.isEmpty)
    }
}

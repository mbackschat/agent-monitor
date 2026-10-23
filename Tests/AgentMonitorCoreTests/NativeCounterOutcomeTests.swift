import Darwin
import Synchronization
import Testing

@testable import AgentMonitorCore

private final class CounterAccessFixture: NativeCounterAccess, Sendable {
    let initial: NativeCounterRead<proc_bsdinfo>
    let verification: NativeCounterRead<proc_bsdinfo>
    let usage: NativeCounterRead<rusage_info_v4>
    private let readInitial = Mutex(false)

    init(
        initial: NativeCounterRead<proc_bsdinfo>, verification: NativeCounterRead<proc_bsdinfo>? = nil,
        usage: NativeCounterRead<rusage_info_v4> = .failure(
            .init(returned: -1, expected: nil, errorNumber: EACCES))
    ) {
        self.initial = initial
        self.verification = verification ?? initial
        self.usage = usage
    }

    func bsdInfo(_ pid: Int32) -> NativeCounterRead<proc_bsdinfo> {
        readInitial.withLock { read in
            defer { read = true }
            return read ? verification : initial
        }
    }

    func resources(_ pid: Int32) -> NativeCounterRead<rusage_info_v4> { usage }
    func executablePath(_ pid: Int32) -> NativeCounterRead<String> { .value("/owned/fixture") }
}

@Suite struct NativeCounterOutcomeTests {
    private func info(uid: UInt32 = getuid(), start: UInt64 = 1) -> NativeCounterRead<proc_bsdinfo> {
        var info = proc_bsdinfo()
        info.pbi_pid = 42
        info.pbi_uid = uid
        info.pbi_start_tvsec = start
        return .value(info)
    }

    private func scan(_ access: CounterAccessFixture) throws -> ProcessSnapshot {
        try NativeProcessReader(adapters: .builtIn, counterAccess: access).snapshot(processIDs: { [42] })
    }

    @Test(arguments: [EACCES, ESRCH, EINVAL]) func failedIdentityReadRetainsNativeFailure(code: Int32) throws
    {
        let result = try scan(
            CounterAccessFixture(initial: .failure(.init(returned: 0, expected: 136, errorNumber: code))))
        #expect(result.samples.isEmpty)
        #expect(result.unreadableCount == 1)
        let failure = try #require(result.nativeOutcomes.first)
        #expect(failure.pid == 42)
        #expect(failure.identity == nil)
        #expect(failure.operation == .bsdInfo)
        #expect(failure.failure?.errorNumber == code)
        #expect(failure.failure?.returned == 0)
        switch code {
        case EACCES: #expect(failure.status == .permissionDenied)
        case ESRCH: #expect(failure.status == .lookupUnavailable)
        default: #expect(failure.status == .otherFailure)
        }
    }

    @Test func shortReadIsDistinctFromMissingProcess() throws {
        let result = try scan(
            CounterAccessFixture(initial: .failure(.init(returned: 32, expected: 136, errorNumber: nil))))
        #expect(result.nativeOutcomes.first?.status == .shortRead)
        #expect(result.nativeOutcomes.first?.failure?.expected == 136)
    }

    @Test func resourceFailurePreservesVerifiedIdentityAndUnavailableCounters() throws {
        let result = try scan(CounterAccessFixture(initial: info()))
        let process = try #require(result.samples.first)
        #expect(process.cpuSeconds == nil)
        #expect(process.footprintBytes == nil)
        #expect(process.rawCPU == nil)
        #expect(result.unreadableCount == 0)
        #expect(result.nativeOutcomes.first?.identity == process.identity)
        #expect(result.nativeOutcomes.first?.operation == .resourceUsage)
        #expect(result.nativeOutcomes.first?.status == .permissionDenied)
    }

    @Test func readableOtherUserIsNotAnUnreadableProcess() throws {
        let result = try scan(CounterAccessFixture(initial: info(uid: getuid() + 1)))
        #expect(result.samples.isEmpty)
        #expect(result.unreadableCount == 0)
        #expect(result.nativeOutcomes.first?.status == .outOfScopeUser)
    }

    @Test(arguments: [true, false]) func changedIdentityOrUserRejectsCounters(changeUID: Bool) throws {
        let after = changeUID ? info(uid: getuid() + 1) : info(start: 2)
        let result = try scan(CounterAccessFixture(initial: info(), verification: after))
        #expect(result.samples.isEmpty)
        #expect(result.unreadableCount == 1)
        #expect(result.nativeOutcomes.last?.operation == .identityVerification)
        #expect(result.nativeOutcomes.last?.status == .identityMismatch)
    }

    @Test func nativeScanPreservesRawCountersAndClockAnchors() throws {
        var usage = rusage_info_v4()
        usage.ri_user_time = (1 << 54) + 1
        usage.ri_system_time = 123
        usage.ri_phys_footprint = 456
        usage.ri_lifetime_max_phys_footprint = 789
        let result = try scan(CounterAccessFixture(initial: info(), usage: .value(usage)))
        let process = try #require(result.samples.first)
        #expect(process.rawCPU?.user == usage.ri_user_time)
        #expect(process.rawCPU?.system == 123)
        #expect(process.footprintBytes == 456)
        #expect(process.kernelPeakFootprintBytes == 789)
        #expect(result.nativeOutcomes.isEmpty)
        let timing = try #require(result.nativeTiming)
        #expect(timing.startedAbsolute <= timing.listingAbsolute)
        #expect(try #require(process.sampledAtTicks) >= timing.listingAbsolute)
        #expect(try #require(process.sampledAtTicks) <= timing.endedAbsolute)
        #expect(timing.denominator > 0)
        var monitor = Monitor()
        monitor.ingest(result)
        let accounting = try #require(monitor.counterScan)
        #expect(accounting.observations.first?.sample.rawCPU == process.rawCPU)
        #expect(accounting.observations.first?.id.scan == accounting.id)
        #expect(accounting.source?.hostCounters == result.hostCounters)
        #expect(accounting.nativeTiming?.listingAbsolute == timing.listingAbsolute)
    }

    @Test func failedVerificationRetainsEarlierFailuresWithoutClaimingIdentity() throws {
        let result = try scan(
            CounterAccessFixture(
                initial: info(), verification: .failure(.init(returned: 0, expected: 136, errorNumber: ESRCH))
            ))
        #expect(result.samples.isEmpty)
        #expect(result.nativeOutcomes.map(\.operation) == [.resourceUsage, .identityVerification])
        #expect(result.nativeOutcomes.map(\.status) == [.permissionDenied, .lookupUnavailable])
        #expect(result.nativeOutcomes.allSatisfy { $0.identity == nil })
    }
}

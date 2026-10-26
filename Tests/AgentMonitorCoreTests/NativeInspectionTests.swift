import Darwin
import Synchronization
import Testing

@testable import AgentMonitorCore

private final class InspectionAccess: NativeCounterAccess, Sendable {
    let calls = Mutex<[String]>([])
    func bsdInfo(_ pid: Int32) -> NativeCounterRead<proc_bsdinfo> {
        calls.withLock { $0.append("identity:\(pid)") }
        var info = proc_bsdinfo()
        info.pbi_pid = UInt32(pid)
        info.pbi_ppid = 1
        info.pbi_uid = getuid()
        info.pbi_start_tvsec = UInt64(pid)
        return .value(info)
    }
    func resources(_ pid: Int32) -> NativeCounterRead<rusage_info_v4> {
        calls.withLock { $0.append("resources") }
        var value = rusage_info_v4()
        value.ri_user_time = 100
        return .value(value)
    }
    func executablePath(_ pid: Int32) -> NativeCounterRead<String> {
        calls.withLock { $0.append("path") }
        return .value("/fake/worker")
    }
    func workingDirectory(_ pid: Int32) -> String? {
        calls.withLock { $0.append("cwd") }
        return "/fake/work"
    }
}

@Suite struct NativeInspectionTests {
    @Test func checksIdentityAndParentBeforeReadingAndVerifyingDirectory() throws {
        let access = InspectionAccess()
        let reader = try NativeProcessReader(adapters: .builtIn, counterAccess: access)
        let allowance = InspectionAllowance(deadline: 1, now: { 0 }, cancelled: { false })
        let result = try #require(reader.inspectionRead(42, allowance: allowance))
        #expect(result.parent == ProcessIdentity(pid: 1, startMicroseconds: 1_000_000))
        #expect(result.cwd == "/fake/work")
        #expect(
            access.calls.withLock { $0 } == [
                "identity:42", "path", "resources", "identity:42", "identity:1", "cwd", "identity:42", "path",
            ])
    }

    @Test func checksDeadlineBetweenIndividualNativeOperations() throws {
        let access = InspectionAccess()
        let reader = try NativeProcessReader(adapters: .builtIn, counterAccess: access)
        let allowance = InspectionAllowance(
            deadline: 2, now: { Double(access.calls.withLock { $0.count }) }, cancelled: { false })
        #expect(reader.inspectionRead(42, allowance: allowance) == nil)
        #expect(access.calls.withLock { $0 } == ["identity:42", "path"])
    }
}

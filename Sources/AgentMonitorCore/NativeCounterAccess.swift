import Darwin
import Foundation

public enum NativeCounterOperation: Sendable {
    case bsdInfo, executablePath, resourceUsage, identityVerification
}

public enum NativeCounterStatus: Sendable {
    case permissionDenied, lookupUnavailable, shortRead, identityMismatch, outOfScopeUser, otherFailure
}

public struct NativeCounterFailure: Equatable, Sendable {
    public let returned: Int32
    public let expected: Int32?
    public let errorNumber: Int32?

    var status: NativeCounterStatus {
        switch errorNumber {
        case EACCES, EPERM: .permissionDenied
        case ESRCH: .lookupUnavailable
        case .some: .otherFailure
        case .none:
            if let expected, returned >= 0, returned < expected { .shortRead } else { .otherFailure }
        }
    }
}

public struct NativeCounterOutcome: Sendable {
    public let pid: Int32
    public let identity: ProcessIdentity?
    public let operation: NativeCounterOperation
    public let status: NativeCounterStatus
    public let failure: NativeCounterFailure?
    public let observedAtTicks: UInt64
    public let verifiedIdentity: ProcessIdentity?

    public init(
        pid: Int32, identity: ProcessIdentity?, operation: NativeCounterOperation,
        status: NativeCounterStatus, failure: NativeCounterFailure?, observedAtTicks: UInt64,
        verifiedIdentity: ProcessIdentity? = nil
    ) {
        self.pid = pid
        self.identity = identity
        self.operation = operation
        self.status = status
        self.failure = failure
        self.observedAtTicks = observedAtTicks
        self.verifiedIdentity = verifiedIdentity
    }
}

/// Anchors are read in field order; they are not an atomic cross-clock sample.
public struct NativeScanTiming: Sendable {
    public let startedAbsolute: UInt64
    public let listingAbsolute: UInt64
    public let listingContinuous: UInt64
    public let listingWallTime: Date
    public let endedAbsolute: UInt64
    public let numerator: UInt32
    public let denominator: UInt32
}

enum NativeCounterRead<Value: Sendable>: Sendable {
    case value(Value)
    case failure(NativeCounterFailure)

    var value: Value? {
        switch self {
        case .value(let value): value
        case .failure: nil
        }
    }
}

protocol NativeCounterAccess: Sendable {
    func bsdInfo(_ pid: Int32) -> NativeCounterRead<proc_bsdinfo>
    func resources(_ pid: Int32) -> NativeCounterRead<rusage_info_v4>
    func executablePath(_ pid: Int32) -> NativeCounterRead<String>
    func workingDirectory(_ pid: Int32) -> String?
}

extension NativeCounterAccess {
    func workingDirectory(_ pid: Int32) -> String? { nil }
}

struct SystemNativeCounterAccess: NativeCounterAccess {
    func workingDirectory(_ pid: Int32) -> String? {
        var paths = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &paths, size) == size else { return nil }
        let path = withUnsafeBytes(of: paths.pvi_cdir.vip_path) {
            String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    func bsdInfo(_ pid: Int32) -> NativeCounterRead<proc_bsdinfo> {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        errno = 0
        let returned = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        let code = errno
        guard returned == size else {
            return .failure(.init(returned: returned, expected: size, errorNumber: code == 0 ? nil : code))
        }
        return .value(info)
    }

    func resources(_ pid: Int32) -> NativeCounterRead<rusage_info_v4> {
        var usage = rusage_info_v4()
        let failure: NativeCounterFailure? = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                errno = 0
                let returned = proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                let code = errno
                return returned == 0
                    ? nil
                    : NativeCounterFailure(
                        returned: returned, expected: nil, errorNumber: code == 0 ? nil : code)
            }
        }
        if let failure { return .failure(failure) }
        return .value(usage)
    }

    func executablePath(_ pid: Int32) -> NativeCounterRead<String> {
        var path = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        errno = 0
        let returned = proc_pidpath(pid, &path, UInt32(path.count))
        let code = errno
        guard returned > 0 else {
            return .failure(.init(returned: returned, expected: nil, errorNumber: code == 0 ? nil : code))
        }
        return .value(String(decoding: path.prefix { $0 != 0 }, as: UTF8.self))
    }
}

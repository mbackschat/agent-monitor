import Darwin
import Foundation

public struct ProcessSnapshot: Sendable {
    public let samples: [ProcessSample]
    public let enumeratedCount: Int
    public let unreadableCount: Int
}

public struct NativeProcessReader: Sendable {
    private let numerator: UInt32
    private let denominator: UInt32

    public init() throws {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom > 0 else {
            throw NativeReadError.timebase
        }
        numerator = timebase.numer
        denominator = timebase.denom
    }

    public func snapshot(excluding excluded: Set<Int32> = []) throws -> ProcessSnapshot {
        let pids = try processIDs()
        var samples: [ProcessSample] = []
        var unreadable = 0
        for pid in pids where !excluded.contains(pid) {
            guard let info = bsdInfo(pid) else {
                unreadable += 1
                continue
            }
            guard info.pbi_uid == getuid() else { continue }
            let identity = identity(info)
            let executable = executablePath(pid) ?? ""
            var usage = rusage_info_v2()
            let resourceResult = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            let timestamp = seconds(mach_absolute_time())
            guard let after = bsdInfo(pid), self.identity(after) == identity else {
                unreadable += 1
                continue
            }
            let cpu = resourceResult == 0 ? seconds(usage.ri_user_time) + seconds(usage.ri_system_time) : nil
            var sample = ProcessSample(
                identity: identity, parentPID: Int32(bitPattern: info.pbi_ppid), executable: executable,
                name: cString(info.pbi_comm),
                sampledAt: timestamp, cpuSeconds: cpu,
                footprintBytes: resourceResult == 0 ? usage.ri_phys_footprint : nil
            )
            sample.terminalDevice = info.e_tdev == 0 || info.e_tdev == UInt32.max ? nil : info.e_tdev
            samples.append(sample)
        }
        return ProcessSnapshot(samples: samples, enumeratedCount: pids.count, unreadableCount: unreadable)
    }

    public func metadata(for sample: ProcessSample, includeCommand: Bool = false) -> ProcessMetadata {
        guard matches(sample) else { return ProcessMetadata(status: .unavailable) }
        var metadata = arguments(sample.identity.pid, includeCommand: includeCommand)
        metadata.cwd = currentDirectory(sample.identity.pid)
        if sample.runtimeProvider != nil, let device = sample.terminalDevice {
            metadata.terminal = terminalName(device)
        }
        if sample.runtimeProvider == .codex {
            metadata.writerThreadIDs = writerThreadIDs(sample.identity.pid)
        }
        guard matches(sample) else { return ProcessMetadata(status: .unavailable) }
        return metadata
    }

    private func matches(_ sample: ProcessSample) -> Bool {
        guard let info = bsdInfo(sample.identity.pid), identity(info) == sample.identity else { return false }
        return executablePath(sample.identity.pid) == sample.executable
    }

    private func seconds(_ ticks: UInt64) -> Double {
        // XNU task_power_info supplies Mach ticks, confirmed against CLOCK_PROCESS_CPUTIME_ID.
        // See docs/research/macos-process-attribution.md, observation 2026-10-14.
        ResourceMath.seconds(ticks: ticks, numerator: numerator, denominator: denominator)
    }

    private func processIDs() throws -> [Int32] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { throw NativeReadError.enumeration(errno) }
        var capacity = Int(needed) / MemoryLayout<pid_t>.stride + 256
        for _ in 0..<3 {
            var pids = [pid_t](repeating: 0, count: capacity)
            let length = Int32(pids.count * MemoryLayout<pid_t>.stride)
            let read = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, length)
            guard read > 0 else { throw NativeReadError.enumeration(errno) }
            if read < length { return pids.prefix(Int(read) / MemoryLayout<pid_t>.stride).filter { $0 > 0 } }
            capacity *= 2
        }
        throw NativeReadError.enumeration(EOVERFLOW)
    }

    private func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }

    private func identity(_ info: proc_bsdinfo) -> ProcessIdentity {
        ProcessIdentity(
            pid: Int32(bitPattern: info.pbi_pid),
            startMicroseconds: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec)
    }

    private func executablePath(_ pid: Int32) -> String? {
        var path = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        return String(decoding: path.prefix { $0 != 0 }, as: UTF8.self)
    }

    private func terminalName(_ device: UInt32) -> String? {
        guard device != UInt32.max, device != 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 128)
        guard devname_r(Int32(bitPattern: device), S_IFCHR, &buffer, Int32(buffer.count)) != nil else {
            return "device:\(device)"
        }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    private func currentDirectory(_ pid: Int32) -> String? {
        var paths = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &paths, size) == size else { return nil }
        let path = cString(paths.pvi_cdir.vip_path)
        return path.isEmpty ? nil : path
    }

    private func arguments(_ pid: Int32, includeCommand: Bool) -> ProcessMetadata {
        var maximum: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var sizeMIB: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&sizeMIB, 2, &maximum, &size, nil, 0) == 0,
            maximum > 0, maximum <= 16 * 1024 * 1024
        else { return ProcessMetadata(status: .unavailable) }
        var buffer = [UInt8](repeating: 0, count: Int(maximum))
        size = buffer.count
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size <= buffer.count else {
            return ProcessMetadata(status: .unavailable)
        }
        return ProcessArguments.parse(Array(buffer.prefix(size)), includeCommand: includeCommand)
    }

    private func writerThreadIDs(_ pid: Int32) -> [String] {
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0, needed < 16 * 1024 * 1024 else { return [] }
        var descriptors = [proc_fdinfo](
            repeating: proc_fdinfo(), count: Int(needed) / MemoryLayout<proc_fdinfo>.stride + 64)
        let capacity = Int32(descriptors.count * MemoryLayout<proc_fdinfo>.stride)
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, capacity)
        guard bytes > 0, bytes < capacity else { return [] }
        var ids: Set<String> = []
        for descriptor in descriptors.prefix(Int(bytes) / MemoryLayout<proc_fdinfo>.stride)
        where descriptor.proc_fdtype == PROX_FDTYPE_VNODE {
            var vnode = vnode_fdinfowithpath()
            let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &vnode, size) == size
            else { continue }
            let path = URL(fileURLWithPath: cString(vnode.pvip.vip_path))
            guard path.deletingLastPathComponent().lastPathComponent == "thread-writer-locks",
                path.pathExtension == "lock",
                let uuid = UUID(uuidString: path.deletingPathExtension().lastPathComponent)
            else { continue }
            ids.insert(uuid.uuidString.lowercased())
        }
        return ids.sorted()
    }

    private func cString<T>(_ value: T) -> String {
        withUnsafeBytes(of: value) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

public enum NativeReadError: Error, LocalizedError {
    case timebase
    case enumeration(Int32)

    public var errorDescription: String? {
        switch self {
        case .timebase: "Cannot read the macOS CPU timebase."
        case .enumeration(let code): "Cannot enumerate macOS processes (errno \(code))."
        }
    }
}

import Darwin
import Foundation
import Synchronization

public struct ProcessSnapshot: Sendable {
    public let samples: [ProcessSample]
    public let enumeratedCount: Int
    public let unreadableCount: Int
    public let listedAt: Double
    public let scanSeconds: Double
    public let hostCounters: HostCPUCounters?
    public let logicalCPUCount: Int
    public let nativeOutcomes: [NativeCounterOutcome]
    public let nativeTiming: NativeScanTiming?
    public let promptEvidence: [PromptEvidence]
    public let listedPIDs: [Int32]?

    public init(
        samples: [ProcessSample], enumeratedCount: Int, unreadableCount: Int,
        listedAt: Double, scanSeconds: Double, hostCounters: HostCPUCounters?, logicalCPUCount: Int,
        nativeOutcomes: [NativeCounterOutcome] = [], nativeTiming: NativeScanTiming? = nil,
        promptEvidence: [PromptEvidence] = [], listedPIDs: [Int32]? = nil
    ) {
        self.samples = samples
        self.enumeratedCount = enumeratedCount
        self.unreadableCount = unreadableCount
        self.listedAt = listedAt
        self.scanSeconds = scanSeconds
        self.hostCounters = hostCounters
        self.logicalCPUCount = logicalCPUCount
        self.nativeOutcomes = nativeOutcomes
        self.nativeTiming = nativeTiming
        self.promptEvidence = promptEvidence
        self.listedPIDs = listedPIDs
    }
}

public struct NativeProcessReader: DiagnosisReading, InspectionReading {
    private var profile: PipelineProfile?

    package func profiling(_ profile: PipelineProfile) -> Self {
        var reader = self
        reader.profile = profile
        return reader
    }

    private let numerator: UInt32
    private let denominator: UInt32
    private let adapters: AttributionAdapters
    private final class RuntimeClaimStore: Sendable {
        let cache: Mutex<RuntimeClaimsCache>
        init(adapters: AttributionAdapters) {
            cache = Mutex(RuntimeClaimsCache(adapters: adapters))
        }
    }
    private let runtimeClaims: RuntimeClaimStore
    private let hostSource: any HostCPUReading
    private let counterAccess: any NativeCounterAccess

    public init(hostSource: any HostCPUReading = NativeHostCPUReader()) throws {
        try self.init(adapters: .builtIn, hostSource: hostSource)
    }

    init(
        adapters: AttributionAdapters, hostSource: any HostCPUReading = NativeHostCPUReader(),
        counterAccess: any NativeCounterAccess = SystemNativeCounterAccess()
    ) throws {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom > 0 else {
            throw NativeReadError.timebase
        }
        numerator = timebase.numer
        denominator = timebase.denom
        self.adapters = adapters
        runtimeClaims = RuntimeClaimStore(adapters: adapters)
        self.hostSource = hostSource
        self.counterAccess = counterAccess
    }

    public func snapshot(excluding excluded: Set<Int32> = []) throws -> ProcessSnapshot {
        try snapshot(processIDs: { try processIDs() }, excluding: excluded)
    }

    func snapshot(processIDs: () throws -> [Int32], excluding excluded: Set<Int32> = []) throws
        -> ProcessSnapshot
    {
        let started = mach_absolute_time()
        let hostCounters = hostSource.read()
        let listing = mach_absolute_time()
        let continuous = mach_continuous_time()
        let wallTime = Date()
        let pids = try processIDs()
        var samples: [ProcessSample] = []
        var outcomes: [NativeCounterOutcome] = []
        var unreadable = 0
        for pid in pids where !excluded.contains(pid) {
            let read = readProcess(pid)
            outcomes += read.outcomes
            unreadable += read.unreadable
            if let sample = read.sample { samples.append(sample) }
        }
        let ended = mach_absolute_time()
        return ProcessSnapshot(
            samples: samples, enumeratedCount: pids.count, unreadableCount: unreadable,
            listedAt: seconds(listing), scanSeconds: seconds(ended) - seconds(listing),
            hostCounters: hostCounters,
            logicalCPUCount: hostCounters?.processors.count ?? ProcessInfo.processInfo.activeProcessorCount,
            nativeOutcomes: outcomes,
            nativeTiming: NativeScanTiming(
                startedAbsolute: started, listingAbsolute: listing, listingContinuous: continuous,
                listingWallTime: wallTime, endedAbsolute: ended, numerator: numerator,
                denominator: denominator), listedPIDs: pids)
    }

    private func readProcess(_ pid: Int32, allowance: InspectionAllowance? = nil)
        -> (sample: ProcessSample?, outcomes: [NativeCounterOutcome], unreadable: Int)
    {
        var outcomes: [NativeCounterOutcome] = []
        var unreadable = 0
        guard allowance?.permitsOperation() != false else { return (nil, outcomes, unreadable) }
        let initial = counterAccess.bsdInfo(pid)
        let initialTime = mach_absolute_time()
        guard let info = initial.value else {
            appendFailure(
                initial, pid: pid, identity: nil, operation: .bsdInfo, at: initialTime, to: &outcomes)
            unreadable += 1
            return (nil, outcomes, unreadable)
        }
        guard info.pbi_uid == getuid() else {
            outcomes.append(
                NativeCounterOutcome(
                    pid: pid, identity: ProcessIdentity(info), operation: .bsdInfo, status: .outOfScopeUser,
                    failure: nil, observedAtTicks: initialTime))
            return (nil, outcomes, unreadable)
        }
        let identity = ProcessIdentity(info)
        guard allowance?.permitsOperation() != false else { return (nil, outcomes, unreadable) }
        let executable = counterAccess.executablePath(pid)
        let executableTime = mach_absolute_time()
        guard allowance?.permitsOperation() != false else { return (nil, outcomes, unreadable) }
        let resource = counterAccess.resources(pid)
        let timestamp = mach_absolute_time()
        guard allowance?.permitsOperation() != false else { return (nil, outcomes, unreadable) }
        let verification = counterAccess.bsdInfo(pid)
        let verificationTime = mach_absolute_time()
        let verified =
            verification.value.map {
                ProcessIdentity($0) == identity && $0.pbi_uid == info.pbi_uid
            } ?? false
        appendFailure(
            executable, pid: pid, identity: verified ? identity : nil, operation: .executablePath,
            at: executableTime, to: &outcomes)
        appendFailure(
            resource, pid: pid, identity: verified ? identity : nil, operation: .resourceUsage,
            at: timestamp, to: &outcomes)
        guard let after = verification.value else {
            appendFailure(
                verification, pid: pid, identity: nil, operation: .identityVerification,
                at: verificationTime, to: &outcomes)
            unreadable += 1
            return (nil, outcomes, unreadable)
        }
        guard ProcessIdentity(after) == identity, after.pbi_uid == info.pbi_uid else {
            outcomes.append(
                NativeCounterOutcome(
                    pid: pid, identity: nil, operation: .identityVerification, status: .identityMismatch,
                    failure: nil, observedAtTicks: verificationTime,
                    verifiedIdentity: after.pbi_uid == getuid() ? ProcessIdentity(after) : nil))
            unreadable += 1
            return (nil, outcomes, unreadable)
        }
        let usage = resource.value
        let rawCPU = usage.map {
            NativeCPUCounters(
                user: $0.ri_user_time, system: $0.ri_system_time,
                numerator: numerator, denominator: denominator)
        }
        var sample = ProcessSample(
            identity: identity, parentPID: Int32(bitPattern: info.pbi_ppid),
            executable: executable.value ?? "",
            name: cString(info.pbi_comm), sampledAt: seconds(timestamp), cpuSeconds: rawCPU?.seconds,
            footprintBytes: usage?.ri_phys_footprint)
        sample.rawCPU = rawCPU
        sample.sampledAtTicks = timestamp
        sample.startedAtTicks = usage?.ri_proc_start_abstime
        sample.startedAt = sample.startedAtTicks.map(seconds)
        sample.kernelPeakFootprintBytes = usage?.ri_lifetime_max_phys_footprint
        sample.terminalDevice = info.e_tdev == 0 || info.e_tdev == UInt32.max ? nil : info.e_tdev
        return (sample, outcomes, unreadable)
    }

    func inspectionPIDs(allowance: InspectionAllowance) throws -> [Int32] {
        try processIDs(allowance: allowance)
    }

    func inspectionRead(_ pid: Int32, allowance: InspectionAllowance) -> InspectionRead? {
        guard let sample = readProcess(pid, allowance: allowance).sample, sample.cpuSeconds != nil else {
            return nil
        }
        guard allowance.permitsOperation() else { return nil }
        let parentInfo = counterAccess.bsdInfo(sample.parentPID).value
        let parent = parentInfo.flatMap { $0.pbi_uid == getuid() ? ProcessIdentity($0) : nil }
        // CWD is a mutable observation too. Keep it only inside a fresh identity/path bracket.
        guard allowance.permitsOperation() else {
            return InspectionRead(sample: sample, parent: parent, cwd: nil)
        }
        let cwd = counterAccess.workingDirectory(pid)
        guard allowance.permitsOperation(), let after = counterAccess.bsdInfo(pid).value,
            after.pbi_uid == getuid(), ProcessIdentity(after) == sample.identity,
            allowance.permitsOperation(), counterAccess.executablePath(pid).value == sample.executable
        else { return InspectionRead(sample: sample, parent: parent, cwd: nil) }
        return InspectionRead(sample: sample, parent: parent, cwd: cwd)
    }

    private func appendFailure<Value>(
        _ result: NativeCounterRead<Value>, pid: Int32, identity: ProcessIdentity?,
        operation: NativeCounterOperation, at time: UInt64, to outcomes: inout [NativeCounterOutcome]
    ) {
        if case .failure(let failure) = result {
            outcomes.append(
                NativeCounterOutcome(
                    pid: pid, identity: identity, operation: operation, status: failure.status,
                    failure: failure, observedAtTicks: time))
        }
    }

    public func metadata(for sample: ProcessSample, includeCommand: Bool = false) -> ProcessMetadata {
        switch observation(for: sample, includeCommand: includeCommand) {
        case .observed(let metadata): metadata
        case .notObserved: ProcessMetadata(status: .unavailable)
        }
    }

    public func captureLaunchEvidence(for sample: ProcessSample, maximumBytes: Int) -> ProcessMetadata? {
        guard maximumBytes > 0, isCurrent(sample) else { return ProcessMetadata(status: .unavailable) }
        let captured = arguments(sample.identity.pid, includeCommand: false, maximumBytes: maximumBytes)
        guard isCurrent(sample) else { return ProcessMetadata(status: .unavailable) }
        return captured
    }

    public func metadata(
        for sample: ProcessSample, includeCommand: Bool, capturedLaunch: ProcessMetadata?
    ) -> ProcessMetadata {
        switch observation(for: sample, includeCommand: includeCommand, capturedLaunch: capturedLaunch) {
        case .observed(let metadata): metadata
        case .notObserved: capturedLaunch ?? ProcessMetadata(status: .unavailable)
        }
    }

    public func observation(for sample: ProcessSample) -> DiagnosisObservation {
        observation(for: sample, includeCommand: false)
    }

    private func observation(
        for sample: ProcessSample, includeCommand: Bool, capturedLaunch: ProcessMetadata? = nil
    ) -> DiagnosisObservation {
        guard isCurrent(sample) else { return .notObserved }
        let captured = capturedLaunch.flatMap { metadata -> ProcessMetadata? in
            switch metadata.status {
            case .truncated, .unavailable: nil
            case .markerRead, .notObserved, .malformed: metadata
            }
        }
        var metadata = captured ?? arguments(sample.identity.pid, includeCommand: includeCommand)
        if includeCommand, captured != nil {
            metadata.command = arguments(sample.identity.pid, includeCommand: true).command
        }
        metadata.cwd = currentDirectory(sample.identity.pid)
        let plan = runtimeClaims.cache.withLock { $0.claims(for: sample.executable) }
            .plan(invokedAs: metadata.invocation)
        if let device = sample.terminalDevice, plan.isRuntime {
            metadata.terminal = terminalName(device)
        }
        var observations = RuntimeObservations()
        for request in plan.requests {
            switch request {
            case .openFilePaths: observations.openFilePaths = openFilePaths(sample.identity.pid)
            case .listeningSockets: observations.listeningSockets = listeningSockets(sample.identity.pid)
            }
        }
        let evidence = plan.evidence(from: observations)
        metadata.writerThreadIDs = evidence.writerThreadIDs
        metadata.listeningSockets = evidence.listeningSockets
        guard isCurrent(sample) else { return .notObserved }
        return .observed(metadata)
    }

    public func isCurrent(_ sample: ProcessSample) -> Bool {
        guard let info = bsdInfo(sample.identity.pid), info.pbi_uid == getuid(),
            ProcessIdentity(info) == sample.identity
        else { return false }
        return executablePath(sample.identity.pid) == sample.executable
    }

    /// An explicit inspection reads only argv, with the same lifetime/path bracket as metadata.
    /// The 256 KiB ceiling bounds one inspected command; oversized argument areas remain unavailable.
    public static func inspectCommand(_ process: HeavyProcess) async throws -> [String]? {
        guard !process.isHistorical else { return nil }
        let worker = SerialBlockingWorker(name: "agent-monitor-command", initial: ())
        do {
            let command = try await worker.perform { _ -> [String]? in
                let reader = try NativeProcessReader()
                let sample = ProcessSample(
                    identity: process.process, parentPID: 0, executable: process.executable,
                    name: process.name, sampledAt: 0, cpuSeconds: nil, footprintBytes: nil)
                guard reader.isCurrent(sample) else { return nil }
                let command = reader.arguments(
                    process.process.pid, includeCommand: true, maximumBytes: 256 * 1024
                ).command
                guard reader.isCurrent(sample) else { return nil }
                return command
            }
            await worker.close()
            return command
        } catch {
            await worker.close()
            throw error
        }
    }

    private func seconds(_ ticks: UInt64) -> Double {
        // XNU task_power_info supplies Mach ticks, confirmed against CLOCK_PROCESS_CPUTIME_ID.
        // See docs/research/macos-process-attribution.md, observation 2026-10-14.
        ResourceMath.seconds(ticks: ticks, numerator: numerator, denominator: denominator)
    }

    private func processIDs(allowance: InspectionAllowance? = nil) throws -> [Int32] {
        guard allowance?.permitsOperation() != false else { throw NativeReadError.enumeration(EINTR) }
        let needed = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), nil, 0)
        guard needed > 0 else { throw NativeReadError.enumeration(errno) }
        var capacity = Int(needed) / MemoryLayout<pid_t>.stride + 256
        for _ in 0..<3 {
            var pids = [pid_t](repeating: 0, count: capacity)
            let length = Int32(pids.count * MemoryLayout<pid_t>.stride)
            guard allowance?.permitsOperation() != false else { throw NativeReadError.enumeration(EINTR) }
            let read = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), &pids, length)
            guard read > 0 else { throw NativeReadError.enumeration(errno) }
            if read < length { return pids.prefix(Int(read) / MemoryLayout<pid_t>.stride).filter { $0 > 0 } }
            capacity *= 2
        }
        throw NativeReadError.enumeration(EOVERFLOW)
    }

    private func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        counterAccess.bsdInfo(pid).value
    }

    private func executablePath(_ pid: Int32) -> String? {
        counterAccess.executablePath(pid).value
    }

    private struct TerminalName: Sendable {
        let value: String
        let observedAt: Double
    }
    private static let terminalNames = Mutex<[UInt32: TerminalName]>([:])

    private func terminalName(_ device: UInt32) -> String? {
        guard device != UInt32.max, device != 0 else { return nil }
        return Self.terminalNames.withLock { cache in
            let now = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
            if let found = cache[device], now - found.observedAt < 60 { return found.value }
            var buffer = [CChar](repeating: 0, count: 128)
            guard devname_r(Int32(bitPattern: device), S_IFCHR, &buffer, Int32(buffer.count)) != nil else {
                return "device:\(device)"
            }
            let name = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            if cache.count >= 256, let oldest = cache.min(by: { $0.value.observedAt < $1.value.observedAt }) {
                cache[oldest.key] = nil
            }
            // devname_r scans /dev (2026-10-24 stack profile); cache only the device-to-name lookup.
            cache[device] = TerminalName(value: name, observedAt: now)
            return name
        }
    }

    private func currentDirectory(_ pid: Int32) -> String? {
        counterAccess.workingDirectory(pid)
    }

    private static let argumentCapacity: Int? = {
        var maximum: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mib, 2, &maximum, &size, nil, 0) == 0,
            maximum > 0, maximum <= 16 * 1024 * 1024
        else { return nil }
        return Int(maximum)
    }()

    private func arguments(
        _ pid: Int32, includeCommand: Bool, maximumBytes: Int = 16 * 1024 * 1024
    ) -> ProcessMetadata {
        guard let maximum = Self.argumentCapacity, maximumBytes > 0 else {
            return ProcessMetadata(status: .unavailable)
        }
        return NativeProcessArguments.read(
            maximumBytes: min(maximum, maximumBytes), includeCommand: includeCommand, adapters: adapters,
            profile: profile
        ) { buffer in
            var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
            var count = buffer?.count ?? 0
            guard sysctl(&mib, 3, buffer?.baseAddress, &count, nil, 0) == 0 else { return nil }
            return count
        }
    }

    private func descriptors(_ pid: Int32) -> [proc_fdinfo] {
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0, needed < 16 * 1024 * 1024 else { return [] }
        var descriptors = [proc_fdinfo](
            repeating: proc_fdinfo(), count: Int(needed) / MemoryLayout<proc_fdinfo>.stride + 64)
        let capacity = Int32(descriptors.count * MemoryLayout<proc_fdinfo>.stride)
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, capacity)
        guard bytes > 0, bytes < capacity else { return [] }
        return Array(descriptors.prefix(Int(bytes) / MemoryLayout<proc_fdinfo>.stride))
    }

    /// Bound Unix sockets in the listening state; client and unbound sockets carry no own path.
    func listeningSockets(_ pid: Int32) -> [String] {
        var paths: Set<String> = []
        for descriptor in descriptors(pid) where descriptor.proc_fdtype == PROX_FDTYPE_SOCKET {
            var info = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &info, size) == size,
                info.psi.soi_kind == SOCKINFO_UN, Int32(info.psi.soi_options) & SO_ACCEPTCONN != 0
            else { continue }
            let path = cString(info.psi.soi_proto.pri_un.unsi_addr.ua_sun.sun_path)
            if path.hasPrefix("/") { paths.insert(path) }
        }
        return paths.sorted()
    }

    private func openFilePaths(_ pid: Int32) -> [String] {
        var paths: Set<String> = []
        for descriptor in descriptors(pid) where descriptor.proc_fdtype == PROX_FDTYPE_VNODE {
            var vnode = vnode_fdinfowithpath()
            let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &vnode, size) == size
            else { continue }
            let path = cString(vnode.pvip.vip_path)
            if !path.isEmpty { paths.insert(path) }
        }
        return paths.sorted()
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

import Darwin

public struct NativeHostCPUReader: HostCPUReading {
    public init() {}

    public func read() -> HostCPUCounters? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var count: natural_t = 0
        var info: processor_info_array_t?
        var length: mach_msg_type_number_t = 0
        // host_statistics caches third-party reads at short intervals; see the 2026-10-16
        // review follow-up in docs/research/cpu-accounting.md.
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &info, &length)
        guard let info else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                vm_size_t(length) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        guard result == KERN_SUCCESS, count > 0, Int(length) == Int(count) * Int(CPU_STATE_MAX) else {
            return nil
        }
        return HostCPUCounters(
            processors: (0..<Int(count)).map { cpu in
                let offset = cpu * Int(CPU_STATE_MAX)
                return HostCPUTicks(
                    user: UInt32(bitPattern: info[offset + Int(CPU_STATE_USER)]),
                    system: UInt32(bitPattern: info[offset + Int(CPU_STATE_SYSTEM)]),
                    idle: UInt32(bitPattern: info[offset + Int(CPU_STATE_IDLE)]),
                    nice: UInt32(bitPattern: info[offset + Int(CPU_STATE_NICE)]))
            })
    }
}

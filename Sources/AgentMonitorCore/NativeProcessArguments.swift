import Foundation

enum NativeProcessArguments {
    static func read(
        maximumBytes: Int, includeCommand: Bool = false, adapters: AttributionAdapters = .builtIn,
        profile: PipelineProfile? = nil, access: (UnsafeMutableRawBufferPointer?) -> Int?
    ) -> ProcessMetadata {
        let initialCapacity = 65_536
        if maximumBytes > initialCapacity {
            // XNU sysctl_procargsx returns the entire supplied capacity for a truncated tail.
            // Only a shorter result proves this read complete; budgets up to 64 KiB and full
            // buffers keep the size-checked path. See bsd/kern/kern_sysctl.c, sysctl_procargsx.
            let result = withUnsafeTemporaryAllocation(byteCount: initialCapacity, alignment: 1) {
                buffer -> ProcessMetadata? in
                guard let count = access(buffer), count > MemoryLayout<Int32>.size, count <= buffer.count
                else {
                    return ProcessMetadata(status: .unavailable)
                }
                guard count < buffer.count else { return nil }
                profile?.increment(.argumentShortReads)
                return ProcessArguments.parse(
                    UnsafeRawBufferPointer(rebasing: buffer[..<count]), includeCommand: includeCommand,
                    adapters: adapters)
            }
            if let result { return result }
            profile?.increment(.argumentReadFallbacks)
        }
        guard maximumBytes > 0, let needed = access(nil), needed > MemoryLayout<Int32>.size else {
            return ProcessMetadata(status: .unavailable)
        }
        guard needed <= maximumBytes else { return ProcessMetadata(status: .truncated) }
        return withUnsafeTemporaryAllocation(byteCount: needed, alignment: 1) { buffer in
            guard let count = access(buffer), count >= 0, count <= buffer.count else {
                return ProcessMetadata(status: .unavailable)
            }
            guard let after = access(nil) else { return ProcessMetadata(status: .unavailable) }
            guard after <= buffer.count else { return ProcessMetadata(status: .truncated) }
            return ProcessArguments.parse(
                UnsafeRawBufferPointer(rebasing: buffer[..<count]), includeCommand: includeCommand,
                adapters: adapters)
        }
    }
}

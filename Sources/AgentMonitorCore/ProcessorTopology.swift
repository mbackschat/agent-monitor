import Darwin
import Foundation

public struct ProcessorTopology: Equatable, Sendable {
    public struct Level: Equatable, Sendable {
        public let name: String
        public let logicalCPUCount: Int

        public init(name: String, logicalCPUCount: Int) {
            self.name = name
            self.logicalCPUCount = logicalCPUCount
        }
    }

    public let logicalCPUCount: Int
    public let levels: [Level]

    public init(logicalCPUCount: Int, levels: [Level] = []) {
        self.logicalCPUCount = max(1, logicalCPUCount)
        self.levels = levels
    }

    public var performanceCPUCount: Int? {
        var remaining = logicalCPUCount
        var performance = 0
        for level in levels {
            guard level.logicalCPUCount > 0, level.logicalCPUCount <= remaining else { return nil }
            remaining -= level.logicalCPUCount
            switch level.name {
            case "Performance", "Super": performance += level.logicalCPUCount
            case "Efficiency": break
            default: return nil
            }
        }
        return remaining == 0 && performance > 0 ? performance : nil
    }

    public static func readSystem() -> Self {
        read(integer: integer, string: string, fallback: ProcessInfo.processInfo.processorCount)
    }

    static func read(integer: (String) -> Int?, string: (String) -> String?, fallback: Int) -> Self {
        let total = integer("hw.logicalcpu_max").flatMap { $0 > 0 ? $0 : nil } ?? max(1, fallback)
        guard let count = integer("hw.nperflevels"), (1...64).contains(count) else {
            return Self(logicalCPUCount: total)
        }
        var levels: [Level] = []
        for index in 0..<count {
            let prefix = "hw.perflevel\(index)"
            guard let name = string("\(prefix).name"), let count = integer("\(prefix).logicalcpu_max") else {
                return Self(logicalCPUCount: total)
            }
            levels.append(Level(name: name, logicalCPUCount: count))
        }
        return Self(logicalCPUCount: total, levels: levels)
    }

    private static func integer(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout.size(ofValue: value)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0,
            size == MemoryLayout<Int32>.size
        else { return nil }
        return Int(value)
    }

    private static func string(_ name: String) -> String? {
        // XNU kern_mib.c exposes perflevel names as NUL-terminated strings. Reject truncation.
        var bytes = [UInt8](repeating: 0, count: 65)
        var size = bytes.count
        let result = bytes.withUnsafeMutableBytes { sysctlbyname(name, $0.baseAddress, &size, nil, 0) }
        guard result == 0, size > 1, size <= bytes.count, bytes[size - 1] == 0,
            !bytes.prefix(size - 1).contains(0)
        else { return nil }
        return String(bytes: bytes.prefix(size - 1), encoding: .utf8)
    }
}

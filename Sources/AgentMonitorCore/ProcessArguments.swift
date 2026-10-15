import Darwin
import Foundation

public enum ProcessArguments {
    public static func parse(_ bytes: [UInt8], includeCommand: Bool = false) -> ProcessMetadata {
        parse(bytes, includeCommand: includeCommand, adapters: .builtIn)
    }

    static func parse(
        _ bytes: [UInt8], includeCommand: Bool = false, adapters: AttributionAdapters
    ) -> ProcessMetadata {
        bytes.withUnsafeBytes { parse($0, includeCommand: includeCommand, adapters: adapters) }
    }

    static func parse(
        _ bytes: UnsafeRawBufferPointer, includeCommand: Bool, adapters: AttributionAdapters
    ) -> ProcessMetadata {
        let malformed = ProcessMetadata(status: .malformed)
        guard bytes.count >= MemoryLayout<Int32>.size else { return malformed }
        let argc = bytes.loadUnaligned(as: Int32.self)
        guard argc > 0, argc <= 65_536 else { return malformed }
        var cursor = MemoryLayout<Int32>.size
        func nextRange() -> Range<Int>? {
            guard cursor < bytes.count, let base = bytes.baseAddress,
                let terminator = memchr(base + cursor, 0, bytes.count - cursor)
            else { return nil }
            let end = base.distance(to: UnsafeRawPointer(terminator))
            let range = cursor..<end
            cursor = end + 1
            return range
        }
        guard nextRange() != nil else { return malformed }
        while cursor < bytes.count, bytes[cursor] == 0 { cursor += 1 }
        var arguments: [String] = []
        for _ in 0..<argc {
            guard let range = nextRange() else { return malformed }
            if includeCommand { arguments.append(String(decoding: bytes[range], as: UTF8.self)) }
        }

        let allowedKeys = adapters.environmentKeys.map { (name: $0, bytes: Array($0.utf8)) }
        var environment: [String: Set<String>] = [:]
        while cursor < bytes.count {
            guard let range = nextRange() else { return malformed }
            if range.isEmpty { break }
            guard let base = bytes.baseAddress,
                let equal = memchr(base + range.lowerBound, CInt(UInt8(ascii: "=")), range.count)
            else { continue }
            let separator = base.distance(to: UnsafeRawPointer(equal))
            let keyBytes = bytes[range.lowerBound..<separator]
            guard let key = allowedKeys.first(where: { keyBytes.elementsEqual($0.bytes) }) else { continue }
            environment[key.name, default: []].insert(
                String(decoding: bytes[(separator + 1)..<range.upperBound], as: UTF8.self))
        }
        guard let found = try? adapters.markers(in: environment) else { return malformed }
        return ProcessMetadata(
            markers: found, status: found.isEmpty ? .notObserved : .markerRead,
            command: includeCommand ? arguments : nil
        )
    }

}

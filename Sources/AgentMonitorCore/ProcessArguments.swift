import Foundation

public enum ProcessArguments {
    public static func parse(_ bytes: [UInt8], includeCommand: Bool = false) -> ProcessMetadata {
        parse(bytes, includeCommand: includeCommand, adapters: .builtIn)
    }

    static func parse(
        _ bytes: [UInt8], includeCommand: Bool = false, adapters: AttributionAdapters
    ) -> ProcessMetadata {
        let malformed = ProcessMetadata(status: .malformed)
        guard bytes.count >= MemoryLayout<Int32>.size else { return malformed }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0, argc <= 65_536 else { return malformed }
        var cursor = MemoryLayout<Int32>.size
        func nextString() -> String? {
            guard cursor < bytes.count, let end = bytes[cursor...].firstIndex(of: 0) else { return nil }
            let value = String(decoding: bytes[cursor..<end], as: UTF8.self)
            cursor = end + 1
            return value
        }
        guard nextString() != nil else { return malformed }
        while cursor < bytes.count, bytes[cursor] == 0 { cursor += 1 }
        var arguments: [String] = []
        for _ in 0..<argc {
            guard let value = nextString() else { return malformed }
            if includeCommand { arguments.append(value) }
        }

        let allowedKeys = adapters.environmentKeys
        var environment: [String: Set<String>] = [:]
        while cursor < bytes.count {
            guard let entry = nextString() else { return malformed }
            if entry.isEmpty { break }
            guard let equal = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<equal])
            guard allowedKeys.contains(key) else { continue }
            environment[key, default: []].insert(String(entry[entry.index(after: equal)...]))
        }
        guard let found = try? adapters.markers(in: environment) else { return malformed }
        return ProcessMetadata(
            markers: found, status: found.isEmpty ? .notObserved : .markerRead,
            command: includeCommand ? arguments : nil
        )
    }

}

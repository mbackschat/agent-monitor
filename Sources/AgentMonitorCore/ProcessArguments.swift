import Foundation

public enum ProcessArguments {
    public static func parse(_ bytes: [UInt8], includeCommand: Bool = false) -> ProcessMetadata {
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

        var markers: [String: String] = [:]
        while cursor < bytes.count {
            guard let entry = nextString() else { return malformed }
            if entry.isEmpty { break }
            guard let equal = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<equal])
            guard ["CODEX_THREAD_ID", "CODEX_SESSION_ID", "CLAUDE_CODE_SESSION_ID"].contains(key) else {
                continue
            }
            let value = String(entry[entry.index(after: equal)...])
            guard let uuid = UUID(uuidString: value) else { return malformed }
            let normalized = uuid.uuidString.lowercased()
            if let previous = markers[key], previous != normalized { return malformed }
            markers[key] = normalized
        }
        if markers["CLAUDE_CODE_SESSION_ID"] != nil,
            markers["CODEX_THREAD_ID"] != nil || markers["CODEX_SESSION_ID"] != nil
        {
            return malformed
        }
        let marker =
            markers["CLAUDE_CODE_SESSION_ID"].map {
                SessionMarker(threadID: $0, provider: .claude)
            }
            ?? markers["CODEX_THREAD_ID"].map {
                SessionMarker(threadID: $0, rootSessionID: markers["CODEX_SESSION_ID"])
            }
        return ProcessMetadata(
            marker: marker, status: marker == nil ? .notObserved : .markerRead,
            command: includeCommand ? arguments : nil
        )
    }
}

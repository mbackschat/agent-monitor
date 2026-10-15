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
        var sockets: Set<String> = []
        while cursor < bytes.count {
            guard let entry = nextString() else { return malformed }
            if entry.isEmpty { break }
            guard let equal = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<equal])
            if key == "CLAUDE_CODE_MESSAGING_SOCKET" {
                sockets.insert(String(entry[entry.index(after: equal)...]))
                continue
            }
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
                SessionMarker(threadID: $0, provider: .claude, inboxSocket: inbox(sockets))
            }
            ?? markers["CODEX_THREAD_ID"].map {
                SessionMarker(threadID: $0, rootSessionID: markers["CODEX_SESSION_ID"], provider: .codex)
            }
        return ProcessMetadata(
            marker: marker, status: marker == nil ? .notObserved : .markerRead,
            command: includeCommand ? arguments : nil
        )
    }

    /// An unusable inbox only disables messaging, so it never makes attribution malformed.
    /// sun_path holds 104 bytes including the terminator (sys/un.h); Claude Code documents the
    /// variable at https://code.claude.com/docs/en/env-vars.
    private static func inbox(_ values: Set<String>) -> String? {
        guard values.count == 1, let path = values.first, path.hasPrefix("/"), path.utf8.count < 104,
            path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return path
    }
}

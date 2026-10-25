import Testing

@testable import AgentMonitorCore

@Test func completeShortArgumentReadNeedsOneNativeCall() {
    let bytes = argumentBuffer(environment: ["CODEX_THREAD_ID=\(sessionA)"])
    var calls = 0
    let result = NativeProcessArguments.read(maximumBytes: 1_048_576) { buffer in
        calls += 1
        guard let buffer else { return bytes.count }
        bytes.withUnsafeBytes { buffer.copyMemory(from: $0) }
        return bytes.count
    }
    #expect(result.status == .markerRead)
    #expect(result.markers == [SessionMarker(threadID: sessionA, provider: .codex)])
    #expect(calls == 1)
}

@Test func fullArgumentReadNeverParsesSuccessfulTailFragment() {
    var fragment = argumentBuffer(environment: ["CODEX_THREAD_ID=\(sessionB)"])
    fragment += Array(repeating: 0, count: 65_536 - fragment.count)
    var reads = 0
    let result = NativeProcessArguments.read(maximumBytes: fragment.count + 1) { buffer in
        guard let buffer else { return fragment.count + 100_000 }
        reads += 1
        fragment.withUnsafeBytes { buffer.copyMemory(from: $0) }
        return fragment.count
    }
    #expect(result.status == .truncated)
    #expect(result.markers.isEmpty)
    #expect(result.invocation == nil)
    #expect(reads <= 1)
}

@Test func exactCapacityArgumentReadUsesVerifiedFallback() {
    let bytes = argumentBuffer(environment: ["CODEX_THREAD_ID=\(sessionA)"])
    let result = NativeProcessArguments.read(maximumBytes: bytes.count) { buffer in
        guard let buffer else { return bytes.count }
        bytes.withUnsafeBytes { buffer.copyMemory(from: $0) }
        return bytes.count
    }
    #expect(result.status == .markerRead)
    #expect(result.markers == [SessionMarker(threadID: sessionA, provider: .codex)])
}

@Test func argumentGrowthDuringFallbackRemainsTruncated() {
    var queries = 0
    let result = NativeProcessArguments.read(maximumBytes: 131_072) { buffer in
        guard let buffer else {
            queries += 1
            return queries == 1 ? 70_000 : 80_000
        }
        buffer.initializeMemory(as: UInt8.self, repeating: 0)
        return buffer.count
    }
    #expect(result.status == .truncated)
    #expect(result.markers.isEmpty)
    #expect(queries == 2)
}

@Test(arguments: [nil, -1, 0, 1, 2, 3, 4, 65_537])
func invalidInitialArgumentReadIsUnavailable(count: Int?) {
    let result = NativeProcessArguments.read(maximumBytes: 131_072) { _ in count }
    #expect(result.status == .unavailable)
    #expect(result.markers.isEmpty)
}

@Test func largeArgumentReadRetriesWholeAreaAndPreservesCommand() {
    let arguments = ["/fixture/worker", "--option", "é"]
    let bytes = argumentBuffer(
        arguments: arguments,
        environment: ["FILLER=" + String(repeating: "x", count: 100_000), "CODEX_THREAD_ID=\(sessionA)"])
    var calls = 0
    let result = NativeProcessArguments.read(maximumBytes: 131_072, includeCommand: true) { buffer in
        calls += 1
        guard let buffer else { return bytes.count }
        let returned = min(buffer.count, bytes.count)
        bytes.suffix(returned).withUnsafeBytes { buffer.copyMemory(from: $0) }
        return returned
    }
    #expect(calls == 4)
    #expect(result == ProcessArguments.parse(bytes, includeCommand: true))
    #expect(result.markers == [SessionMarker(threadID: sessionA, provider: .codex)])
    #expect(result.command == arguments)
}

@Test func cappedPromptArgumentsStillQuerySizeBeforeReading() {
    let bytes = argumentBuffer(environment: ["CODEX_THREAD_ID=\(sessionA)"])
    var calls: [Bool] = []
    let result = NativeProcessArguments.read(maximumBytes: 65_536) { buffer in
        calls.append(buffer != nil)
        if let buffer { bytes.withUnsafeBytes { buffer.copyMemory(from: $0) } }
        return bytes.count
    }
    #expect(calls == [false, true, false])
    #expect(result == ProcessArguments.parse(bytes))
}

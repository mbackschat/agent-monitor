import Synchronization
import Testing

@testable import AgentMonitorCore

private final class RuntimeClaimCalls: Sendable {
    let recognition = Mutex<[String: Int]>([:])
    let invocation = Mutex<[String]>([])
}

private struct RuntimeClaimAdapter: AgentAttributionAdapter {
    let provider: AgentProvider
    let runtimeObservations: Set<RuntimeObservation>
    let calls: RuntimeClaimCalls
    let environmentKeys: Set<String> = []
    var exactRuntimeSpelling: String?
    var byteSensitiveInvocation = false

    func recognizesRuntime(_ executable: String) -> Bool {
        calls.recognition.withLock { $0[executable, default: 0] += 1 }
        if let exactRuntimeSpelling {
            return executable.utf8.elementsEqual(exactRuntimeSpelling.utf8)
        }
        return executable.contains("fixture")
    }
    func acceptsRuntimeInvocation(_ invocation: String, executable: String) -> Bool {
        calls.invocation.withLock { $0.append(invocation) }
        if byteSensitiveInvocation { return invocation.utf8.elementsEqual(executable.utf8) }
        return invocation == "both" || invocation == provider.rawValue
    }
    func marker(in environment: [String: Set<String>]) throws -> SessionMarker? { nil }
    func runtimeEvidence(from observations: RuntimeObservations) -> RuntimeEvidence {
        if !runtimeObservations.contains(.openFilePaths) { #expect(observations.openFilePaths.isEmpty) }
        if !runtimeObservations.contains(.listeningSockets) { #expect(observations.listeningSockets.isEmpty) }
        return RuntimeEvidence(
            writerThreadIDs: observations.openFilePaths, listeningSockets: observations.listeningSockets)
    }
    func runtimeLink(for marker: SessionMarker) -> RuntimeLink? { nil }
    func isSharedRuntime(_ attribution: Attribution) -> Bool { false }
}

private func claimRegistry(_ calls: RuntimeClaimCalls) throws -> AttributionAdapters {
    try AttributionAdapters([
        RuntimeClaimAdapter(provider: .claude, runtimeObservations: [.listeningSockets], calls: calls)
    ])
}

@Suite struct RuntimeClaimsTests {
    @Test func repeatedPositiveAndNegativePathsReuseOnlyExecutableRecognition() throws {
        let calls = RuntimeClaimCalls()
        var cache = RuntimeClaimsCache(adapters: try claimRegistry(calls))
        for _ in 0..<3 {
            let positive = cache.claims(for: "/fixture/runtime").plan(invokedAs: "claude")
            let negative = cache.claims(for: "/usr/bin/node").plan(invokedAs: "claude")
            #expect(positive.isRuntime)
            #expect(!negative.isRuntime)
        }
        #expect(calls.recognition.withLock { $0 } == ["/fixture/runtime": 1, "/usr/bin/node": 1])
        #expect(calls.invocation.withLock { $0 } == ["claude", "claude", "claude"])
        #expect(cache.retainedEntryCount == 2)
    }

    @Test func freshInvocationCanWithdrawAndRestoreAClaimForTheSameExecutable() {
        var cache = RuntimeClaimsCache()
        let path = "/Users/test/.local/share/claude/versions/2.1.301"
        var recognized: [Bool] = []
        for invocation in ["claude", "ugrep", "claude", nil] {
            let plan = cache.claims(for: path).plan(invokedAs: invocation)
            recognized.append(plan.isRuntime)
            #expect(plan.requests == (plan.isRuntime ? [.listeningSockets] : []))
        }
        #expect(recognized == [true, false, true, true])
        #expect(cache.retainedEntryCount == 1)
    }

    @Test func changedPathsGetIndependentClaimsWithoutReplacingOlderPaths() throws {
        let calls = RuntimeClaimCalls()
        var cache = RuntimeClaimsCache(adapters: try claimRegistry(calls))
        var recognized: [Bool] = []
        for path in ["/fixture/a", "/usr/bin/node", "/fixture/b", "/fixture/a"] {
            let plan = cache.claims(for: path).plan()
            recognized.append(plan.isRuntime)
        }
        #expect(recognized == [true, false, true, true])
        #expect(calls.recognition.withLock { $0 } == ["/fixture/a": 1, "/usr/bin/node": 1, "/fixture/b": 1])
        #expect(cache.retainedEntryCount == 3)
    }

    @Test func cacheEvictsInInsertionOrderRatherThanAccessOrder() throws {
        let calls = RuntimeClaimCalls()
        var cache = RuntimeClaimsCache(adapters: try claimRegistry(calls), maximumEntries: 2)
        for path in ["/fixture/a", "/fixture/b", "/fixture/a", "/fixture/c", "/fixture/a", "/fixture/c"] {
            _ = cache.claims(for: path)
        }
        #expect(calls.recognition.withLock { $0 } == ["/fixture/a": 2, "/fixture/b": 1, "/fixture/c": 1])
        #expect(cache.retainedEntryCount == 2)
        #expect(cache.retainedKeyBytes == "/fixture/a".utf8.count + "/fixture/c".utf8.count)
    }

    @Test func byteLimitChargesUTF8RatherThanCharacters() throws {
        let calls = RuntimeClaimCalls()
        var cache = RuntimeClaimsCache(adapters: try claimRegistry(calls), maximumKeyBytes: 9)
        for path in ["/é/a", "/é/b", "/é/a"] { _ = cache.claims(for: path) }
        #expect(calls.recognition.withLock { $0 } == ["/é/a": 2, "/é/b": 1])
        #expect(cache.retainedEntryCount == 1)
        #expect(cache.retainedKeyBytes == 5)
    }

    @Test func defaultEntryLimitRemainsBoundedUnderPathChurn() throws {
        let calls = RuntimeClaimCalls()
        var cache = RuntimeClaimsCache(adapters: try claimRegistry(calls))
        for index in 0...256 { _ = cache.claims(for: "/fixture/\(index)") }
        #expect(cache.retainedEntryCount == 256)
        #expect(cache.retainedKeyBytes <= 65_536)
        _ = cache.claims(for: "/fixture/0")
        #expect(calls.recognition.withLock { $0["/fixture/0"] } == 2)
    }

    @Test func uncacheablePathsStillRecognizeAndDoNotEvictRetainedClaims() throws {
        let calls = RuntimeClaimCalls()
        var cache = RuntimeClaimsCache(adapters: try claimRegistry(calls), maximumEntries: 1)
        _ = cache.claims(for: "/fixture/kept")
        let oversized = "/fixture/" + String(repeating: "x", count: 65_536)
        for path in ["", "fixture/relative", oversized] {
            for _ in 0..<2 {
                let plan = cache.claims(for: path).plan()
                #expect(plan.isRuntime == path.contains("fixture"))
            }
            #expect(calls.recognition.withLock { $0[path] } == 2)
            #expect(cache.retainedEntryCount == 1)
            #expect(cache.retainedKeyBytes == "/fixture/kept".utf8.count)
        }
        _ = cache.claims(for: "/fixture/kept")
        #expect(calls.recognition.withLock { $0["/fixture/kept"] } == 1)
    }

    @Test func copiedCachesAndDifferentRegistriesKeepIndependentClaims() throws {
        let calls = RuntimeClaimCalls()
        var original = RuntimeClaimsCache(adapters: try claimRegistry(calls), maximumEntries: 1)
        _ = original.claims(for: "/fixture/a")
        var copy = original
        _ = copy.claims(for: "/fixture/b")
        _ = original.claims(for: "/fixture/a")
        _ = copy.claims(for: "/fixture/a")
        #expect(calls.recognition.withLock { $0 } == ["/fixture/a": 2, "/fixture/b": 1])
        var unrelated = RuntimeClaimsCache(adapters: try AttributionAdapters([]))
        let empty = unrelated.claims(for: "/fixture/a").plan()
        #expect(!empty.isRuntime)
    }

    @Test func canonicallyEquivalentPathsUseFreshBytesWithoutReplacingTheStoredKey() throws {
        let composed = "/fixture/caf\u{e9}"
        let decomposed = "/fixture/cafe\u{301}"
        let calls = RuntimeClaimCalls()
        let strict = RuntimeClaimAdapter(
            provider: .claude, runtimeObservations: [], calls: calls, exactRuntimeSpelling: composed)
        var cache = RuntimeClaimsCache(adapters: try AttributionAdapters([strict]))
        let original = cache.claims(for: composed).plan()
        let differentBytes = cache.claims(for: decomposed).plan()
        let reused = cache.claims(for: composed).plan()
        #expect(original.isRuntime)
        #expect(!differentBytes.isRuntime)
        #expect(reused.isRuntime)
        #expect(calls.recognition.withLock { $0.values.reduce(0, +) } == 2)
        #expect(cache.retainedEntryCount == 1)
        #expect(cache.retainedKeyBytes == composed.utf8.count)

        let invocation = RuntimeClaimAdapter(
            provider: .claude, runtimeObservations: [], calls: calls, byteSensitiveInvocation: true)
        var invocationCache = RuntimeClaimsCache(adapters: try AttributionAdapters([invocation]))
        let first = invocationCache.claims(for: composed).plan(invokedAs: composed)
        let fresh = invocationCache.claims(for: decomposed).plan(invokedAs: decomposed)
        #expect(first.isRuntime)
        #expect(fresh.isRuntime)
        #expect(invocationCache.retainedEntryCount == 1)
        #expect(invocationCache.retainedKeyBytes == composed.utf8.count)
    }

    @Test(arguments: [false, true])
    func plansKeepEveryClaimAndEachAdaptersObservationAllowlist(reversed: Bool) throws {
        let calls = RuntimeClaimCalls()
        let first = RuntimeClaimAdapter(provider: .codex, runtimeObservations: [.openFilePaths], calls: calls)
        let second = RuntimeClaimAdapter(
            provider: .claude, runtimeObservations: [.listeningSockets], calls: calls)
        let adapters = try AttributionAdapters(reversed ? [second, first] : [first, second])
        var cache = RuntimeClaimsCache(adapters: adapters)
        let observations = RuntimeObservations(
            openFilePaths: ["z-writer", "a-writer", "z-writer"],
            listeningSockets: ["z-listener", "a-listener", "z-listener"])
        let cases: [(String?, Set<AgentProvider>)] = [
            (nil, [.codex, .claude]), ("both", [.codex, .claude]),
            ("codex", [.codex]), ("claude", [.claude]), ("ugrep", []),
        ]
        for (invocation, providers) in cases {
            let plan = cache.claims(for: "/fixture/shared").plan(invokedAs: invocation)
            var expectedRequests: Set<RuntimeObservation> = []
            if providers.contains(.codex) { expectedRequests.insert(.openFilePaths) }
            if providers.contains(.claude) { expectedRequests.insert(.listeningSockets) }
            let actual = plan.evidence(from: observations)
            #expect(plan.providers == providers)
            #expect(plan.isRuntime == !providers.isEmpty)
            #expect(plan.requests == expectedRequests)
            #expect(actual.writerThreadIDs == (providers.contains(.codex) ? ["a-writer", "z-writer"] : []))
            #expect(
                actual.listeningSockets == (providers.contains(.claude) ? ["a-listener", "z-listener"] : []))
        }
        let both = cache.claims(for: "/fixture/shared").plan(invokedAs: "both")
        #expect(both.requests == [.openFilePaths, .listeningSockets])
        #expect(both.evidence(from: observations).writerThreadIDs == ["a-writer", "z-writer"])
        #expect(both.evidence(from: observations).listeningSockets == ["a-listener", "z-listener"])
    }
}

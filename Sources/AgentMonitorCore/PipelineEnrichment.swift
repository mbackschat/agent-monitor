import Foundation
import Synchronization

struct MetadataRefreshRequest: Sendable {
    let samples: [ProcessSample]
    let prompt: [ProcessIdentity: PromptEvidence]
    let requestedAt: Double
}

struct RegistryRefreshRequest: Sendable {
    let provider: AgentProvider
    let query: SessionRegistryQuery
    let samples: [ProcessSample]
}

/// Refresh requests may be superseded; measured counters and prompt observations never enter these mailboxes.
/// Native metadata and provider subprocesses have separate blocking workers so neither delays accounting.
final class PipelineEnrichment: Sendable {
    struct MetadataResult: Sendable {
        let sample: ProcessSample
        let metadata: ProcessMetadata
        let observedAt: Double
        let launchObservedAt: Double?
    }
    struct RegistryResult: Sendable {
        let provider: AgentProvider
        let output: Data?
        let verified: Set<ProcessIdentity>
        let observedAt: Double
    }
    private struct Cache: Sendable {
        var refreshed: [ProcessIdentity: (executable: String, name: String, at: Double)] = [:]
    }
    private struct Results: Sendable {
        var metadata: [ProcessIdentity: MetadataResult] = [:]
        var registry: [AgentProvider: RegistryResult] = [:]
    }
    private struct Admission: Sendable {
        var signatures: [ProcessIdentity: String] = [:]
        var nextRefresh = -Double.infinity
        var stopped = false
    }
    private struct Finished: Error {}
    private let admission = Mutex(Admission())
    private let results = Mutex(Results())
    private let metadata = AsyncStream<MetadataRefreshRequest>.makeStream(
        bufferingPolicy: .bufferingNewest(1))
    private let registries = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private let pendingRegistries = Mutex<[AgentProvider: RegistryRefreshRequest]>([:])

    func requestMetadata(_ request: MetadataRefreshRequest) {
        let admitted = admission.withLock { state in
            guard !state.stopped else { return false }
            var changed = false
            var signatures: [ProcessIdentity: String] = [:]
            for sample in request.samples {
                let signature = sample.executable + "\0" + sample.name
                signatures[sample.identity] = signature
                if state.signatures[sample.identity] != signature { changed = true }
            }
            state.signatures = signatures
            let due = request.requestedAt >= state.nextRefresh
            if due { state.nextRefresh = request.requestedAt + 1 }
            return changed || due
        }
        if admitted { metadata.continuation.yield(request) }
    }
    private func checkFinished() throws {
        if admission.withLock({ $0.stopped }) { throw Finished() }
    }
    func requestRegistries(_ requests: [RegistryRefreshRequest]) {
        guard !requests.isEmpty, !admission.withLock({ $0.stopped }) else { return }
        pendingRegistries.withLock { pending in
            for request in requests { pending[request.provider] = request }
        }
        registries.continuation.yield(())
    }
    func finish() {
        admission.withLock { $0.stopped = true }
        metadata.continuation.finish()
        registries.continuation.finish()
    }
    func takeResults() -> ([MetadataResult], [RegistryResult]) {
        results.withLock { value in
            defer { value = Results() }
            return (Array(value.metadata.values), Array(value.registry.values))
        }
    }

    func refreshMetadata(
        reader: any ProcessReading, clock: any SamplingClock, includeCommand: Bool,
        checking: @escaping @Sendable () throws -> Void
    ) async throws {
        let worker = SerialBlockingWorker(name: "AgentMonitor metadata", initial: Cache())
        do {
            for await request in metadata.stream {
                try checkFinished()
                try checking()
                try await worker.perform { [self] cache in
                    let live = Set(request.samples.map(\.identity))
                    cache.refreshed = cache.refreshed.filter { live.contains($0.key) }
                    results.withLock { $0.metadata = $0.metadata.filter { live.contains($0.key) } }
                    // Prompt capture covers arrivals; the one-second refresh contract must not let
                    // established workers delay changed executables (CPU-01 enrichment review).
                    var urgent: [ProcessSample] = []
                    var due: [ProcessSample] = []
                    for sample in request.samples {
                        if let last = cache.refreshed[sample.identity],
                            last.executable == sample.executable, last.name == sample.name
                        {
                            if request.requestedAt - last.at >= 1 { due.append(sample) }
                        } else {
                            urgent.append(sample)
                        }
                    }
                    for sample in urgent + due {
                        try checkFinished()
                        try checking()
                        let captured = request.prompt[sample.identity].flatMap {
                            evidence -> PromptEvidence? in
                            switch evidence.metadata?.status {
                            case .truncated, .unavailable, .none: nil
                            case .markerRead, .notObserved, .malformed: evidence
                            }
                        }
                        let value = reader.metadata(
                            for: sample, includeCommand: includeCommand, capturedLaunch: captured?.metadata)
                        let observed = clock.monotonicNow()
                        cache.refreshed[sample.identity] = (sample.executable, sample.name, observed)
                        results.withLock {
                            $0.metadata[sample.identity] = MetadataResult(
                                sample: sample, metadata: value, observedAt: observed,
                                launchObservedAt: captured?.observedAt)
                        }
                    }
                }
            }
        } catch is Finished {
            await worker.close()
            return
        } catch {
            await worker.close()
            throw error
        }
        await worker.close()
    }

    func refreshRegistries(
        reader: any ProcessReading, registry: any SessionRegistryReading, clock: any SamplingClock,
        checking: @escaping @Sendable () throws -> Void
    ) async throws {
        let worker = SerialBlockingWorker(name: "AgentMonitor providers", initial: 0)
        let check: @Sendable () throws -> Void = { [self] in
            try checkFinished()
            try checking()
        }
        do {
            for await _ in registries.stream {
                let requests = pendingRegistries.withLock { pending in
                    defer { pending.removeAll() }
                    return Array(pending.values)
                }
                for request in requests {
                    try check()
                    let value = try await worker.perform { _ in
                        try check()
                        let output: Data?
                        do {
                            output = try registry.output(of: request.query, checking: check)
                        } catch is Finished { throw Finished() } catch is CancellationError {
                            throw CancellationError()
                        } catch { output = nil }
                        try check()
                        return RegistryResult(
                            provider: request.provider, output: output,
                            verified: Set(request.samples.filter(reader.isCurrent).map(\.identity)),
                            observedAt: clock.monotonicNow())
                    }
                    results.withLock { $0.registry[request.provider] = value }
                }
            }
        } catch is Finished {
            await worker.close()
            return
        } catch {
            await worker.close()
            throw error
        }
        await worker.close()
    }
}

import Foundation
import Synchronization

struct MetadataRefreshRequest: Sendable {
    let samples: [ProcessSample]
    let prompt: [ProcessIdentity: PromptEvidence]
    let requestedAt: Double
}

/// Refresh requests may be superseded; measured counters and prompt observations never enter these mailboxes.
/// Native metadata uses a separate blocking worker so it cannot delay accounting.
final class PipelineEnrichment: Sendable {
    let profile: PipelineProfile?
    init(profile: PipelineProfile? = nil) { self.profile = profile }

    struct MetadataResult: Sendable {
        let sample: ProcessSample
        let metadata: ProcessMetadata
        let observedAt: Double
        let launchObservedAt: Double?
    }
    struct Cache: Sendable {
        var refreshed: [ProcessIdentity: (execution: ObservedExecution, at: Double)] = [:]
    }
    private struct Admission: Sendable {
        var signatures: [ProcessIdentity: ObservedExecution] = [:]
        var nextRefresh = -Double.infinity
        var stopped = false
    }
    private struct Finished: Error {}
    private let admission = Mutex(Admission())
    private let results = Mutex<[ProcessIdentity: MetadataResult]>([:])
    private let metadata = AsyncStream<MetadataRefreshRequest>.makeStream(
        bufferingPolicy: .bufferingNewest(1))

    func requestMetadata(_ request: MetadataRefreshRequest) {
        let admitted = admission.withLock { state in
            guard !state.stopped else { return false }
            var changed = false
            var signatures: [ProcessIdentity: ObservedExecution] = [:]
            for sample in request.samples {
                var execution = state.signatures[sample.identity] ?? ObservedExecution(sample)
                if execution.update(sample) || state.signatures[sample.identity] == nil { changed = true }
                signatures[sample.identity] = execution
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
    func finish() {
        admission.withLock { $0.stopped = true }
        metadata.continuation.finish()
    }
    func takeResults() -> [MetadataResult] {
        results.withLock { value in
            defer { value = [:] }
            return Array(value.values)
        }
    }

    func refreshMetadata(
        reader: any ProcessReading, clock: any SamplingClock, includeCommand: Bool,
        checking: @escaping @Sendable () throws -> Void
    ) async throws {
        let worker = SerialBlockingWorker(
            name: "AgentMonitor metadata", initial: Cache(), profile: profile, role: .metadata)
        do {
            for await request in metadata.stream {
                try checkFinished()
                try checking()
                try await worker.perform { [self] cache in
                    try profile.measure(.metadataBatch) {
                        try refreshMetadataBatch(
                            request, cache: &cache, reader: reader, clock: clock,
                            includeCommand: includeCommand, checking: checking)
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

    func refreshMetadataBatch(
        _ request: MetadataRefreshRequest, cache: inout Cache,
        reader: any ProcessReading, clock: any SamplingClock, includeCommand: Bool,
        checking: @escaping @Sendable () throws -> Void
    ) throws {
        let live = Set(request.samples.map(\.identity))
        cache.refreshed = cache.refreshed.filter { live.contains($0.key) }
        results.withLock { $0 = $0.filter { live.contains($0.key) } }
        // Prompt capture covers arrivals; the one-second refresh contract must not let
        // established workers delay changed executables (CPU-01 enrichment review).
        var urgent: [ProcessSample] = []
        var due: [ProcessSample] = []
        for sample in request.samples {
            if var last = cache.refreshed[sample.identity] {
                let changed = last.execution.update(sample)
                cache.refreshed[sample.identity] = last
                if changed {
                    urgent.append(sample)
                } else if request.requestedAt - last.at >= 1 {
                    due.append(sample)
                }
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
            cache.refreshed[sample.identity] = (
                cache.refreshed[sample.identity]?.execution ?? ObservedExecution(sample), request.requestedAt
            )
            results.withLock {
                $0[sample.identity] = MetadataResult(
                    sample: sample, metadata: value, observedAt: observed,
                    launchObservedAt: captured?.observedAt)
            }
        }
    }

}

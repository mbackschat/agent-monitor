import Foundation
import Testing

@testable import AgentMonitorCore

private struct ResolutionOracle {
    var cached = Monitor()
    var uncached = Monitor()

    mutating func verify(_ context: String) {
        let rows = cached.accountingFindings(sorted: true)
        #expect(rows == uncached.findings(), "\(context)")
        #expect(
            cached.attributionObservationTimes(for: rows) == uncached.attributionObservationTimes(),
            "\(context)")
    }

    mutating func ingest(_ samples: [ProcessSample], _ context: String) {
        cached.ingest(samples)
        uncached.ingest(samples)
        verify(context)
    }

    mutating func enrich(
        _ identity: ProcessIdentity, _ metadata: ProcessMetadata, at: Double, _ context: String
    ) {
        cached.enrich(metadata, for: identity, observedAt: at)
        uncached.enrich(metadata, for: identity, observedAt: at)
        verify(context)
    }

    mutating func bind(
        _ runtime: ProcessIdentity, session: String?, name: String? = nil, at: Double, _ context: String
    ) throws {
        let entries: [[String: Any]] =
            session.map {
                [
                    [
                        "pid": runtime.pid, "sessionId": $0, "status": "busy", "kind": "interactive",
                        "name": name ?? "",
                    ]
                ]
            } ?? []
        let data = try JSONSerialization.data(withJSONObject: entries)
        cached.bindSessions(data, provider: .claude, observedAt: at)
        uncached.bindSessions(data, provider: .claude, observedAt: at)
        verify(context)
    }
}

enum AncestorChange: CaseIterable {
    case writer, terminal, execution, registryBinding, registryRemoval, reparent
}

@Test(arguments: AncestorChange.allCases)
func cachedResolutionInvalidatesEveryDescendant(change: AncestorChange) throws {
    var oracle = ResolutionOracle()
    var runtime = sample(10, executable: "/bin/claude", terminal: "ttys010")
    let other = sample(11, executable: "/bin/claude", terminal: "ttys011")
    var middle = sample(20, parent: 10)
    let branch = sample(30, parent: 20)
    let leaf = sample(40, parent: 30)
    oracle.ingest([runtime, other, middle, branch, leaf], "warm")
    if change == .registryRemoval {
        try oracle.bind(runtime.identity, session: sessionA, at: 1, "initial binding")
    }
    let before = try #require(oracle.cached.finding(for: leaf.identity))
    runtime.sampledAt = 2
    switch change {
    case .writer:
        oracle.enrich(runtime.identity, ProcessMetadata(writerThreadIDs: [sessionA]), at: 2, "writer")
    case .terminal:
        runtime.terminal = "ttys012"
        oracle.ingest([runtime, other, middle, branch, leaf], "terminal")
    case .execution:
        runtime.executable = "/bin/codex"
        oracle.ingest([runtime, other, middle, branch, leaf], "exec")
    case .registryBinding:
        try oracle.bind(runtime.identity, session: sessionA, at: 2, "bind")
    case .registryRemoval:
        try oracle.bind(runtime.identity, session: nil, at: 2, "unbind")
    case .reparent:
        middle.parentPID = other.identity.pid
        oracle.ingest([runtime, other, middle, branch, leaf], "reparent middle")
    }
    let after = try #require(oracle.uncached.finding(for: leaf.identity))
    #expect(before.attribution != after.attribution)
    #expect(oracle.cached.finding(for: leaf.identity) == after)
}

private struct ResolutionRandom {
    var state: UInt64

    mutating func index(_ count: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int(state >> 32) % count
    }
}

private enum ResolutionOperation: CaseIterable {
    case spawn, exit, miss, reparent, exec, rename, peakReset, reuse
    case marker, socket, writer, invocation, malformed, terminal, bind, unbind, copy
}

@Test(arguments: 0..<200)
func generatedCachedResolutionMatchesUncachedState(seed: Int) throws {
    var random = ResolutionRandom(state: UInt64(seed))
    var oracle = ResolutionOracle()
    var processes: [ProcessSample?] = []
    for index in 0..<12 {
        let parent: Int32 = index < 2 ? 1 : Int32(index == 2 ? 10 : index + 9)
        let executable = index < 2 ? "/bin/claude" : "/bin/worker"
        processes.append(sample(Int32(index + 10), parent: parent, executable: executable))
    }
    oracle.ingest(processes.compactMap { $0 }, "seed \(seed), initial")
    var operations = ResolutionOperation.allCases
    for index in operations.indices.reversed() {
        operations.swapAt(index, random.index(index + 1))
    }
    for step in 0..<50 {
        let operation =
            step < operations.count ? operations[step] : operations[random.index(operations.count)]
        let context = "seed \(seed), step \(step), \(operation)"
        let time = Double(step + 2)
        let worker = 2 + random.index(10)
        let runtime = random.index(2)
        let target = random.index(2) == 0 ? runtime : worker
        let session = random.index(2) == 0 ? sessionA : sessionB
        for index in processes.indices {
            processes[index]?.sampledAt = time
            processes[index]?.cpuSeconds = time / 10
            processes[index]?.footprintBytes = UInt64(100 + step)
        }
        switch operation {
        case .spawn, .reuse:
            processes[worker] = sample(
                Int32(worker + 10), parent: Int32(runtime + 10), start: UInt64(1_000 + step), at: time)
        case .exit:
            processes[worker] = nil
        case .reparent:
            let parent = random.index(worker)
            processes[worker]?.parentPID = Int32(parent + 10)
        case .exec:
            let executable = processes[target]?.executable == "/bin/claude" ? "/bin/codex" : "/bin/claude"
            processes[target]?.executable = executable
        case .rename:
            processes[target]?.name = "execution-\(step)"
        case .peakReset:
            processes[target]?.kernelPeakFootprintBytes = 100
            oracle.ingest(processes.compactMap { $0 }, context + ", before peak reset")
            processes[target]?.kernelPeakFootprintBytes = 10
        case .terminal:
            processes[runtime]?.terminal = random.index(2) == 0 ? nil : "ttys0\(step)"
            processes[runtime]?.terminalDevice = random.index(2) == 0 ? nil : UInt32(step)
        case .miss, .marker, .socket, .writer, .invocation, .malformed, .bind, .unbind, .copy:
            break
        }
        oracle.ingest(processes.compactMap { $0 }, context)
        switch operation {
        case .miss:
            let missing = processes[worker]
            processes[worker] = nil
            oracle.ingest(processes.compactMap { $0 }, context + ", absent scan")
            processes[worker] = missing
            oracle.ingest(processes.compactMap { $0 }, context + ", returned")
        case .marker, .socket, .writer, .invocation, .malformed:
            guard let process = processes[target] else { continue }
            let metadata: ProcessMetadata
            switch operation {
            case .marker:
                metadata = ProcessMetadata(markers: [
                    SessionMarker(threadID: session, provider: .claude, inboxSocket: "/fake/inbox-\(runtime)")
                ])
            case .socket:
                metadata = ProcessMetadata(listeningSockets: ["/fake/inbox-\(runtime)"])
            case .writer:
                metadata = ProcessMetadata(writerThreadIDs: [session])
            case .invocation:
                metadata = ProcessMetadata(invocation: random.index(2) == 0 ? "claude" : "not-an-agent")
            case .malformed:
                metadata = ProcessMetadata(status: .malformed)
            default:
                preconditionFailure("Not a metadata operation")
            }
            oracle.enrich(process.identity, metadata, at: time, context)
        case .bind, .unbind:
            let process = try #require(processes[runtime])
            try oracle.bind(process.identity, session: operation == .bind ? session : nil, at: time, context)
        case .copy:
            let process = try #require(processes[runtime])
            let original = oracle.cached.findings()
            var copy = oracle
            copy.enrich(process.identity, ProcessMetadata(writerThreadIDs: [session]), at: time, context)
            #expect(oracle.cached.findings() == original, "\(context), original copy")
            oracle.verify(context + ", original copy")
        case .spawn, .exit, .reparent, .exec, .rename, .peakReset, .reuse, .terminal:
            break
        }
    }
}

@Test func warmAccountingCacheUsesLatestVerifiedSessionName() throws {
    var oracle = ResolutionOracle()
    let runtime = sample(10, executable: "/bin/claude")
    let worker = sample(20, parent: 10)
    oracle.ingest([runtime, worker], "initial")
    try oracle.bind(runtime.identity, session: sessionA, name: "Original", at: 1, "warm named binding")
    #expect(oracle.cached.accountingFindings().allSatisfy { $0.sessionName == "Original" })
    try oracle.bind(runtime.identity, session: sessionA, name: "Renamed", at: 2, "same owner renamed")
    #expect(oracle.cached.accountingFindings().allSatisfy { $0.sessionName == "Renamed" })
    try oracle.bind(runtime.identity, session: sessionA, at: 3, "name removed")
    #expect(oracle.cached.accountingFindings().allSatisfy { $0.sessionName == nil })
}

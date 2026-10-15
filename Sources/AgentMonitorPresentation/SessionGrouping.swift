import AgentMonitorCore
import Foundation

public enum ReportGrouping: String, Sendable { case none, session }

public enum SessionGroupID: Hashable, Sendable {
    case session(provider: String, id: String)
    case unresolved(ProcessIdentity)
}

public struct SessionGroup: Equatable, Sendable {
    public let id: SessionGroupID
    public let provider: AgentProvider?
    public let sessionID: String?
    public let isRoot: Bool
    public let processes: [HeavyProcess]

    public var cpuTotal: Double? { sum(processes.map(\.cpuPercent)) }
    public var memoryGBTotal: Double? { sum(processes.map { $0.footprintBytes.map { Double($0) / 1e9 } }) }
    public var cpuPartial: Bool { processes.contains { $0.cpuPercent == nil } }
    public var memoryPartial: Bool { processes.contains { $0.footprintBytes == nil } }
    public var minimumPID: Int32 { processes.map(\.process.pid).min() ?? 0 }
    public var project: String {
        let directories = Set(processes.compactMap { $0.attribution.runtimeDirectory ?? $0.cwd })
        guard directories.count == 1, let directory = directories.first else {
            return "multiple/unknown projects"
        }
        return URL(fileURLWithPath: directory).lastPathComponent
    }

    private var isSharedRuntime: Bool {
        processes.count == 1 && processes.first?.isSharedRuntime == true
    }

    var sessionDescription: String {
        sessionID ?? "\(isSharedRuntime ? "shared runtime" : "unresolved") PID \(minimumPID)"
    }

    public var label: String {
        let session = sessionID.map { String($0.prefix(8)) } ?? sessionDescription
        let kind = isSharedRuntime ? "" : (isRoot ? " root" : " session")
        let partial = cpuPartial || memoryPartial ? " | partial totals" : ""
        return
            "\(provider?.rawValue ?? "unknown")/\(session)\(kind) | \(processes.count) heavy | \(project)\(partial)"
    }

    private func sum(_ values: [Double?]) -> Double? {
        let known = values.compactMap { $0 }
        return known.isEmpty ? nil : known.reduce(0, +)
    }
}

public enum SessionGrouping {
    private struct RootEvidence: Hashable {
        let provider: String
        let id: String
        let runtime: ProcessIdentity
    }

    public static func groups(_ findings: [HeavyProcess]) -> [SessionGroup] {
        var seen: Set<ProcessIdentity> = []
        let rows = findings.filter { seen.insert($0.process).inserted }
        let roots = Set(
            rows.compactMap { row -> RootEvidence? in
                let owner = row.attribution
                guard isExact(owner), let provider = owner.provider, let thread = owner.threadID,
                    owner.rootSessionID == thread, let runtime = owner.runtime,
                    owner.context != .unverified
                else { return nil }
                return RootEvidence(provider: provider.rawValue, id: thread, runtime: runtime)
            })
        var order: [SessionGroupID] = []
        var members: [SessionGroupID: [HeavyProcess]] = [:]
        var rootGroups: Set<SessionGroupID> = []
        for row in rows {
            let owner = row.attribution
            let key: SessionGroupID
            if isExact(owner), let provider = owner.provider, let thread = owner.threadID {
                var target = thread
                if let root = owner.rootSessionID, let runtime = owner.runtime,
                    owner.context != .unverified,
                    roots.contains(RootEvidence(provider: provider.rawValue, id: root, runtime: runtime))
                {
                    target = root
                    rootGroups.insert(.session(provider: provider.rawValue, id: root))
                }
                key = .session(provider: provider.rawValue, id: target)
            } else {
                key = .unresolved(row.process)
            }
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(row)
        }
        return order.map { key in
            let processes = members[key] ?? []
            let session: String?
            switch key {
            case .session(_, let id): session = id
            case .unresolved: session = nil
            }
            return SessionGroup(
                id: key, provider: processes.first?.attribution.provider,
                sessionID: session, isRoot: rootGroups.contains(key), processes: processes)
        }
    }

    private static func isExact(_ owner: Attribution) -> Bool {
        switch owner.evidence {
        case .marker, .inheritedMarker, .writerLock: true
        case .unknown, .ambiguous, .runtimeOnly: false
        }
    }
}

public enum LiveReportRowID: Hashable, Sendable {
    case process(ProcessIdentity)
    case group(SessionGroupID)
}

public enum LiveReportRow: Equatable, Sendable {
    case process(HeavyProcess)
    case group(SessionGroup)

    public var id: LiveReportRowID {
        switch self {
        case .process(let row): .process(row.process)
        case .group(let group): .group(group.id)
        }
    }
}

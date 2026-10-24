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

    public func containsDisplayedProcess(in identities: Set<ProcessIdentity>) -> Bool {
        processes.contains { identities.contains($0.process) }
    }

    public var cpuTotal: Double? { sum(processes.map(\.cpuPercent)) }
    public var memoryGBTotal: Double? {
        let current = processes.filter { !$0.isHistorical }
        return current.isEmpty ? 0 : sum(current.map { $0.footprintBytes.map { Double($0) / 1e9 } })
    }
    public var cpuPartial: Bool { processes.contains { $0.cpuPercent == nil } }
    public var memoryPartial: Bool { processes.contains { !$0.isHistorical && $0.footprintBytes == nil } }
    public var minimumPID: Int32 { processes.map(\.process.pid).min() ?? 0 }
    public var project: String {
        if isSharedRuntime { return "Shared runtime" }
        let workloads = processes.filter { $0.process != $0.attribution.runtime }
        let members = workloads.isEmpty ? processes : workloads
        let directories = Set(members.compactMap(\.cwd))
        if directories.count > 1 { return "Multiple directories" }
        guard members.allSatisfy({ $0.cwd != nil }), let directory = directories.first else {
            return "Unknown project"
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
        let evidence =
            processes.contains { $0.accounting != nil }
            ? (sessionID == nil ? " | uncertain CPU" : " | point-candidate CPU") : ""
        let partial = cpuPartial || memoryPartial ? " | partial totals" : ""
        return
            "\(provider?.rawValue ?? "unknown")/\(session)\(kind) | \(processes.count) observed | \(project)\(partial)\(evidence)"
    }

    private func sum(_ values: [Double?]) -> Double? {
        let known = values.compactMap { $0 }
        return known.isEmpty ? nil : known.reduce(0, +)
    }
}

public enum SessionGrouping {
    public static func groups(_ findings: [HeavyProcess]) -> [SessionGroup] {
        var seen: Set<ProcessIdentity> = []
        let rows = findings.filter { seen.insert($0.process).inserted }
        let roots = SessionCorroboration(rows)
        var order: [SessionGroupID] = []
        var members: [SessionGroupID: [HeavyProcess]] = [:]
        var rootGroups: Set<SessionGroupID> = []
        for row in rows {
            let owner = row.attribution
            let key: SessionGroupID
            if SessionCorroboration.isExact(owner), let provider = owner.provider, let thread = owner.threadID
            {
                var target = thread
                if let root = roots.root(for: owner) {
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

}

public enum LiveReportRowID: Hashable, Sendable {
    case process(ProcessIdentity)
    case group(SessionGroupID)
}

public enum LiveReportRow: Equatable, Sendable {
    case process(HeavyProcess)
    case group(SessionGroup)
    case unavailable(ReportPin)

    public var id: LiveReportRowID {
        switch self {
        case .process(let row): .process(row.process)
        case .group(let group): .group(group.id)
        case .unavailable(let pin): pin.id
        }
    }
}

public struct ReportPin: Equatable, Sendable {
    public let id: LiveReportRowID
    public let label: String
}

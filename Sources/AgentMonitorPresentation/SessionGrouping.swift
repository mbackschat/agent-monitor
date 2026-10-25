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
    public let contributingProcesses: Set<ProcessIdentity>
    public let labelChangedInWindow: Bool
    fileprivate let windowCPU: Double?
    fileprivate let hasWindow: Bool
    public var observedCount: Int { contributingProcesses.count }
    public var canFlatten: Bool { processes.count == 1 && observedCount == 1 && !labelChangedInWindow }

    public func containsDisplayedProcess(in identities: Set<ProcessIdentity>) -> Bool {
        !contributingProcesses.isDisjoint(with: identities)
    }

    public var cpuTotal: Double? { hasWindow ? windowCPU : sum(processes.map(\.cpuPercent)) }
    public var memoryGBTotal: Double? {
        let current = processes.filter { !$0.isHistorical }
        return current.isEmpty ? 0 : sum(current.map { $0.footprintBytes.map { Double($0) / 1e9 } })
    }
    public var cpuPartial: Bool { processes.contains { $0.cpuPercent == nil } }
    public var memoryPartial: Bool { processes.contains { !$0.isHistorical && $0.footprintBytes == nil } }
    public var minimumPID: Int32 { contributingProcesses.map(\.pid).min() ?? 0 }
    public var project: String {
        if isSharedRuntime { return "Shared runtime" }
        let workloads = processes.filter { $0.process != $0.attribution.runtime }
        let members = workloads.isEmpty ? processes : workloads
        return ProjectLabel.make(members.map(\.cwd))
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
            hasWindow || processes.contains { $0.accounting != nil }
            ? (sessionID == nil ? " | uncertain CPU" : " | point-candidate CPU") : ""
        let partial = cpuPartial || memoryPartial ? " | partial totals" : ""
        let changed = labelChangedInWindow ? " | Label changed in window" : ""
        return
            "\(provider?.rawValue ?? "unknown")/\(session)\(kind) | \(observedCount) observed | \(project)\(partial)\(evidence)\(changed)"
    }

    private func sum(_ values: [Double?]) -> Double? {
        let known = values.compactMap { $0 }
        return known.isEmpty ? nil : known.reduce(0, +)
    }
}

public enum SessionGrouping {
    public static func groups(_ findings: [HeavyProcess], window: ReportWindowSummary? = nil)
        -> [SessionGroup]
    {
        var seen: Set<ProcessIdentity> = []
        let rows = findings.filter { seen.insert($0.process).inserted }
        let roots = SessionCorroboration(rows)
        var order: [SessionGroupID] = []
        var members: [SessionGroupID: [HeavyProcess]] = [:]
        var contributors: [SessionGroupID: Set<ProcessIdentity>] = [:]
        var providers: [SessionGroupID: AgentProvider] = [:]
        var cpu: [SessionGroupID: Double] = [:]
        var rootGroups: Set<SessionGroupID> = []
        var changedGroups: Set<SessionGroupID> = []
        let changed = Set(rows.filter { $0.accounting?.labelChangedInWindow == true }.map(\.process))
        func admit(_ owner: Attribution, process: ProcessIdentity, root: String?) -> SessionGroupID {
            let key: SessionGroupID
            if SessionCorroboration.isExact(owner), let provider = owner.provider, let thread = owner.threadID
            {
                key = .session(provider: provider.rawValue, id: root ?? thread)
                if root != nil { rootGroups.insert(key) }
            } else {
                key = .unresolved(process)
            }
            if contributors[key] == nil { order.append(key) }
            contributors[key, default: []].insert(process)
            if let provider = owner.provider { providers[key] = provider }
            if changed.contains(process) { changedGroups.insert(key) }
            return key
        }
        for row in rows {
            let root =
                row.accounting.map { $0.lastObservedCorroboratedRootSessionID }
                ?? roots.root(for: row.attribution)
            let key = admit(row.attribution, process: row.process, root: root)
            members[key, default: []].append(row)
        }
        if let window, window.durationSeconds > 0 {
            for record in window.contributions
            where seen.contains(record.process)
                && record.openingScan >= window.baselineScan
            {
                let key = admit(
                    record.attribution, process: record.process, root: record.corroboratedRootSessionID)
                cpu[key, default: 0] += 100 * record.cpuSeconds / window.durationSeconds
            }
        }
        return order.map { key in
            let session: String?
            switch key {
            case .session(_, let id): session = id
            case .unresolved: session = nil
            }
            return SessionGroup(
                id: key, provider: providers[key], sessionID: session,
                isRoot: rootGroups.contains(key), processes: members[key] ?? [],
                contributingProcesses: contributors[key] ?? [],
                labelChangedInWindow: changedGroups.contains(key),
                windowCPU: cpu[key], hasWindow: window != nil)
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

enum ProjectLabel {
    static func make(_ directories: [String?]) -> String {
        let known = Set(directories.compactMap { $0 })
        if known.count > 1 { return "Multiple directories" }
        guard directories.allSatisfy({ $0 != nil }), let directory = known.first else {
            return "Unknown project"
        }
        return directory.split(separator: "/").last.map(String.init) ?? "/"
    }
}

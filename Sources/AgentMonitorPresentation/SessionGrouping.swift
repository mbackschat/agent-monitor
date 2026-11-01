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
        return directorySummary
    }

    public let workloadDirectories: Set<String?>
    fileprivate let directorySummary: String

    public var heading: String {
        headingLabel.title
    }

    public var headingLabel: ContributorLabel {
        let provider = provider?.rawValue ?? "unknown"
        guard let sessionID else {
            return .text("\(provider) · \(sessionDescription) · \(project)")
        }
        return .session(owner: provider, id: String(sessionID.prefix(8)), directory: project)
    }

    public var headingHelp: String {
        (["\(provider?.rawValue ?? "unknown")/\(sessionDescription)"]
            + workloadDirectories.compactMap { $0 }.sorted()
            + (workloadDirectories.contains(nil) ? ["CWD unavailable"] : [])).joined(separator: "\n")
    }

    private var isSharedRuntime: Bool {
        processes.count == 1 && processes.first?.isSharedRuntime == true
    }

    var sessionDescription: String {
        sessionID ?? "\(isSharedRuntime ? "shared runtime" : "unresolved") PID \(minimumPID)"
    }

    public var label: String { labelRuns.map(\.text).joined() }

    var labelRuns: [ReportLine.Run] {
        let session = sessionID.map { String($0.prefix(8)) } ?? sessionDescription
        let kind = isSharedRuntime ? "" : (isRoot ? " root" : " session")
        let evidence =
            hasWindow || processes.contains { $0.accounting != nil }
            ? (sessionID == nil ? " | uncertain CPU" : " | point-candidate CPU") : ""
        let partial = cpuPartial || memoryPartial ? " | partial totals" : ""
        let changed = labelChangedInWindow ? " | Label changed in window" : ""
        return [
            .init("\(provider?.rawValue ?? "unknown")/\(session)\(kind)", style: .identity),
            .init(" | \(observedCount) \(observedCount == 1 ? "process" : "processes") | \(project)"),
            .init(partial, style: .warning),
            .init(evidence, style: sessionID == nil ? .warning : .normal),
            .init(changed, style: .warning),
        ]
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
        let directories = members.mapValues { processes in
            let workloads = processes.filter { $0.process != $0.attribution.runtime }
            return Set((workloads.isEmpty ? processes : workloads).map(\.cwd))
        }
        let labels = WorkloadDirectory.compactLabels(
            for: Set(directories.values.flatMap { $0.compactMap { $0 } }))
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
                windowCPU: cpu[key], hasWindow: window != nil,
                workloadDirectories: directories[key] ?? [],
                directorySummary: WorkloadDirectory.summary(directories[key] ?? [], labels: labels))
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

/// Compact workload-directory labels; full paths stay in details (product contract: compact,
/// distinguishable paths with the full path on access).
enum WorkloadDirectory {
    /// Abbreviates the home directory and keeps the last two components of deeper paths.
    static func compact(_ path: String, home: String = NSHomeDirectory()) -> String {
        compact(path, home: home, suffixComponents: 2)
    }

    /// The product contract requires distinguishable workload paths, so matching suffixes gain
    /// leading components until each label identifies one observed directory.
    static func compactLabels(for paths: Set<String>, home: String = NSHomeDirectory()) -> [String: String] {
        var result: [String: String] = [:]
        var remaining = paths
        let maximumComponents = max(2, paths.map { $0.split(separator: "/").count }.max() ?? 0)
        for suffixComponents in 2...maximumComponents {
            guard !remaining.isEmpty else { break }
            let groups = Dictionary(grouping: remaining) {
                compact($0, home: home, suffixComponents: suffixComponents)
            }
            remaining = []
            for (label, members) in groups {
                if members.count == 1, let path = members.first {
                    result[path] = label
                } else {
                    remaining.formUnion(members)
                }
            }
        }
        for path in remaining { result[path] = path }
        return result
    }

    private static func compact(_ path: String, home: String, suffixComponents: Int) -> String {
        let relative =
            path == home || path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        let components = relative.split(separator: "/", omittingEmptySubsequences: true)
        let leading = relative.hasPrefix("~") ? 1 : 0
        guard components.count - leading > suffixComponents else { return relative }
        return "…/" + components.suffix(suffixComponents).joined(separator: "/")
    }

    /// One directory by path, several by count; an unreadable directory stays disclosed.
    static func summary(_ directories: Set<String?>, labels: [String: String] = [:]) -> String {
        let known = directories.compactMap { $0 }
        let base: String
        switch known.count {
        case 0: return "CWD unavailable"
        case 1: base = labels[known[0]] ?? compact(known[0])
        default: base = "\(known.count) dirs"
        }
        return directories.contains(nil) ? base + " + CWD unavailable" : base
    }
}

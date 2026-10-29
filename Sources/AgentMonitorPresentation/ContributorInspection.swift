import AgentMonitorCore
import Foundation

public enum ContributorLabel: Equatable, Sendable {
    case text(String)
    case session(identity: String, directory: String?)
    case workload(name: String, directory: String?)

    public var headline: String {
        switch self {
        case .text(let title): title
        case .session(let identity, _): identity
        case .workload(let name, _): name
        }
    }

    public var title: String {
        switch self {
        case .text(let text): text
        case .session(let identity, let directory):
            ([identity] + [directory].compactMap { $0 }).joined(separator: " · ")
        case .workload(let name, let directory):
            ([name] + [directory].compactMap { $0 }).joined(separator: " · ")
        }
    }
}

public struct ContributorNode: Equatable, Sendable, Identifiable {
    public let id: ContributorID
    public var label: ContributorLabel
    public var title: String { label.title }
    public var stats = ContributorStats()
    public var children: [ContributorID] = []
    var labels: [InspectionField] = []
    var evidence: [ContributorEvidence] = []

    init(id: ContributorID, title: String) {
        self.id = id
        label = .text(title)
    }

    public var ownerHeadline: String {
        func session(_ id: ContributorID) -> String? {
            switch id {
            case .session(let provider, let session, _): provider + " · " + session.prefix(8)
            case .executable(let parent, _, _), .more(let parent), .process(let parent, _),
                .provider(let parent, _):
                session(parent)
            case .section, .collapsed: nil
            }
        }
        return session(id) ?? label.headline
    }

    public var populationFields: [InspectionField] {
        [
            InspectionField(
                "Processes now", stats.currentAvailable ? String(stats.current.count) : "Unavailable"),
            InspectionField("Recent workers", stats.workerCountText),
            InspectionField(
                "No longer observed",
                stats.currentAvailable ? String(stats.noLongerObserved.count) : "Unavailable",
                help: "Absence is not confirmed termination."),
            InspectionField("Agent runtimes", String(stats.runtimes.count)),
            InspectionField("Filtered members", String(stats.filtered.count)),
        ]
    }
    public var inspectionFields: [InspectionField] { labels + evidence.flatMap(\.fields) }
    public var details: [String] { inspectionFields.map(\.text) }
    public var process: ProcessIdentity?
    public func summary(duration: Double) -> String {
        func candidate(_ id: ContributorID) -> Bool {
            switch id {
            case .session: true
            case .executable(let parent, _, _), .more(let parent), .process(let parent, _): candidate(parent)
            case .section, .provider, .collapsed: false
            }
        }
        return stats.summary(duration: duration, cpuLabel: candidate(id) ? "Candidate CPU" : "CPU")
    }
}

public struct InspectionField: Equatable, Sendable {
    public enum Kind: Sendable { case context, evidence }
    public let kind: Kind
    public let label: String
    public let value: String
    public let help: String?

    public init(_ label: String, _ value: String, kind: Kind = .context, help: String? = nil) {
        self.kind = kind
        self.label = label
        self.value = value
        self.help = help
    }
    public var text: String { label + ": " + value }

    static func terminalLines(_ fields: [Self], width: Int) -> [String] {
        let labelWidth = min(width / 3, fields.map { TerminalCells.width($0.label) + 1 }.max() ?? 0)
        return fields.flatMap { field in
            let label = TerminalCells.padded(
                TerminalCells.abbreviated(TextReport.safe(field.label + ":"), to: labelWidth), to: labelWidth)
            let values = TerminalCells.wrapped(
                TextReport.safe(field.value), to: max(1, width - labelWidth - 1))
            return values.enumerated().map {
                ($0.offset == 0 ? label : String(repeating: " ", count: labelWidth)) + " " + $0.element
            }
        }
    }

    static func collapsed(_ value: CollapsedContribution, window: String) -> [Self] {
        var fields = [
            Self(
                window, String(format: "%.2f–%.2f s", value.startedAt, value.endedAt),
                help: "Acquisition-run monotonic time."),
            Self("CPU", String(format: "%.2f CPU-s", value.cpuSeconds)),
            Self(
                "Intervals",
                "\(value.intervalCount) accepted · \(value.missingReadIntervalCount) with missing reads"),
            Self("Processes / workers", "\(value.processCount.text) / \(value.workerCount.text)"),
            Self(
                "Released detail",
                value.category.categoryDetailsRetained
                    ? "Individual identities and directories" : "Identities, directories and category labels"),
        ]
        if let peak = value.maximumFootprint { fields.append(Self("Sampled maximum", memory(peak))) }
        return fields
    }
}

struct ContributorEvidence: Equatable, Sendable {
    let record: RecentWorkerRecord
    let stats: ContributorStats
    let first: Double?
    let peak: RecentMemoryReading?
    let currentAvailable: Bool
    let present: Bool
    let changes: Int
    let evidence: Set<String>

    var fields: [InspectionField] {
        let key = record.category
        let state =
            currentAvailable
            ? (present
                ? (stats.current.isEmpty
                    ? "Observed elsewhere; membership changed" : "Observed in final scan")
                : "No longer observed; exit unconfirmed") : "Final-scan presence unavailable"
        var fields = [
            InspectionField("Agent", key.owner.provider?.rawValue ?? "Unresolved"),
            InspectionField("Session", key.owner.sessionID ?? "Unresolved"),
            InspectionField("Directory", record.cwd ?? "Unavailable"),
            InspectionField("Executable", key.executable),
            InspectionField("Lifetime", "PID \(key.process.pid), start µs \(key.process.startMicroseconds)"),
            InspectionField("State", state),
            InspectionField(
                "Role", key.isAgentRuntime ? "Adapter-recognised agent runtime" : "Worker", kind: .evidence),
            InspectionField(
                "First / last seen",
                String(format: "%.1f–%.1f s", first ?? record.firstObservedAt, record.lastObservedAt),
                kind: .evidence, help: "Acquisition-run monotonic time."),
            InspectionField("Ownership", key.owner.resolution.rawValue, kind: .evidence),
            InspectionField("Evidence", evidence.sorted().joined(separator: ", "), kind: .evidence),
            InspectionField("Frozen root", key.owner.rootSessionID ?? "Not corroborated", kind: .evidence),
            InspectionField("Membership changes", String(stats.membershipChanged.count), kind: .evidence),
            InspectionField(
                "Intervals", "\(stats.recentMeasurements) accepted · \(stats.exclusions) excluded",
                kind: .evidence),
        ]
        if let name = key.invocationName { fields.insert(InspectionField("Invoked as", name), at: 4) }
        if let maximum = stats.maximumWorkerFootprint {
            fields.append(InspectionField("Sampled maximum", memory(maximum), kind: .evidence))
        }
        if let peak {
            fields.append(
                InspectionField(
                    "Kernel task peak",
                    memory(peak) + (record.kernelPeakUnavailable ? " · later unavailable" : ""),
                    kind: .evidence))
            fields.append(
                InspectionField(
                    "Peak epoch", "Unverified; may predate this range or reset on exec", kind: .evidence))
        }
        if !key.owner.candidates.isEmpty {
            fields.append(
                InspectionField(
                    "Conflicting candidates", key.owner.candidates.joined(separator: ", "), kind: .evidence))
        }
        if changes > 0 {
            fields.append(
                InspectionField(
                    "Exec-spanning intervals", "\(changes) · exec time unverified", kind: .evidence))
        }
        if let command = record.command {
            fields += command.enumerated().map { InspectionField("Argument \($0.offset)", $0.element) }
        }
        return fields
    }
}

private func memory(_ reading: RecentMemoryReading) -> String {
    String(format: "%.1f MB at %.1f s", Double(reading.bytes) / 1e6, reading.observedAt)
        + " · scan \(reading.scan) · \(reading.evidence.rawValue)"
}

public enum ContributorWorkloadPart: Equatable, Sendable {
    case executable(String)
    case context(String)

    public var text: String {
        switch self {
        case .executable(let value), .context(let value): value
        }
    }
}

extension ContributorOverview {
    public func workloadContext(for node: ContributorNode) -> String {
        workloadParts(for: node).map(\.text).joined()
    }

    public func workloadParts(for node: ContributorNode) -> [ContributorWorkloadPart] {
        var workloads: [ContributorNode] = []
        func collect(_ id: ContributorID) {
            guard let child = nodes[id] else { return }
            if case .executable = id {
                workloads.append(child)
                return
            }
            for id in child.children { collect(id) }
        }
        func retainedContext(_ value: [ContributorWorkloadPart]) -> [ContributorWorkloadPart] {
            guard node.stats.current.isEmpty, node.stats.hasContributions else { return value }
            let presence: String
            if !node.stats.currentAvailable {
                presence = "Current presence unavailable"
            } else if !node.stats.noLongerObserved.isEmpty {
                presence = "No longer observed"
            } else {
                presence = "Observed elsewhere"
            }
            return value + [.context(" · " + presence + " · Recent CPU " + node.stats.recentCPUText)]
        }
        switch node.id {
        case .session:
            collect(node.id)
            let labels = workloadDirectoryLabels
            var context: [ContributorWorkloadPart] = []
            for child in workloads.prefix(3) {
                if !context.isEmpty { context.append(.context("  +  ")) }
                if case .executable(_, let name, let cwd) = child.id {
                    context.append(.executable(name))
                    context.append(
                        .context(
                            " · " + (cwd.map { labels[$0] ?? $0 } ?? "CWD unavailable") + " "
                                + child.stats.cpuText(duration: duration)))
                } else {
                    context.append(.context(child.label.headline))
                }
            }
            if workloads.count > 3 { context.append(.context("  +\(workloads.count - 3) more workloads")) }
            if !context.isEmpty { return retainedContext(context) }
        case .executable(_, _, let cwd): return retainedContext([.context(cwd ?? "CWD unavailable")])
        case .process:
            return retainedContext([
                .context(
                    node.inspectionFields.first { $0.label == "Directory" }?.value ?? "CWD unavailable")
            ])
        case .section, .provider, .more, .collapsed: break
        }
        let population =
            node.stats.currentAvailable
            ? "\(node.stats.current.count) processes" : "Current presence unavailable"
        let departed =
            node.stats.noLongerObserved.isEmpty
            ? "" : " · \(node.stats.noLongerObserved.count) no longer observed"
        let released =
            node.stats.collapsedWorkers == nil ? "" : " · \(node.stats.workerCountText) observed workers"
        return [.context(population + departed + released + " · Recent CPU " + node.stats.recentCPUText)]
    }
}

extension ContributorStats {
    public var currentMemoryText: String {
        currentAvailable && !current.isEmpty ? memoryText : "—"
    }
}

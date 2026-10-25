import AgentMonitorCore
import AgentMonitorPresentation

/// One lookup per displayed projection avoids rebuilding the whole table for every row command.
/// See the 2026-10-24 stack sample in docs/research/menu-bar-load-cost.md.
final class MenuBarRowIndex {
    let projection: ReportProjection
    let processes: [ProcessIdentity: HeavyProcess]
    let sessions: [ProcessIdentity: SessionGroup]
    let visibleIDs: [LiveReportRowID]
    let visible: Set<LiveReportRowID>
    let groupFocusTargets: [SessionGroupID: HeavyProcess]

    init(state: LiveReportState) {
        let projection = state.projection
        self.projection = projection
        processes = Dictionary(
            uniqueKeysWithValues: (state.snapshot?.findings ?? []).map { ($0.process, $0) })
        sessions = Dictionary(
            uniqueKeysWithValues: projection.groups.flatMap { group in
                group.processes.map { ($0.process, group) }
            })
        let pinned = Set(state.pins.map(\.id))
        visibleIDs = (projection.pinnedRows + projection.unpinnedRows).flatMap { row in
            switch row {
            case .group(let group):
                let children = projection.childrenByGroup[group.id] ?? []
                if !pinned.contains(row.id), group.canFlatten, let process = children.first {
                    return [LiveReportRowID.process(process.process)]
                }
                return [row.id]
                    + (state.openGroups.contains(group.id) ? children.map { .process($0.process) } : [])
            case .process, .unavailable: return [row.id]
            }
        }
        visible = Set(visibleIDs)
        groupFocusTargets = Dictionary(
            uniqueKeysWithValues: projection.groups.compactMap { group in
                guard
                    Set(group.processes.filter { !$0.isHistorical }.compactMap(\.attribution.runtime)).count
                        == 1,
                    let process = group.processes.first(where: {
                        !$0.isHistorical && $0.attribution.runtime != nil
                    })
                else { return nil }
                return (group.id, process)
            })
    }

    static func needsUpdate(from old: LiveReportState, to new: LiveReportState) -> Bool {
        old.updates != new.updates || old.snapshot != new.snapshot
            || old.grouping != new.grouping || old.sortKey != new.sortKey || old.ascending != new.ascending
            || old.openGroups != new.openGroups || old.pins != new.pins
    }
}

import AgentMonitorCore

extension LiveReportState {
    public func isPinned(_ id: LiveReportRowID) -> Bool { pins.contains { $0.id == id } }

    public var pinnedRows: [LiveReportRow] { projection.pinnedRows }
    public var unpinnedRows: [LiveReportRow] { projection.unpinnedRows }

    public var projection: ReportProjection {
        let processes = rows
        let sessions = groups
        let pinned: [LiveReportRow] = pins.map { pin in
            switch pin.id {
            case .process(let identity):
                return processes.first { $0.process == identity }.map(LiveReportRow.process)
                    ?? .unavailable(pin)
            case .group(let id):
                return sessions.first { $0.id == id }.map(LiveReportRow.group) ?? .unavailable(pin)
            }
        }
        let unpinned: [LiveReportRow]
        switch grouping {
        case .none:
            let grouped = Set(
                sessions.filter { isPinned(.group($0.id)) }.flatMap { $0.processes.map(\.process) })
            unpinned = processes.filter { !isPinned(.process($0.process)) && !grouped.contains($0.process) }
                .map(LiveReportRow.process)
        case .session:
            unpinned = sessions.filter {
                !isPinned(.group($0.id)) && $0.processes.contains { !isPinned(.process($0.process)) }
            }.map(LiveReportRow.group)
        }
        return ReportProjection(groups: sessions, pinnedRows: pinned, unpinnedRows: unpinned)
    }

    public func children(of group: SessionGroup) -> [HeavyProcess] {
        let children = group.processes.filter { !isPinned(.process($0.process)) }
        guard isPinned(.group(group.id)) else { return children }
        return children.sorted {
            if $0.process.pid != $1.process.pid { return $0.process.pid < $1.process.pid }
            return $0.process.startMicroseconds < $1.process.startMicroseconds
        }
    }
}

public struct ReportProjection: Sendable {
    public let groups: [SessionGroup]
    public let pinnedRows: [LiveReportRow]
    public let unpinnedRows: [LiveReportRow]
}

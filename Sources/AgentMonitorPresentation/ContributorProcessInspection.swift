import AgentMonitorCore

extension LiveReportState {
    public func contributorProcesses(for id: ContributorID) -> [HeavyProcess] {
        guard showsOverview, overview.visibleRows.contains(where: { $0.id == id }),
            let node = overview.nodes[id], node.stats.currentAvailable
        else { return [] }
        return (snapshot?.observedFindings ?? []).filter {
            !$0.isHistorical && node.stats.current.contains($0.process)
        }.sorted { $0.process.pid < $1.process.pid }
    }

    public var contributorProcessTarget: HeavyProcess? {
        guard overview.detailsVisible, let id = overview.selection,
            let identity = overview.inspectedProcess
        else { return nil }
        return contributorProcesses(for: id).first { $0.process == identity }
    }

    public mutating func inspectContributorProcess(_ identity: ProcessIdentity, contributor: ContributorID) {
        guard actionPanel == nil, !diagnosis.isVisible,
            contributorProcesses(for: contributor).contains(where: { $0.process == identity })
        else { return }
        overview.inspectProcess(identity, contributor: contributor)
    }

}

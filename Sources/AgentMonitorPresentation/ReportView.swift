public enum ReportView: CaseIterable, Sendable {
    case mainContributors, allContributors, sessions, processes

    public var isOverview: Bool {
        switch self {
        case .mainContributors, .allContributors: true
        case .sessions, .processes: false
        }
    }
}

extension LiveReportState {
    public var canSelectOverview: Bool { snapshot == nil || snapshot?.recentActivity != nil }

    public var view: ReportView {
        get {
            if overview.enabled, canSelectOverview {
                return overview.showAll ? .allContributors : .mainContributors
            }
            return grouping == .session ? .sessions : .processes
        }
        set {
            switch newValue {
            case .mainContributors, .allContributors:
                overview.enabled = true
                overview.showAll = newValue == .allContributors
            case .sessions, .processes:
                overview.enabled = false
                let target: ReportGrouping = newValue == .sessions ? .session : .none
                if grouping != target { toggleGrouping() }
            }
        }
    }

    public func title(for view: ReportView) -> String {
        switch view {
        case .mainContributors: overview.mainTitle
        case .allContributors: overview.allTitle
        case .sessions: "Processes by session"
        case .processes: "Processes"
        }
    }

    public mutating func sortCurrentView(by key: ReportSort) {
        guard view.isOverview else {
            if sortKey != key { sort(by: key) }
            return
        }
        let order: ContributorOrder
        switch key {
        case .stable: order = .stable
        case .cpu: order = .cpu
        case .memory: order = .memory
        case .pid: return
        }
        overview.sort(by: order, ascending: overview.order == order ? overview.ascending : false)
    }

    public mutating func reverseCurrentSort() {
        if view.isOverview {
            guard overview.order != .stable else { return }
            overview.sort(by: overview.order, ascending: !overview.ascending)
        } else {
            reverseSort()
        }
    }
}

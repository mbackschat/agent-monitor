/// Browsing controls shared by native and terminal hosts; text entry and action confirmation stay local.
public enum ReportShortcut: String, CaseIterable, Sendable {
    case foldPinned = "5"
    case foldSessions = "6"
    case foldOther = "7"
    case foldTable = "8"
    case overview = "v"
    case allContributors = "a"
    case pause = "p"
    case pin = "."
    case unpinAll = "u"
    case stable = "o"
    case cpu = "c"
    case memory = "m"
    case pid = "n"
    case reverse = "r"
    case grouping = "g"
    case cpuDown = "1"
    case cpuUp = "2"
    case memoryDown = "3"
    case memoryUp = "4"
    case historyMetric = "h"
    case historyWindow = "t"
    case chartRange = "b"
    case slower = "<"
    case faster = ">"
}

extension LiveReportState {
    public mutating func apply(_ shortcut: ReportShortcut) {
        guard actionPanel == nil, referencePage == nil else { return }
        switch shortcut {
        case .foldPinned, .foldSessions, .foldOther, .foldTable:
            guard showsOverview else { return }
            switch shortcut {
            case .foldPinned: overview.toggleSection(.pinned)
            case .foldSessions: overview.toggleSection(.sessions)
            case .foldOther: overview.toggleSection(.other)
            default: overview.toggleTable()
            }
        case .overview:
            let wasEnabled = overview.enabled
            if showsOverview { inspectOverviewProcess() }
            overview.enabled = !wasEnabled
        case .allContributors:
            view = view == .allContributors ? .mainContributors : .allContributors
        case .pause: toggleFreeze()
        case .pin: toggleSelectedPin()
        case .unpinAll: unpinAll()
        case .stable: sortCurrentView(by: .stable)
        case .cpu: sortCurrentView(by: .cpu)
        case .memory: sortCurrentView(by: .memory)
        case .pid: sortCurrentView(by: .pid)
        case .reverse: reverseCurrentSort()
        case .grouping:
            overview.enabled = false
            toggleGrouping()
        case .cpuDown: adjustThreshold(.cpuDown)
        case .cpuUp: adjustThreshold(.cpuUp)
        case .memoryDown: adjustThreshold(.memoryDown)
        case .memoryUp: adjustThreshold(.memoryUp)
        case .historyMetric: historyMetric = historyMetric.next
        case .historyWindow: historyWindow = historyWindow.next
        case .chartRange:
            if view.isOverview { overview.cycleChartRange() }
        case .slower: adjustInterval(.slower)
        case .faster: adjustInterval(.faster)
        }
    }
}

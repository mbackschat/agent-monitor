/// Browsing controls shared by native and terminal hosts; text entry and action confirmation stay local.
public enum ReportShortcut: String, CaseIterable, Sendable {
    case pause = "p"
    case pin = " "
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
    case slower = "<"
    case faster = ">"
}

extension LiveReportState {
    public mutating func apply(_ shortcut: ReportShortcut) {
        guard actionPanel == nil else { return }
        switch shortcut {
        case .pause: toggleFreeze()
        case .pin: toggleSelectedPin()
        case .stable: sort(by: .stable)
        case .cpu: sort(by: .cpu)
        case .memory: sort(by: .memory)
        case .pid: sort(by: .pid)
        case .reverse: reverseSort()
        case .grouping: toggleGrouping()
        case .cpuDown: adjustThreshold(.cpuDown)
        case .cpuUp: adjustThreshold(.cpuUp)
        case .memoryDown: adjustThreshold(.memoryDown)
        case .memoryUp: adjustThreshold(.memoryUp)
        case .historyMetric: historyMetric = historyMetric.next
        case .historyWindow: historyWindow = historyWindow.next
        case .slower: adjustInterval(.slower)
        case .faster: adjustInterval(.faster)
        }
    }
}

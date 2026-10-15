import AgentMonitorCore
import AgentMonitorPresentation

struct MenuBarArrivals {
    private var previous: Set<LiveReportRowID>?
    private(set) var deadlines: [LiveReportRowID: ContinuousClock.Instant] = [:]

    mutating func update(_ snapshot: MonitoringSnapshot?, now: ContinuousClock.Instant) {
        guard let snapshot else {
            self = Self()
            return
        }
        let processes = snapshot.findings.map { LiveReportRowID.process($0.process) }
        let sessions = SessionGrouping.groups(snapshot.findings)
        let groups = sessions.map { LiveReportRowID.group($0.id) }
        let current = Set(processes + groups)
        expire(at: now)
        deadlines = deadlines.filter { current.contains($0.key) }
        if let previous {
            let added = current.subtracting(previous)
            for id in added { deadlines[id] = now + .seconds(3) }
            for group in sessions
            where group.processes.contains(where: { added.contains(.process($0.process)) }) {
                deadlines[.group(group.id)] = now + .seconds(3)
            }
        }
        previous = current
    }

    mutating func expire(at now: ContinuousClock.Instant) {
        deadlines = deadlines.filter { $0.value > now }
    }
}

import AgentMonitorCore
import AgentMonitorPresentation
import Foundation

enum MenuBarCollection {
    static func source(
        reader: @escaping @Sendable () throws -> any ProcessReading = { try NativeProcessReader() },
        clock: any AcquisitionClock = ContinuousSamplingClock(),
        excluding: Set<Int32> = [ProcessInfo.processInfo.processIdentifier]
    ) -> MenuBarSource {
        let history = RecentActivityStore()
        return { thresholds, interval, receive in
            let session = MonitoringSession(
                configuration: try MonitoringConfiguration(
                    thresholds: await thresholds(), intervalSeconds: interval.seconds, samples: 0,
                    collectAgentLoad: true, reportIntervalSeconds: LiveReportState.displayIntervalSeconds),
                reader: try reader(), clock: clock, excluding: excluding,
                recentActivity: history)
            try await session.run(
                thresholds: thresholds, interval: interval, receive)
        }
    }
}

import AgentMonitorCore
import Foundation

enum MenuBarCollection {
    static func source(
        reader: @escaping @Sendable () throws -> any ProcessReading = { try NativeProcessReader() },
        clock: any SamplingClock = ContinuousSamplingClock(),
        registry: any SessionRegistryReading = CommandSessionRegistryReader(),
        excluding: Set<Int32> = [ProcessInfo.processInfo.processIdentifier]
    ) -> MenuBarSource {
        let history = RecentActivityStore()
        return { thresholds, interval, receive in
            let session = MonitoringSession(
                configuration: try MonitoringConfiguration(
                    thresholds: await thresholds(), intervalSeconds: interval.seconds, samples: 0,
                    collectAgentLoad: true, reportIntervalSeconds: 1),
                reader: try reader(), clock: clock, registry: registry, excluding: excluding,
                recentActivity: history)
            try await session.run(
                thresholds: thresholds, interval: interval, receive)
        }
    }
}

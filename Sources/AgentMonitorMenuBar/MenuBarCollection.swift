import AgentMonitorCore
import Foundation

enum MenuBarCollection {
    static func source(
        reader: @escaping @Sendable () throws -> any ProcessReading = { try NativeProcessReader() },
        clock: any SamplingClock = ContinuousSamplingClock(),
        registry: any SessionRegistryReading = CommandSessionRegistryReader(),
        excluding: Set<Int32> = [ProcessInfo.processInfo.processIdentifier]
    ) -> MenuBarSource {
        { thresholds, interval, resolveSessions, receive in
            let session = MonitoringSession(
                configuration: try MonitoringConfiguration(
                    thresholds: await thresholds(), intervalSeconds: interval.seconds, samples: 0,
                    collectAgentLoad: true),
                reader: try reader(), clock: clock, registry: registry, excluding: excluding)
            try await session.run(
                thresholds: thresholds, interval: interval, resolveSessions: resolveSessions, receive)
        }
    }
}

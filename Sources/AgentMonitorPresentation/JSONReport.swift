import AgentMonitorCore
import Foundation

public struct JSONReport: Encodable {
    public let schemaVersion = 3
    public let cpuAccounting: CPUAccountingFields
    public let attributionMeaning = "launchOrigin"
    public let timestamp: Date
    public let intervalSeconds: Double
    public let cpuThresholdPercent: Double
    public let memoryThresholdBytes: UInt64
    public let sampledProcessCount: Int
    public let unreadableProcessCount: Int
    public let findings: [HeavyProcess]

    public init(_ snapshot: MonitoringSnapshot) {
        cpuAccounting = CPUAccountingFields(snapshot.cpuAccounting)
        timestamp = snapshot.timestamp
        intervalSeconds = snapshot.intervalSeconds
        cpuThresholdPercent = snapshot.cpuThresholdPercent
        memoryThresholdBytes = snapshot.memoryThresholdBytes
        sampledProcessCount = snapshot.sampledProcessCount
        unreadableProcessCount = snapshot.unreadableProcessCount
        findings = snapshot.findings
    }

    public static func encodeLine(_ snapshot: MonitoringSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(JSONReport(snapshot))
        data.append(10)
        return data
    }

    public static func schema() throws -> Data {
        guard let url = Bundle.module.url(forResource: "report.schema", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}

public struct CPUAccountingFields: Encodable {
    public let hostBusyPercent: Double?
    public let logicalCPUCount: Int
    public let measuredUserPercent: Double
    public let unmeasuredLifetimeCount: Int
    public let previousScanSeconds: Double?

    init(_ value: CPUAccounting) {
        hostBusyPercent = value.hostBusyPercent
        logicalCPUCount = value.logicalCPUCount
        measuredUserPercent = value.measuredUserPercent
        unmeasuredLifetimeCount = value.unmeasuredLifetimeCount
        previousScanSeconds = value.previousScanSeconds
    }
}

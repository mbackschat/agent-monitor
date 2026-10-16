import AgentMonitorCore
import Foundation

public struct JSONDiagnosis: Encodable {
    let schemaVersion = 1
    let startedAt: Date
    let endedAt: Date
    let elapsedSeconds: Double
    let requestedIntervalSeconds = 1
    let measurementIntervals = 3
    let maximumScanSeconds: Double
    let scope = "currentUserExcludingMonitor"
    let host: Host
    let measured: Measured
    public let contributors: [Contributor]
    let providerLookups: [Lookup]
    let diagnostics: [String]

    struct Host: Encodable {
        let meanBusyPercent: Double?
        let logicalCPUCount: Int?
        let observedSeconds: Double
        let validIntervals: Int
    }

    struct Measured: Encodable {
        let cpuSeconds: Double?
        let windowCPUPercent: Double?
        let observedLifetimeCount: Int
        let measuredLifetimeCount: Int
        let unmeasuredObservationCount: Int
        let unreadableObservationCount: Int
        let omittedContributorCount: Int
    }

    struct Lookup: Encodable {
        let provider: AgentProvider
        let status: String
    }

    struct Footprint: Encodable {
        let bytes: UInt64
        let sampledAt: Date
    }

    struct Association: Encodable {
        let value: DiagnosisAttribution
        private enum CodingKeys: String, CodingKey { case status, observedAt, value, reason }
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch value {
            case .available(let observedAt, let value):
                try container.encode("available", forKey: .status)
                try container.encode(observedAt, forKey: .observedAt)
                try container.encode(value, forKey: .value)
            case .unavailable(let reason):
                try container.encode("unavailable", forKey: .status)
                try container.encode(reason.rawValue, forKey: .reason)
            }
        }
    }

    public struct Contributor: Encodable {
        public let process: ProcessIdentity
        public let label: String
        public let labelTruncated: Bool
        let cpuSeconds: Double
        let observedSeconds: Double
        let validIntervals: Int
        let meanCPUPercent: Double
        let peakCPUPercent: Double
        let footprint: Footprint?
        let attribution: Association

        init(_ value: DiagnosisContributor) {
            process = value.sample.identity
            let basename = value.sample.executable.split(separator: "/").last.map(String.init) ?? ""
            let name = basename.isEmpty ? value.sample.name : basename
            labelTruncated = name.unicodeScalars.count > 120
            label = String(String.UnicodeScalarView(name.unicodeScalars.prefix(120)))
            cpuSeconds = value.cpuSeconds
            observedSeconds = value.observedSeconds
            validIntervals = value.validIntervals
            meanCPUPercent = value.meanCPUPercent
            peakCPUPercent = value.peakCPUPercent
            footprint = value.footprint.map { Footprint(bytes: $0.bytes, sampledAt: $0.sampledAt) }
            attribution = Association(value: value.attribution)
        }
    }

    public init(_ value: CPUDiagnosis) {
        startedAt = value.startedAt
        endedAt = value.endedAt
        elapsedSeconds = value.elapsedSeconds
        maximumScanSeconds = value.maximumScanSeconds
        host = Host(
            meanBusyPercent: value.host.meanBusyPercent, logicalCPUCount: value.host.logicalCPUCount,
            observedSeconds: value.host.observedSeconds, validIntervals: value.host.validIntervals)
        measured = Measured(
            cpuSeconds: value.cpuSeconds, windowCPUPercent: value.windowCPUPercent,
            observedLifetimeCount: value.observedLifetimeCount,
            measuredLifetimeCount: value.measuredLifetimeCount,
            unmeasuredObservationCount: value.unmeasuredObservationCount,
            unreadableObservationCount: value.unreadableObservationCount,
            omittedContributorCount: value.omittedContributorCount)
        contributors = value.contributors.map(Contributor.init)
        providerLookups = value.providerLookups.map {
            Lookup(provider: $0.provider, status: $0.status.rawValue)
        }
        diagnostics = value.diagnostics.map(\.rawValue)
    }

    public static func encode(_ value: CPUDiagnosis) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timestamp(date))
        }
        return try encoder.encode(JSONDiagnosis(value))
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    public static func schema() throws -> Data {
        guard let url = Bundle.module.url(forResource: "diagnosis.schema", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}

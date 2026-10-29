import Foundation

public enum DiagnosisObservation: Sendable {
    case observed(ProcessMetadata)
    case notObserved
}

public protocol DiagnosisReading: Sendable {
    func snapshot(excluding: Set<Int32>) throws -> ProcessSnapshot
    func observation(for sample: ProcessSample) -> DiagnosisObservation
    func isCurrent(_ sample: ProcessSample) -> Bool
}

public enum DiagnosisAttributionFailure: String, Sendable {
    case notObservedAtEnrichment, metadataUnavailable
}

public enum DiagnosisAttribution: Equatable, Sendable {
    case available(observedAt: Date, value: Attribution)
    case unavailable(DiagnosisAttributionFailure)
}

public enum DiagnosisDiagnostic: String, CaseIterable, Sendable {
    case unmeasuredCPU, unreadableObservations, hostCoverageIncomplete, hostCapacityChanged
    case attributionUnavailable, noMeasuredLifetimes
}

public struct DiagnosisFootprint: Equatable, Sendable {
    public let bytes: UInt64
    public let sampledAt: Date
}

public struct DiagnosisContributor: Sendable {
    public let sample: ProcessSample
    public let cpuSeconds: Double
    public let observedSeconds: Double
    public let validIntervals: Int
    public let meanCPUPercent: Double
    public let peakCPUPercent: Double
    public let footprint: DiagnosisFootprint?
    public let attribution: DiagnosisAttribution
    public var isMonitorHelper = false
}

public struct CPUDiagnosis: Sendable {
    public let startedAt: Date
    public let endedAt: Date
    public let elapsedSeconds: Double
    public let maximumScanSeconds: Double
    public let host: CPUWindowHost
    public let cpuSeconds: Double?
    public let windowCPUPercent: Double?
    public let observedLifetimeCount: Int
    public let measuredLifetimeCount: Int
    public let unmeasuredObservationCount: Int
    public let unreadableObservationCount: Int
    public let omittedContributorCount: Int
    public let contributors: [DiagnosisContributor]

    public var diagnostics: [DiagnosisDiagnostic] {
        DiagnosisDiagnostic.allCases.filter {
            switch $0 {
            case .unmeasuredCPU: unmeasuredObservationCount > 0
            case .unreadableObservations: unreadableObservationCount > 0
            case .hostCoverageIncomplete: host.validIntervals < 3
            case .hostCapacityChanged: host.logicalCPUCount == nil
            case .attributionUnavailable:
                contributors.contains { if case .unavailable = $0.attribution { true } else { false } }
            case .noMeasuredLifetimes: measuredLifetimeCount == 0
            }
        }
    }
}

public enum CPUDiagnosisError: Error, Equatable { case collectionFailed }

public struct CPUDiagnosisSession: Sendable {
    private let reader: any DiagnosisReading
    private let clock: any SamplingClock
    private let excluded: Set<Int32>
    private let monitorPID: Int32?

    public init(
        reader: any DiagnosisReading, clock: any SamplingClock = ContinuousSamplingClock(),
        excluding: Set<Int32> = [], monitorPID: Int32? = nil
    ) {
        self.reader = reader
        self.clock = clock
        excluded = excluding
        self.monitorPID = monitorPID
    }

    @concurrent public static func collectLocal() async throws -> CPUDiagnosis {
        let reader: NativeProcessReader
        do { reader = try NativeProcessReader() } catch { throw CPUDiagnosisError.collectionFailed }
        let pid = ProcessInfo.processInfo.processIdentifier
        return try await CPUDiagnosisSession(reader: reader, excluding: [pid], monitorPID: pid).run()
    }

    @concurrent public func run() async throws -> CPUDiagnosis {
        var window = CPUDiagnosisWindow(monitorPID: monitorPID)
        var footprintDates: [ProcessIdentity: Date] = [:]
        let startedAt = clock.now()
        var endedAt = startedAt
        for index in 0...3 {
            try Task.checkCancellation()
            if index > 0 { try await clock.wait(seconds: 1) }
            let snapshot: ProcessSnapshot
            do { snapshot = try reader.snapshot(excluding: excluded) } catch is CancellationError {
                throw CancellationError()
            } catch { throw CPUDiagnosisError.collectionFailed }
            try Task.checkCancellation()
            endedAt = clock.now()
            window.ingest(snapshot)
            for sample in snapshot.samples where sample.footprintBytes != nil {
                footprintDates[sample.identity] = endedAt.addingTimeInterval(
                    sample.sampledAt - snapshot.listedAt - snapshot.scanSeconds)
            }
        }
        let selected = window.contributors
        var monitor = window.monitor
        let identities = selected.map(\.sample.identity)
        var observations: [ProcessIdentity: DiagnosisObservation] = [:]
        var observedAt: [ProcessIdentity: Date] = [:]
        try monitor.enrich(for: identities) { sample in
            try Task.checkCancellation()
            let observation = reader.observation(for: sample)
            try Task.checkCancellation()
            observations[sample.identity] = observation
            observedAt[sample.identity] = clock.now()
            if case .observed(let metadata) = observation {
                return metadata
            }
            return ProcessMetadata(status: .unavailable)
        }
        let contributors = selected.map { value in
            let identity = value.sample.identity
            let attribution: DiagnosisAttribution
            if case .observed(let metadata) = observations[identity],
                let finding = monitor.finding(for: identity), let timestamp = observedAt[identity],
                reader.isCurrent(value.sample)
            {
                if metadata.status == .unavailable, finding.attribution.evidence == .unknown {
                    attribution = .unavailable(.metadataUnavailable)
                } else {
                    attribution = .available(
                        observedAt: timestamp,
                        value: finding.attribution)
                }
            } else {
                attribution = .unavailable(.notObservedAtEnrichment)
            }
            let footprint = value.footprint.flatMap { measurement in
                footprintDates[identity].map { DiagnosisFootprint(bytes: measurement.bytes, sampledAt: $0) }
            }
            return DiagnosisContributor(
                sample: value.sample, cpuSeconds: value.cpuSeconds, observedSeconds: value.observedSeconds,
                validIntervals: value.validIntervals, meanCPUPercent: value.meanCPUPercent,
                peakCPUPercent: value.peakCPUPercent, footprint: footprint, attribution: attribution,
                isMonitorHelper: value.isMonitorHelper)
        }
        try Task.checkCancellation()
        return CPUDiagnosis(
            startedAt: startedAt, endedAt: endedAt, elapsedSeconds: window.elapsedSeconds,
            maximumScanSeconds: window.maximumScanSeconds, host: window.host,
            cpuSeconds: window.cpuSeconds, windowCPUPercent: window.windowCPUPercent,
            observedLifetimeCount: window.observedLifetimeCount,
            measuredLifetimeCount: window.measuredLifetimeCount,
            unmeasuredObservationCount: window.unmeasuredObservationCount,
            unreadableObservationCount: window.unreadableObservationCount,
            omittedContributorCount: window.omittedContributorCount,
            contributors: contributors)
    }
}

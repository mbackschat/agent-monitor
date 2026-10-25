enum AttributionStorage {
    static func validate(_ size: MonitoringPayloadSize, limits: MonitoringPipelineLimits, sequence: UInt64)
        throws
    {
        guard size.observations <= limits.pendingObservations, size.textBytes <= limits.pendingTextBytes
        else {
            throw MonitoringError.overloaded(stage: .attribution, rejectedScan: sequence)
        }
    }

    static func sampleTextBytes(_ sample: ProcessSample) -> Int {
        2 * (sample.executable.utf8.count + sample.name.utf8.count) + (sample.terminal?.utf8.count ?? 0)
    }

    static func marker(_ marker: SessionMarker) -> MonitoringPayloadSize {
        MonitoringPayloadSize(
            observations: 1,
            textBytes: marker.threadID.utf8.count + (marker.rootSessionID?.utf8.count ?? 0)
                + (marker.inboxSocket?.utf8.count ?? 0))
    }

    static func metadata(_ metadata: ProcessMetadata) -> MonitoringPayloadSize {
        var size = MonitoringPayloadSize(
            observations: (metadata.command?.count ?? 0) + metadata.writerThreadIDs.count
                + metadata.listeningSockets.count,
            textBytes: (metadata.cwd?.utf8.count ?? 0) + (metadata.invocation?.utf8.count ?? 0)
                + (metadata.terminal?.utf8.count ?? 0))
        for value in metadata.markers { size.add(marker(value)) }
        for value in metadata.command ?? [] { size.textBytes += value.utf8.count }
        for value in metadata.writerThreadIDs { size.textBytes += value.utf8.count }
        for value in metadata.listeningSockets { size.textBytes += value.utf8.count }
        return size
    }

    static func resolution(_ attribution: Attribution, marker: SessionMarker?) -> MonitoringPayloadSize {
        var size = MonitoringPayloadSize(attribution: attribution)
        size.observations += 1
        if let marker { size.add(Self.marker(marker)) }
        return size
    }
}

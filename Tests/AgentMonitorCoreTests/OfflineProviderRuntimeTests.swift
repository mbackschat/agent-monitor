import Foundation
import Testing

@testable import AgentMonitorCore

@Suite struct OfflineProviderRuntimeTests {
    @Test func defaultSessionRegistryRefusesACommandBeforeItStarts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("listing.sh")
        let marker = directory.appendingPathComponent("started")
        try Data("printf started > \"$1\"\n".utf8).write(to: script)
        let query = SessionRegistryQuery(
            tool: "Disposable listing fixture", command: ["/bin/sh", script.path, marker.path],
            environment: ["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"])

        let failure: (any Error)?
        do {
            _ = try OfflineSessionRegistryReader().output(of: query)
            failure = nil
        } catch {
            failure = error
        }

        #expect(failure != nil)
        #expect(failure?.localizedDescription == ProviderRuntimeAvailability.sessionListingUnavailableReason)
        #expect(!OfflineSessionRegistryReader().isAvailable)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }
}

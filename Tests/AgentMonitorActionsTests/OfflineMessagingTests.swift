import Foundation
import Testing

@testable import AgentMonitorActions
@testable import AgentMonitorCore

@Suite struct OfflineMessagingTests {
    @Test(arguments: [AgentProvider.codex, .claude])
    func publicMessagingAdaptersRefuseRecipientLookup(provider: AgentProvider) {
        let (messaging, target) = fixture(provider)
        do {
            _ = try messaging.recipients(for: target)
            Issue.record("Expected offline recipient lookup to be unavailable")
        } catch {
            #expect(error.localizedDescription == ProviderRuntimeAvailability.messagingUnavailableReason)
            #expect((error as? ActionFailure)?.uncertain == false)
        }
        #expect(!SessionActions.canMessage(target.process))
    }

    @Test(arguments: [AgentProvider.codex, .claude])
    func publicMessagingAdaptersRefuseDirectSubmission(provider: AgentProvider) {
        let (messaging, target) = fixture(provider)
        do {
            try messaging.send("Disposable unsent message", to: target.session, for: target)
            Issue.record("Expected offline message submission to be unavailable")
        } catch {
            #expect(error.localizedDescription == ProviderRuntimeAvailability.messagingUnavailableReason)
            #expect((error as? ActionFailure)?.uncertain == false)
        }
    }

    private func fixture(_ provider: AgentProvider) -> (any AgentMessaging, MessageTarget) {
        let messaging: any AgentMessaging =
            switch provider {
            case .codex: CodexMessaging()
            case .claude: ClaudeMessaging()
            }
        let session = "11111111-1111-4111-8111-111111111111"
        let runtime = ProcessIdentity(pid: 700, startMicroseconds: 1)
        let process = HeavyProcess(
            process: ProcessIdentity(pid: 701, startMicroseconds: 1), executable: "/fixture/worker",
            name: "worker", cpuPercent: 80, footprintBytes: nil, cwd: "/fixture", command: nil,
            metadataStatus: .markerRead,
            attribution: Attribution(
                provider: provider, evidence: .marker, context: .terminal, threadID: session,
                rootSessionID: nil, runtime: runtime, terminal: nil, runtimeDirectory: nil,
                candidateThreadIDs: [], ancestry: []))
        return (messaging, MessageTarget(process: process, session: session, runtime: runtime))
    }
}

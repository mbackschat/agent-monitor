import AgentMonitorCore
import Foundation

struct SavedMessage: Equatable {
    let process: HeavyProcess
    let sampledAt: Date?
    let text: String
    let recipientID: String?
}

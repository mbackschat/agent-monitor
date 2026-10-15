import AgentMonitorCore

struct SavedMessage: Equatable {
    let process: HeavyProcess
    let text: String
    let recipientID: String?
}

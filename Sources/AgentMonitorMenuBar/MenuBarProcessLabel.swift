import AgentMonitorCore
import AgentMonitorPresentation
import SwiftUI

struct MenuBarProcessLabel: View {
    let process: HeavyProcess
    let session: SessionGroup?
    let cpuText: String
    let footprintText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(process.name).lineLimit(1).truncationMode(.middle)
                if session != nil { pid }
                Spacer(minLength: 4)
                Text(cpuText).monospacedDigit().fixedSize()
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let session {
                    if !process.isSharedRuntime {
                        Text(session.project)
                            .lineLimit(1).truncationMode(.middle).layoutPriority(-1)
                            .help(session.project)
                        Text("·")
                    }
                    Text(
                        "\(session.provider?.rawValue ?? "unknown") · \(session.sessionID.map { String($0.prefix(8)) } ?? (process.isSharedRuntime ? "shared runtime" : "unresolved"))"
                    )
                    .fixedSize()
                } else {
                    pid
                }
                Spacer(minLength: 4)
                Text(footprintText).monospacedDigit().fixedSize()
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var pid: some View {
        Text("PID \(String(process.process.pid))")
            .font(.caption2).foregroundStyle(.secondary).fixedSize()
    }
}

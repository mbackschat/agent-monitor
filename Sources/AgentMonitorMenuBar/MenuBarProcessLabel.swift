import AgentMonitorCore
import AgentMonitorPresentation
import SwiftUI

struct MenuBarProcessLabel: View {
    let process: HeavyProcess
    let session: SessionGroup?
    let cpuText: String
    let footprintText: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(process.name).lineLimit(1).truncationMode(.middle)
            Text(String(process.process.pid)).font(.caption2).foregroundStyle(.secondary).fixedSize()
            if process.isHistorical {
                Text("Past").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Text(cpuText).monospacedDigit().frame(width: 48, alignment: .trailing)
            Text(footprintText).monospacedDigit().frame(width: 56, alignment: .trailing)
        }
        .font(.subheadline)
        .help(
            "\(process.name) · PID \(process.process.pid)"
                + (session.map {
                    " · \($0.project) · \($0.provider?.rawValue ?? "unknown") · \($0.sessionID ?? "unresolved")"
                } ?? "")
                + (process.isHistorical ? ". No longer observed; measured CPU remains in this window." : ""))
    }
}

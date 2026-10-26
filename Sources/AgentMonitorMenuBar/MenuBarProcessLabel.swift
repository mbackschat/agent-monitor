import AgentMonitorCore
import AgentMonitorPresentation
import SwiftUI

struct MenuBarProcessLabel: View {
    let process: HeavyProcess
    let session: SessionGroup?
    let directory: String
    let cpuText: String
    let footprintText: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(process.observedName).lineLimit(1).truncationMode(.middle)
            Text(directory).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
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
            "\(process.observedName) · PID \(process.process.pid)"
                + " · CWD: \(process.cwd ?? "unavailable")"
                + (session.map {
                    " · \($0.project) · \($0.provider?.rawValue ?? "unknown") · \($0.sessionID ?? "unresolved")"
                } ?? "")
                + (process.isHistorical ? ". No longer observed; measured CPU remains in this window." : ""))
    }
}

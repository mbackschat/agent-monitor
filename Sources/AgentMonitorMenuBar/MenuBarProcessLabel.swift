import AgentMonitorCore
import AgentMonitorPresentation
import SwiftUI

struct MenuBarProcessLabel: View {
    enum Placement {
        case standalone
        case sessionChild(SessionGroupID)
    }

    let process: HeavyProcess
    let placement: Placement
    let directory: String
    let cpuText: String
    let footprintText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if showsOwner {
                HStack(spacing: 6) {
                    Text(ownerLabel).fixedSize()
                    if exactSession, let name = process.sessionName {
                        Text(TextReport.safe(name)).lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                    if process.accounting?.labelChangedInWindow == true {
                        Text("Changed").fixedSize()
                            .help(
                                "The session label changed in this CPU window. This is the last observed label; CPU includes contributions with earlier labels."
                            )
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            resources
        }
        .help(
            "\(process.observedName) · PID \(process.process.pid)"
                + " · CWD: \(process.cwd ?? "unavailable")"
                + " · \(ownerLabel)"
                + (exactSession
                    ? " · \(process.attribution.threadID ?? "") · \(process.sessionName ?? "")" : "")
                + (process.isHistorical ? ". No longer observed; measured CPU remains in this window." : ""))
    }

    private var showsOwner: Bool {
        switch placement {
        case .standalone: true
        case .sessionChild(let parent):
            if exactSession, let provider = process.attribution.provider,
                let session = process.attribution.threadID
            {
                parent != .session(provider: provider.rawValue, id: session)
            } else {
                true
            }
        }
    }

    private var exactSession: Bool {
        SessionCorroboration.isExact(process.attribution)
            && process.attribution.provider != nil && process.attribution.threadID != nil
    }

    private var ownerLabel: String {
        let provider = process.attribution.provider?.rawValue ?? "Unknown agent"
        let session: String
        if exactSession, let id = process.attribution.threadID {
            session = TextReport.safe(String(id.prefix(8)))
        } else if process.isSharedRuntime {
            session = "Shared runtime"
        } else {
            switch process.attribution.evidence {
            case .ambiguous: session = "Uncertain session"
            default: session = "Unresolved session"
            }
        }
        return "\(provider) · \(session)"
    }

    private var resources: some View {
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
    }
}

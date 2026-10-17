import AgentMonitorPresentation
import SwiftUI

struct MenuBarDiagnosisView: View {
    @Bindable var diagnosis: CPUDiagnosisController
    let copyStatus: String?
    let onCopy: () -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CPU diagnosis · \(diagnosis.state.phase.rawValue)").font(.headline)
                Spacer()
                if diagnosis.state.phase == .collecting {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { diagnosis.cancel() }
                } else {
                    Button("Run again") { diagnosis.start() }
                        .disabled(diagnosis.state.isRunning)
                        .help(DiagnosisViewState.startHelp)
                }
            }
            if diagnosis.state.phase == .completed {
                HStack {
                    Button("Copy report", systemImage: "doc.on.doc") { _ = onCopy() }
                        .controlSize(.small)
                        .help("Copy the full fixed report, including identities and measurement coverage.")
                    if let copyStatus { Text(copyStatus).font(.caption).foregroundStyle(.secondary) }
                }
            }
            ForEach(Array(diagnosis.state.lines.enumerated()), id: \.offset) { entry in
                Text(entry.element.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(entry.element.style == .failure ? .red : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding()
    }
}

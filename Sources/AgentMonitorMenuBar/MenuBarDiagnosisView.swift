import AgentMonitorPresentation
import SwiftUI

struct MenuBarDiagnosisView: View {
    @Bindable var diagnosis: CPUDiagnosisController

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
                        .help(DiagnosisViewState.help)
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

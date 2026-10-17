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
            if diagnosis.state.phase == .completed {
                ForEach(Array(diagnosis.state.sections.enumerated()), id: \.offset) { entry in
                    MenuBarDiagnosisSection(section: entry.element)
                }
            } else {
                ForEach(Array(diagnosis.state.lines.enumerated()), id: \.offset) { entry in
                    Text(entry.element.text)
                        .font(.callout)
                        .foregroundStyle(entry.element.style == .failure ? .red : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding()
    }
}

struct MenuBarDiagnosisSection: View {
    let section: DiagnosisReportSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title).font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(Array(section.lines.enumerated()), id: \.offset) { entry in
                Text(entry.element.text)
                    .font(.callout)
                    .foregroundStyle(entry.element.style == .muted ? .secondary : .primary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(section.kind == .contributor ? 12 : 0)
        .background(
            section.kind == .contributor ? Color.primary.opacity(0.04) : .clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            if section.kind == .contributor {
                RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12))
            }
        }
        .textSelection(.enabled)
    }
}

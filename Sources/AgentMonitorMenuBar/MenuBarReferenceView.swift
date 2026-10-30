import AgentMonitorCore
import AgentMonitorPresentation
import SwiftUI

enum MenuBarReferencePage: String, Identifiable {
    case glossary, diagnostics, keyboard
    var id: Self { self }
    var title: String {
        switch self {
        case .glossary: "Help & glossary"
        case .diagnostics: "Diagnostics"
        case .keyboard: "Keyboard shortcuts"
        }
    }
    var symbol: String {
        switch self {
        case .glossary: "questionmark.circle"
        case .diagnostics: "stethoscope"
        case .keyboard: "keyboard"
        }
    }
}

struct MenuBarReferenceMenu: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        HStack(spacing: 8) {
            referenceButton(.glossary)
            referenceButton(.diagnostics)
            if !model.report.displayCoverageStatus.notes.isEmpty {
                MenuBarCoverageStatus(model: model)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .controlSize(.small)
        .popover(item: $model.referencePage) { page in
            MenuBarReferenceContent(model: model, page: page) { model.referencePage = nil }
        }
    }

    private func referenceButton(_ page: MenuBarReferencePage) -> some View {
        Button(page.title, systemImage: page.symbol) { model.referencePage = page }
            .labelStyle(.iconOnly).help(page.title)
    }
}

struct MenuBarCoverageStatus: View {
    let model: MenuBarModel

    var body: some View {
        let status = model.report.displayCoverageStatus
        HStack {
            if !status.notes.isEmpty {
                Label(
                    status.summaryText,
                    systemImage: status.severity == .warning ? "exclamationmark.triangle" : "info.circle"
                )
                .lineLimit(2)
                .foregroundStyle(status.severity == .warning ? Color.orange : Color.secondary)
            }
        }
        .font(.caption2)
        .fixedSize(horizontal: false, vertical: true)
        .help(status.help)
    }
}

struct MenuBarReferenceContent: View {
    @Bindable var model: MenuBarModel
    let page: MenuBarReferencePage
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(page.title).font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly).help("Close (Esc)").keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch page {
                    case .glossary: glossary
                    case .diagnostics: diagnostics
                    case .keyboard: MenuBarKeyboardShortcuts()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: 400, height: 480)
    }

    private var glossary: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(ReportGlossary.entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title).font(.subheadline.bold()).accessibilityAddTraits(.isHeader)
                    Text(entry.definition).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .textSelection(.enabled)
            }
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.report.frozen ? "Paused report diagnostics" : "Displayed report diagnostics")
                .font(.subheadline.bold())
            Text(CPUContext.text(model.report.snapshot?.cpuAccounting))
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            if model.report.showsOverview {
                Text(model.report.overview.census).font(.caption)
                Text(model.report.overview.coverage).font(.caption)
            }
            GroupBox("Collection") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ThresholdContext.text(model.report.thresholds))
                    Text("Visible acquisition maximum: \(model.report.interval.formatted()) seconds")
                    Text("Display refresh: \(LiveReportState.displayIntervalSeconds.formatted()) seconds")
                    Text(
                        model.liveIcon
                            ? "Collection continues while the panel is closed."
                            : "Collection runs only while the panel is open.")
                }
                .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(model.report.displayCoverageStatus.notes.enumerated()), id: \.offset) { _, note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.text).font(.subheadline.bold())
                        .foregroundStyle(note.severity == .warning ? Color.orange : Color.primary)
                    Text(note.help).font(.caption)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if model.report.displayCoverageStatus.notes.isEmpty {
                Text(CoverageStatus.clearText).font(.caption).foregroundStyle(.secondary)
            }
            if let summary = model.report.displaySamplingCoverage {
                MenuBarCoverageSummary(summary: summary)
            }
            Text(SamplingCoverageSummary.interpretation)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GroupBox("Local-only operation") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ProviderRuntimeAvailability.sessionListingUnavailableReason)
                    Text(ProviderRuntimeAvailability.messagingUnavailableReason)
                }
                .font(.caption).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Text("CPU investigation").font(.subheadline.bold())
            Text(DiagnosisViewState.startHelp).font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Button("Diagnose CPU") {
                dismiss()
                model.beginDiagnosis()
            }
            .disabled(!model.isOpen || model.report.actionPanel != nil || model.diagnosis.state.isRunning)
            .help("Measure which processes use CPU over a short observation")
        }
    }
}

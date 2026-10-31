import AgentMonitorPresentation
import SwiftUI

struct MenuBarContributorInspection: View {
    @State private var showsEvidence = false
    var activity = ContributorActivity()
    let node: ContributorNode
    let duration: Double
    let canInspect: Bool
    let inspect: () -> Void
    var close: () -> Void = {}
    var focus: FocusState<MenuBarFocus?>.Binding? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(
                    TextReport.safe(
                        node.ownerHeadline
                            + (node.ownerHeadline == node.label.headline ? "" : " / " + node.label.headline))
                ).font(.headline).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let focus {
                    closeButton.focused(focus, equals: .inspection)
                } else {
                    closeButton
                }
            }
            let context = node.inspectionFields.filter { $0.kind == .context }
            let evidence = node.inspectionFields.filter { $0.kind == .evidence }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "CPU " + node.stats.cpuText(duration: duration) + " · Memory "
                            + node.stats.currentMemoryText
                            + " · Recent CPU " + node.stats.recentCPUText
                    )
                    .font(.caption).monospacedDigit().textSelection(.enabled)
                    MenuBarInspectionHistory(activity: activity, id: node.id).id(node.id)
                    MenuBarInspectionFields(fields: context)
                    if node.process != nil {
                        Button("Inspect current process…", action: inspect).disabled(!canInspect)
                            .help(
                                "Show current process details, arguments and actions"
                            )
                    }
                    Text("Process counts").font(.subheadline.bold()).accessibilityAddTraits(.isHeader)
                        .help("Counts overlap; do not add them together")
                    MenuBarEvidenceTable(fields: node.populationFields)
                    if !evidence.isEmpty {
                        DisclosureGroup(isExpanded: $showsEvidence) {
                            MenuBarEvidenceTable(fields: evidence).padding(.top, 6)
                        } label: {
                            Text("Attribution details")
                                .help(
                                    "Show ownership evidence and measurement limits"
                                )
                        }.font(.caption)
                    }

                }
            }

        }
        .lineLimit(nil)
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private var closeButton: some View {
        Button("Close details", systemImage: "xmark", action: close)
            .labelStyle(.iconOnly).help("Close details (Esc)")
    }

}

struct MenuBarInspectionFields: View {
    let fields: [InspectionField]

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 7) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                GridRow(alignment: .top) {
                    Text(field.label).foregroundStyle(.secondary).frame(width: 114, alignment: .leading)
                    Text(TextReport.safe(field.value))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.help("Select text to copy")
            }
        }.font(.caption).lineLimit(nil).textSelection(.enabled)
    }
}

struct MenuBarEvidenceTable: View {
    let fields: [InspectionField]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Text("Item").frame(width: 110, alignment: .leading)
                Text("Value").frame(width: 120, alignment: .leading)
                Text("Meaning").frame(maxWidth: .infinity, alignment: .leading)
            }.fontWeight(.semibold).padding(6)
            ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                HStack(alignment: .top, spacing: 10) {
                    Text(field.label).frame(width: 110, alignment: .leading)
                    Text(TextReport.safe(field.value)).monospacedDigit().fontWeight(.medium)
                        .frame(width: 120, alignment: .leading)
                    Text(field.help ?? "—").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true).padding(6)
                .background(.primary.opacity(index.isMultiple(of: 2) ? 0.045 : 0))
            }
        }.font(.caption).lineLimit(nil).textSelection(.enabled)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

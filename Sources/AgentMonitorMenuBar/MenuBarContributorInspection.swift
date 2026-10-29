import AgentMonitorPresentation
import SwiftUI

struct MenuBarContributorInspection: View {
    @State private var showsEvidence = false
    @State private var showsHistory = false
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
            let evidence = node.populationFields + node.inspectionFields.filter { $0.kind == .evidence }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "CPU " + node.stats.cpuText(duration: duration) + " · Memory "
                            + node.stats.currentMemoryText
                            + " · Recent CPU " + node.stats.recentCPUText
                    )
                    .font(.caption).monospacedDigit().textSelection(.enabled)
                    MenuBarInspectionFields(fields: context)
                    if node.process != nil {
                        Button("Inspect current process…", action: inspect).disabled(!canInspect)
                            .help(
                                "Open process details, arguments and verified actions. Historical workers cannot be action targets."
                            )
                    }
                    if !activity.spans.isEmpty {
                        DisclosureGroup("CPU history · " + activity.scaleLabel, isExpanded: $showsHistory) {
                            MenuBarInspectionFields(fields: activity.inspectionFields(for: node.id)).padding(
                                .top, 6)
                        }.font(.caption)
                    }
                    DisclosureGroup("Counts and evidence", isExpanded: $showsEvidence) {
                        MenuBarInspectionFields(fields: evidence).padding(.top, 6)
                    }.font(.caption)
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
                }.help(field.help ?? "")
            }
        }.font(.caption).lineLimit(nil).textSelection(.enabled)
    }
}

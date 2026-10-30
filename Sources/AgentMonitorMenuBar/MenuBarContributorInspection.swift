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
                    MenuBarInspectionHistory(activity: activity, id: node.id)
                    MenuBarInspectionFields(fields: context)
                    if node.process != nil {
                        Button("Inspect current process…", action: inspect).disabled(!canInspect)
                            .help(
                                "Show current process details, arguments and actions"
                            )
                    }
                    Text("Process counts").font(.subheadline.bold()).accessibilityAddTraits(.isHeader)
                        .help("These populations overlap; do not add the rows together")
                    MenuBarEvidenceTable(fields: node.populationFields)
                    if !evidence.isEmpty {
                        DisclosureGroup(isExpanded: $showsEvidence) {
                            MenuBarEvidenceTable(fields: evidence).padding(.top, 6)
                        } label: {
                            Text("Attribution details")
                                .help(
                                    "How this process was associated with a session, and the limits of that evidence"
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
                }.help(field.help ?? "")
            }
        }.font(.caption).lineLimit(nil).textSelection(.enabled)
    }
}

private struct MenuBarInspectionHistory: View {
    let activity: ContributorActivity
    let id: ContributorID
    @State private var showsIntervals = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CPU history").font(.subheadline.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(activity.scaleLabel).font(.caption).monospacedDigit()
                    .help("Fixed CPU range shared with the overview; 100% means one core")
            }
            if activity.spans.isEmpty {
                Text("No CPU history available").font(.caption).foregroundStyle(.secondary)
            } else {
                MenuBarContributorLane(activity: activity, id: id)
                    .frame(height: 96)
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                    .overlay {
                        if activity.samples[id]?.contains(where: { ($0?.measuredIntervals ?? 0) > 0 }) != true
                        {
                            Text("No measured CPU intervals").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                HStack {
                    Text("Older")
                    Spacer()
                    Text("Latest")
                }.font(.caption2).foregroundStyle(.secondary)
                DisclosureGroup(isExpanded: $showsIntervals) {
                    MenuBarInspectionFields(fields: activity.inspectionFields(for: id)).padding(.top, 6)
                } label: {
                    Text("Interval values").help("Exact CPU values and measurement limits for each bar")
                }.font(.caption)
            }
        }
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

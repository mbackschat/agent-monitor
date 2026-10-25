import AgentMonitorPresentation
import SwiftUI

struct MenuBarContributorInspection: View {
    @State private var showsEvidence = false
    let node: ContributorNode
    let duration: Double
    let canInspect: Bool
    let inspect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(TextReport.safe(node.title)).font(.headline).textSelection(.enabled)
            HStack(spacing: 20) {
                metric("CPU", node.stats.cpuText(duration: duration))
                metric("Memory", node.stats.memoryText)
                metric("Recent CPU", node.stats.recentCPUText)
            }
            Divider()
            let context = node.inspectionFields.filter { $0.kind == .context }
            let evidence = node.populationFields + node.inspectionFields.filter { $0.kind == .evidence }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    MenuBarInspectionFields(fields: context)
                    DisclosureGroup("Counts and evidence", isExpanded: $showsEvidence) {
                        MenuBarInspectionFields(fields: evidence).padding(.top, 6)
                    }.font(.caption)
                }
            }
            .frame(
                idealHeight: min(
                    340, CGFloat(context.count + (showsEvidence ? evidence.count : 0)) * 22 + 28),
                maxHeight: 340)
            if node.process != nil {
                Button("Inspect current process…", action: inspect).disabled(!canInspect)
                    .help(
                        "Open process details, arguments and verified actions. Historical workers cannot be action targets."
                    )
            }
        }
        .padding(14).frame(width: 400)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body.monospacedDigit())
        }
    }
}

struct MenuBarInspectionFields: View {
    let fields: [InspectionField]

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 7) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                GridRow(alignment: .top) {
                    Text(field.label).foregroundStyle(.secondary).frame(width: 114, alignment: .leading)
                    Text(TextReport.safe(field.value)).frame(maxWidth: .infinity, alignment: .leading)
                }.help(field.help ?? "")
            }
        }.font(.caption).textSelection(.enabled)
    }
}

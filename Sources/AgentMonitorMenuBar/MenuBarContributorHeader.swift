import AgentMonitorPresentation
import SwiftUI

enum MenuBarContributorColumns {
    static let chart: CGFloat = 100
    static let cpu: CGFloat = 80
    static let memory: CGFloat = 88
    static let spacing: CGFloat = 12
}

struct MenuBarContributorHeader: View {
    @Bindable var model: MenuBarModel

    private var acceptsInteraction: Bool {
        model.isOpen && model.report.showsOverview && model.isReportUnobstructed
    }

    var body: some View {
        let overview = model.report.overview
        VStack(spacing: 6) {
            HStack(spacing: MenuBarContributorColumns.spacing) {
                sortButton("Contributor", field: .contributor)
                Spacer(minLength: 0)
                Text("CPU history · " + overview.activity.scaleLabel)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize().frame(width: MenuBarContributorColumns.chart, alignment: .trailing)
                sortButton("CPU", field: .cpu)
                    .frame(width: MenuBarContributorColumns.cpu, alignment: .trailing)
                sortButton("Memory", field: .memory)
                    .frame(width: MenuBarContributorColumns.memory, alignment: .trailing)
            }
            HStack(spacing: MenuBarContributorColumns.spacing) {
                Text(
                    overview.totals.currentAvailable
                        ? "Total · \(overview.totals.current.count) processes"
                        : "Total · presence unavailable"
                )
                .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                MenuBarContributorLane(activity: overview.activity)
                    .frame(width: MenuBarContributorColumns.chart, height: 32)
                Text(overview.totals.cpuText(duration: overview.duration))
                    .font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: MenuBarContributorColumns.cpu, alignment: .trailing)
                    .accessibilityLabel("Total CPU: " + overview.totals.cpuText(duration: overview.duration))
                Text(overview.totals.memoryText)
                    .font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: MenuBarContributorColumns.memory, alignment: .trailing)
                    .accessibilityLabel("Total memory: " + overview.totals.memoryText)
            }.monospacedDigit().accessibilityLabel("Measured total")
        }.padding(.leading, 14).padding(.trailing, 24).padding(.vertical, 7)
    }

    private func sortButton(_ title: String, field: ContributorOrder) -> some View {
        Button {
            guard acceptsInteraction else { return }
            let overview = model.report.overview
            model.report.overview.sort(
                by: field, ascending: overview.order == field ? !overview.ascending : field == .contributor)
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if model.report.overview.order == field {
                    Image(systemName: model.report.overview.ascending ? "chevron.up" : "chevron.down").font(
                        .caption2)
                }
            }.font(.system(size: 11, weight: .semibold))
        }.buttonStyle(.plain)
            .accessibilityIdentifier("contributor-sort-" + title.lowercased())
            .accessibilityLabel("Sort by " + title)
            .accessibilityValue(
                model.report.overview.order == field
                    ? (model.report.overview.ascending ? "Ascending" : "Descending") : "Not sorted"
            )
            .help(
                "Sort by " + title + (field == .cpu ? " (c)" : field == .memory ? " (m)" : "")
                    + "; click again or press r to reverse")
    }
}

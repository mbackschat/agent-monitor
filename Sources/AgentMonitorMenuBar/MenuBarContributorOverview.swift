import AgentMonitorPresentation
import SwiftUI

struct MenuBarContributorOverview: View {
    @Bindable var model: MenuBarModel
    var focus: FocusState<MenuBarFocus?>.Binding

    var body: some View {
        let overview = model.report.overview
        VStack(alignment: .leading, spacing: 6) {
            Text(
                "Measured total · CPU \(overview.totals.cpuText(duration: overview.duration)) · Memory \(overview.totals.memoryText)"
            )
            .font(.caption).monospacedDigit()
            Text(
                (overview.totals.currentAvailable
                    ? "\(overview.totals.current.count) processes" : "Current presence unavailable")
                    + " · Recent CPU \(overview.totals.recentCPUText) over \(overview.sourceDurationLabel)"
            )
            .font(.caption2).foregroundStyle(.secondary)
            if let notice = overview.pinNotice {
                Text(notice).font(.caption).foregroundStyle(.orange)
            }
            MenuBarCoverageLink(model: model)
            MenuBarContributorTable(model: model, focus: focus)
        }
    }
}

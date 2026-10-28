import AgentMonitorPresentation
import SwiftUI

struct MenuBarContributorOverview: View {
    @Bindable var model: MenuBarModel
    var focus: FocusState<MenuBarFocus?>.Binding

    var body: some View {
        let overview = model.report.overview
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(overview.totals.cpuText(duration: overview.duration)).font(.title2.bold())
                    Text("CPU").font(.caption)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(overview.totals.memoryText).font(.title3.weight(.semibold))
                    Text("memory").font(.caption)
                }
                Spacer(minLength: 0)
                Text(
                    overview.totals.currentAvailable
                        ? "\(overview.totals.current.count) processes" : "Presence unavailable"
                )
                .font(.caption).foregroundStyle(.secondary)
            }.monospacedDigit().accessibilityLabel("Measured total")
            if !model.report.displayCoverageStatus.notes.isEmpty { MenuBarCoverageStatus(model: model) }
            if let notice = overview.pinNotice { Text(notice).font(.caption).foregroundStyle(.orange) }
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 6) {
                    MenuBarContributorTable(model: model, focus: focus)
                    Text("Recent " + overview.activity.intervalLabel + " · 100% = one core")
                        .font(.caption2).foregroundStyle(.secondary)
                    if overview.detailsVisible, let id = overview.selection, let node = overview.nodes[id] {
                        Divider()
                        MenuBarContributorInspection(
                            node: node, duration: overview.duration,
                            canInspect: node.process.map { identity in
                                model.report.snapshot?.findings.contains {
                                    $0.process == identity && !$0.isHistorical
                                } == true
                            } ?? false,
                            inspect: { model.report.inspectOverviewProcess() },
                            close: {
                                model.report.overview.toggleDetails()
                                focus.wrappedValue = .overview
                            }, focus: focus
                        )
                        .frame(height: min(190, geometry.size.height * 0.45))
                        .onKeyPress(.escape) {
                            model.report.overview.toggleDetails()
                            focus.wrappedValue = .overview
                            return .handled
                        }
                    }
                }
            }
        }
        .onChange(of: overview.detailsVisible) { _, visible in
            guard model.isOpen, model.report.showsOverview, !model.diagnosis.state.isVisible,
                model.report.actionPanel == nil
            else { return }
            focus.wrappedValue = visible ? .inspection : .overview
        }
    }
}

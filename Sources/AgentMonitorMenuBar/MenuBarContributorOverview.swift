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
            if let notice = overview.pinNotice { Text(notice).font(.caption).foregroundStyle(.orange) }
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 6) {
                    MenuBarContributorTable(model: model, focus: focus)
                    Text("Recent " + overview.activity.intervalLabel + " · 100% = one core")
                        .font(.caption2).foregroundStyle(.secondary)
                    if overview.detailsVisible, let id = overview.selection, let node = overview.nodes[id] {
                        Divider()
                        Group {
                            if let process = model.report.contributorProcessTarget {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Button("Back to contributor", systemImage: "chevron.left") {
                                            model.report.overview.showContributorSummary()
                                        }.labelStyle(.iconOnly).help("Back to contributor")
                                            .focused(focus, equals: .inspection)
                                        Text(TextReport.safe(node.ownerHeadline)).font(
                                            .caption.weight(.semibold)
                                        )
                                        .lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                        Button("Close details", systemImage: "xmark") { closeDetails() }
                                            .labelStyle(.iconOnly).help("Close details (Esc)")
                                    }
                                    ScrollView {
                                        MenuBarProcessDetails(
                                            model: model, process: process, contributor: id,
                                            keyboardTarget: .process(process.process)
                                        )
                                        .id(process.process)
                                    }
                                }.padding(10)
                            } else {
                                MenuBarContributorInspection(
                                    activity: overview.activity, node: node, duration: overview.duration,
                                    canInspect: node.process.map { identity in
                                        model.report.contributorProcesses(for: id).contains {
                                            $0.process == identity
                                        }
                                    } ?? false,
                                    inspect: {
                                        if let identity = node.process {
                                            model.report.inspectContributorProcess(identity, contributor: id)
                                        }
                                    }, close: closeDetails, focus: focus)
                            }
                        }
                        .frame(height: min(260, geometry.size.height * 0.48))
                        .background(.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
                        .onKeyPress(.escape) {
                            closeDetails()
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
    private func closeDetails() {
        model.report.overview.toggleDetails()
        focus.wrappedValue = .overview
    }

}

struct MenuBarReadingSurface: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .opacity(0.92)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

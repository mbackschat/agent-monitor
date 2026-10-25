import AgentMonitorPresentation
import SwiftUI

struct MenuBarContributorOverview: View {
    @Bindable var model: MenuBarModel
    var focus: FocusState<MenuBarFocus?>.Binding

    var body: some View {
        let overview = model.report.overview
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        "Observed total · "
                            + overview.totals.summary(duration: overview.duration)
                    )
                    .font(.caption).monospacedDigit()
                    Text(overview.totals.compactCensus).font(.caption2).foregroundStyle(.secondary)
                        .help(overview.totals.census)
                }

            }
            if overview.duration > LiveReportState.displayIntervalSeconds + 0.05 {
                Text("CPU over \(overview.duration.formatted(.number.precision(.fractionLength(1)))) s")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            MenuBarCoverageStatus(status: overview.coverageStatus)
            DisclosureGroup("Sampling coverage") {
                if let summary = overview.samplingCoverage {
                    MenuBarCoverageSummary(summary: summary)
                }
            }.font(.caption).foregroundStyle(.secondary)
            if !model.liveIcon {
                Text("Collected since panel opened").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text("Group / process").frame(maxWidth: .infinity, alignment: .leading)
                Text("CPU").frame(width: 48, alignment: .trailing)
                Text("Memory").frame(width: 62, alignment: .trailing)
                Text("Recent").frame(width: 44, alignment: .trailing)
                Text("Now").frame(width: 28, alignment: .trailing)
            }.font(.caption2).foregroundStyle(.secondary).padding(.leading, 26).padding(.trailing, 8)
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(overview.visibleRows) { row in
                    contributor(row, overview: overview)
                }
            }
        }
    }

    private func contributor(_ row: ContributorRow, overview: ContributorOverview) -> some View {
        let node = row.node
        let expanded = overview.open.contains(row.id)
        return VStack(alignment: .leading, spacing: 5) {
            Button {
                model.report.overview.toggle(row.id)
            } label: {
                MenuBarContributorSummary(node: node, overview: overview, expanded: expanded)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused(focus, equals: .contributor(row.id))
            .accessibilityLabel(node.title + ". " + node.summary(duration: overview.duration))
            .contextMenu {
                Button("Pin / unpin session") {
                    model.report.overview.select(row.id)
                    model.report.overview.togglePin()
                }
            }
            if expanded && !node.details.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(node.details.enumerated()), id: \.offset) { _, text in
                        Text(text).font(.caption2).textSelection(.enabled)
                    }
                    if let identity = node.process,
                        model.report.snapshot?.findings.contains(where: {
                            $0.process == identity && !$0.isHistorical
                        }) == true
                    {
                        Button("Inspect current process…") {
                            model.report.overview.select(row.id)
                            model.report.inspectOverviewProcess()
                        }.controlSize(.small)
                    }
                }.padding(.leading, 18)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 1)
        .padding(.leading, CGFloat(min(row.depth, 4) * 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            overview.selection == row.id ? Color.accentColor.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .id(row.id)
    }
}

struct MenuBarContributorSummary: View {
    let node: ContributorNode
    let overview: ContributorOverview
    let expanded: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right").frame(width: 12)
            Text(node.title).font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(node.title + ". " + node.stats.census)
            metric(
                node.stats.cpuText(duration: overview.duration),
                fraction: overview.cpuMeterFraction(node.stats)
            )
            .frame(width: 48)
            .help(
                "CPU over \(overview.duration.formatted()) s. Bar: 100% is one core. Session ownership is point evidence."
            )
            metric(node.stats.memoryText, fraction: overview.memoryMeterFraction(node.stats))
                .frame(width: 62)
                .help(
                    "Current physical footprint; bar scale is physical RAM. \(node.stats.missingMemory) readings unavailable. Historical peaks are in details."
                )
            Text(node.stats.recentCPUText).monospacedDigit().frame(width: 44, alignment: .trailing)
                .help("Measured CPU-seconds in the recent range, including workers no longer observed.")
            Text(node.stats.currentAvailable ? String(node.stats.current.count) : "—")
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                .help(
                    node.stats.census
                        + ". Disappearance is not confirmed termination; filtered members remain in totals.")
        }
        .font(.caption)
        .frame(minHeight: 22)
        .overlay(alignment: .topLeading) {
            if overview.pinned.contains(node.id) {
                Image(systemName: "pin.fill").font(.system(size: 7)).offset(x: -6, y: -2)
            }
        }
    }

    private func metric(_ value: String, fraction: Double) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value).monospacedDigit()
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Color.accentColor.opacity(0.65))
                        .frame(width: geometry.size.width * min(1, max(0, fraction)))
                }
            }.frame(height: 2)
        }
    }
}

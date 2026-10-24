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
            if overview.duration > 1.05 {
                Text("CPU over \(overview.duration.formatted(.number.precision(.fractionLength(1)))) s")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !overview.coverageWarning.isEmpty {
                Text(overview.coverageWarning).font(.caption2).foregroundStyle(.orange)
            }
            DisclosureGroup("Recent coverage · \(overview.sourceDurationLabel)") {
                Text(overview.census).font(.caption2)
                Text(overview.coverage).font(.caption2)
                Text(
                    "Session CPU is point-evidence candidate CPU over \(overview.duration.formatted(.number.precision(.fractionLength(1)))) s. Polling can miss workers and final exit CPU. Counts identify observed lifetimes, not confirmed exits."
                )
                .font(.caption2)
            }.font(.caption).foregroundStyle(.secondary)
            if !model.liveIcon {
                Text("Collected since panel opened").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Text("CPU").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Memory").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Recent CPU").frame(maxWidth: .infinity, alignment: .trailing)
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
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").frame(width: 10)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(node.title).font(.subheadline.weight(.medium)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(node.stats.currentAvailable ? "\(node.stats.current.count) now" : "—")
                                .font(.caption2).foregroundStyle(.secondary).fixedSize()
                        }.help(node.title + ". " + node.stats.census)
                        HStack(spacing: 12) {
                            metric(
                                "CPU", value: node.stats.cpuText(duration: overview.duration),
                                share: overview.cpuMeterFraction(node.stats),
                                help:
                                    "Point-evidence candidate CPU for exact sessions, measured over \(overview.duration.formatted()) s. Bar: 100% is one core. Share of observed CPU: \(overview.totals.currentCPU > 0 ? (100 * node.stats.currentCPU / overview.totals.currentCPU).formatted(.number.precision(.fractionLength(1))) : "0")%. Unresolved work remains separate."
                            )
                            metric(
                                "Memory", value: node.stats.memoryText,
                                share: overview.memoryMeterFraction(node.stats),
                                help:
                                    "Latest observed footprint; \(node.stats.missingMemory) readings unavailable. Bar: full scale is \((Double(overview.memoryCapacityBytes) / 1e9).formatted(.number.precision(.fractionLength(1)))) GB physical RAM. Share of observed memory: \(overview.totals.memoryBytes > 0 ? (100 * Double(node.stats.memoryBytes) / Double(overview.totals.memoryBytes)).formatted(.number.precision(.fractionLength(1))) : "0")%. Historical peaks are in details."
                            )
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(node.stats.recentCPUText).font(.caption).monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .help(
                                "Measured CPU-seconds in the retained recent range, including workers no longer observed. Session ownership is point evidence."
                            )
                        }
                        if !node.stats.noLongerObserved.isEmpty || !node.stats.filtered.isEmpty {
                            Text(node.stats.compactCensus).font(.caption2).foregroundStyle(.secondary)
                                .help(
                                    node.stats.census
                                        + ". Disappearance is not confirmed termination; filtered members remain in totals."
                                )
                        }
                    }
                    Spacer(minLength: 0)
                    if overview.pinned.contains(row.id) { Image(systemName: "pin.fill").font(.caption) }
                }.contentShape(Rectangle())
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
        .padding(.horizontal, 8).padding(.vertical, 6)
        .padding(.leading, CGFloat(min(row.depth, 4) * 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            overview.selection == row.id ? Color.accentColor.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .id(row.id)
    }
    private func metric(_ title: String, value: String, share: Double, help: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                Text(value).monospacedDigit()
            }.font(.caption)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Color.accentColor.opacity(0.65))
                        .frame(width: geometry.size.width * min(1, max(0, share)))
                }
            }.frame(height: 3)
        }.frame(maxWidth: .infinity).accessibilityLabel(title + ": " + value).help(help)
    }

}

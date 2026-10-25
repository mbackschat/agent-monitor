import AgentMonitorCore
import AgentMonitorPresentation
import SwiftUI

struct MenuBarSamplingCoverage: View {
    let snapshot: MonitoringSnapshot

    var body: some View {
        DisclosureGroup("Sampling coverage") {
            MenuBarSamplingCoverageDetails(snapshot: snapshot)
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}

struct MenuBarSamplingCoverageDetails: View {
    let snapshot: MonitoringSnapshot

    var body: some View {
        MenuBarCoverageSummary(summary: SamplingCoverageSummary(snapshot: snapshot))
    }
}

/// Individual coverage cells keep simultaneous gaps visible; definitions stay in tooltips.
struct MenuBarCoverageStatus: View {
    let status: CoverageStatus

    var body: some View {
        Group {
            if status.notes.isEmpty {
                Label(CoverageStatus.clearText, systemImage: "info.circle")
                    .foregroundStyle(.secondary).help(status.help)
            } else {
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6) {
                    ForEach(Array(stride(from: 0, to: status.notes.count, by: 2)), id: \.self) { start in
                        GridRow {
                            note(status.notes[start])
                            if start + 1 < status.notes.count {
                                note(status.notes[start + 1])
                            } else {
                                Color.clear.frame(width: 0, height: 0)
                            }
                        }
                    }
                }
            }
        }.font(.caption2)
    }

    private func note(_ value: CoverageStatus.Note) -> some View {
        Label(
            value.text, systemImage: value.severity == .warning ? "exclamationmark.triangle" : "info.circle"
        )
        .foregroundStyle(value.severity == .warning ? Color.orange : Color.primary)
        .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(value.help)
    }
}

struct MenuBarCoverageSummary: View {
    let summary: SamplingCoverageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let duration = summary.duration {
                VStack(spacing: 3) {
                    HStack {
                        Text("Recent history")
                        Spacer()
                        Text(duration, format: .number.precision(.fractionLength(1))) + Text(" / 60 s")
                        if summary.retentionLimited {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                .help(
                                    "Retention pressure or an acquisition gap shortened the available history."
                                )
                        }
                    }.font(.caption2)
                    ProgressView(value: min(duration, 60), total: 60)
                        .tint(summary.retentionLimited ? .orange : .accentColor)
                        .help(
                            "Retained time range, not a percentage of workload captured. Polling can miss processes."
                        )
                        .accessibilityLabel("Retained recent history")
                        .accessibilityValue("\(duration.formatted()) seconds")
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach([0, 3], id: \.self) { start in
                    GridRow {
                        ForEach(Array(summary.metrics.dropFirst(start).prefix(3))) { metric in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(metric.value).font(.system(.body, design: .rounded).weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(metric.warning ? Color.orange : Color.primary)
                                Text(metric.title).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(metric.help)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            if !summary.events.isEmpty {
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
                    ForEach(Array(stride(from: 0, to: summary.events.count, by: 2)), id: \.self) { start in
                        GridRow {
                            ForEach(Array(summary.events.dropFirst(start).prefix(2))) { metric in
                                HStack(spacing: 6) {
                                    Text(metric.title).foregroundStyle(.secondary)
                                    Spacer(minLength: 4)
                                    Text(metric.value).monospacedDigit()
                                }
                                .font(.caption2).help(metric.help)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
            HStack {
                Text(summary.scanLabel).font(.caption2)
                Spacer()
                Image(systemName: "info.circle")
                    .help(SamplingCoverageSummary.interpretation)
                    .accessibilityLabel("Sampling limitations")
            }.foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

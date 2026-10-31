import AgentMonitorCore
import AgentMonitorPresentation
import SwiftUI

struct MenuBarCoverageSummary: View {
    let summary: SamplingCoverageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let duration = summary.duration {
                VStack(spacing: 3) {
                    HStack {
                        Text("Recent history")
                        Spacer()
                        Text("\(duration, format: .number.precision(.fractionLength(1))) / 60 s")
                        if summary.retentionLimited {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                .help(
                                    "Less history is available; see Measurement limits"
                                )
                        }
                    }.font(.caption2)
                    ProgressView(value: min(duration, 60), total: 60)
                        .tint(summary.retentionLimited ? .orange : .accentColor)
                        .help(
                            "Retained history duration; not complete workload coverage"
                        )
                        .accessibilityLabel("Retained recent history")
                        .accessibilityValue("\(duration.formatted()) seconds")
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(Array(stride(from: 0, to: summary.metrics.count, by: 3)), id: \.self) { start in
                    GridRow {
                        ForEach(Array(summary.metrics.dropFirst(start).prefix(3))) { metric in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(metric.value).font(.system(.body, design: .rounded).weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(metric.warning ? Color.orange : Color.primary)
                                    .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                                Text(metric.title).font(.caption2).foregroundStyle(.secondary)
                                    .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
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
            Text(summary.scanLabel).font(.caption2).foregroundStyle(.secondary)
                .help("Observed scans and retained history, not complete workload coverage")
        }
        .padding(.vertical, 4)
    }
}

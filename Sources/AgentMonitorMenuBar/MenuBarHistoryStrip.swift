import AgentMonitorPresentation
import SwiftUI

struct MenuBarHistoryStrip: View {
    let model: MenuBarModel

    var body: some View {
        let metric = model.report.historyMetric
        let history = model.report.history
        let values = history.values(metric: metric, window: model.report.historyWindow, count: 40)
        let peak = values.compactMap { $0 }.max()
        let maximum = max(1, peak ?? 1)
        let currentValue = history.currentValue(metric)
        HStack(spacing: 8) {
            MenuBarViewOptions(model: model, placement: .history)
                .frame(width: 120)
            Canvas { context, size in
                context.fill(
                    Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)),
                    with: .color(.secondary.opacity(0.3)))
                let step = size.width / Double(values.count)
                for (index, value) in values.enumerated() {
                    guard let value else { continue }
                    let height = max(1, value / maximum * size.height)
                    let bar = CGRect(
                        x: Double(index) * step, y: size.height - height,
                        width: max(1, step - 1), height: height)
                    context.fill(Path(roundedRect: bar, cornerRadius: 1), with: .foreground)
                }
            }
            .foregroundStyle(.secondary)
            .frame(height: 20)
            .accessibilityLabel(
                peak == nil
                    ? "Agent \(metric.rawValue) history, no available measurements"
                    : "Agent \(metric.rawValue) history, peak \(metric.formatted(peak))"
            )
            .help(
                "All observed agents · each bar preserves the bucket’s peak · scale 0–\(metric.formatted(maximum)) · gaps mean no available measurement"
            )
            Text(currentValue.map { metric.formatted($0) } ?? "No data")
                .font(.caption).monospacedDigit().fixedSize()
                .foregroundStyle(currentValue == nil ? .secondary : .primary)
                .help("Latest \(metric.rawValue) measurement; No data means unavailable, not zero.")
        }
        .frame(height: 28)
    }
}

import AgentMonitorPresentation
import SwiftUI

struct MenuBarHistoryStrip: View {
    let model: MenuBarModel

    var body: some View {
        let metric = model.report.historyMetric
        let history = model.report.history
        let values = history.values(metric: metric, window: model.report.historyWindow, count: 40)
        let maximum = max(1, values.compactMap { $0 }.max() ?? 1)
        HStack(spacing: 8) {
            MenuBarViewOptions(model: model, placement: .history)
                .frame(width: 120)
            Canvas { context, size in
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
            .accessibilityLabel("Agent history, peak \(metric.formatted(values.compactMap { $0 }.max()))")
            .help(
                "All observed agents · each bar preserves the bucket’s peak · scale 0–\(metric.formatted(maximum)) · gaps mean no available measurement"
            )
            Text(metric.formatted(history.currentValue(metric)))
                .font(.caption).monospacedDigit().fixedSize()
        }
        .frame(height: 28)
    }
}

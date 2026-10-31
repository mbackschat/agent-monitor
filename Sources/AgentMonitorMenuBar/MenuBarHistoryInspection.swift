import AgentMonitorPresentation
import SwiftUI

struct MenuBarHistoryData: Equatable {
    let spans: [ContributorActivity.Span]
    let samples: [ContributorActivity.Sample?]
    let ceiling: Double

    init(activity: ContributorActivity, id: ContributorID) {
        spans = activity.spans
        samples = activity.samples[id] ?? Array(repeating: nil, count: spans.count)
        ceiling = activity.ceiling
    }

    func readout(at index: Int) -> String? {
        guard spans.indices.contains(index) else { return nil }
        let value = samples[index]?.percent(in: spans[index])
        let cpu = value.map { String(format: "%.1f%% CPU", $0) } ?? "Not measured"
        let end = spans.last?.endedAt ?? 0
        let range = String(
            format: "%.1f–%.1f s before latest", end - spans[index].endedAt, end - spans[index].startedAt)
        return cpu + " · " + range
    }
}

struct MenuBarHistoryGeometry {
    let count: Int
    let step: Double
    let leading: Double

    init(width: Double, scale: Double, count: Int) {
        self.count = count
        step = count > 0 ? floor(width * scale / Double(count)) / scale : 0
        leading = (width - step * Double(count)) / 2
    }

    func index(at x: Double) -> Int? {
        guard step > 0, x >= leading, x < leading + Double(count) * step else { return nil }
        return Int((x - leading) / step)
    }
}

struct MenuBarHistorySelection {
    private(set) var held: MenuBarHistoryData?
    var index: Int?

    mutating func hold(_ data: MenuBarHistoryData, at index: Int) {
        guard data.spans.indices.contains(index) else { return }
        // Retain only this contributor’s bounded bars to avoid holding the report population
        // (architecture.md, Resource history).
        held = data
        self.index = index
    }

    mutating func resume() {
        held = nil
        index = nil
    }
}

struct MenuBarInspectionHistory: View {
    let activity: ContributorActivity
    let id: ContributorID
    @State private var selection = MenuBarHistorySelection()
    @Environment(\.displayScale) private var displayScale

    private var data: MenuBarHistoryData {
        selection.held ?? MenuBarHistoryData(activity: activity, id: id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CPU history").font(.subheadline.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("0–\(Int(data.ceiling))%").font(.caption).monospacedDigit()
                    .help("Fixed CPU range; 100% means one core")
            }
            if data.spans.isEmpty {
                Text("No CPU history available").font(.caption).foregroundStyle(.secondary)
            } else {
                chart
                HStack {
                    Text("Older")
                    Spacer()
                    Text(selection.held == nil ? "Latest" : "Held")
                }.font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if let index = selection.index, let text = data.readout(at: index) {
                        Text(text).monospacedDigit()
                            .help(String(format: "Average over %.1f seconds", data.spans[index].duration))
                        if data.samples[index]?.qualified == true {
                            Image(systemName: "exclamationmark.triangle")
                                .accessibilityLabel("Partial measurement")
                                .help("Partial measurement; some CPU may be missing")
                        }
                    } else {
                        Text("Hover to inspect · click to hold").foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if selection.held != nil {
                        Button("Resume") { selection.resume() }
                            .help("Resume live chart")
                    }
                }.font(.caption).frame(minHeight: 22)
            }
        }
    }

    private var chart: some View {
        GeometryReader { geometry in
            let bars = MenuBarHistoryGeometry(
                width: geometry.size.width, scale: displayScale, count: data.spans.count)
            MenuBarHistoryPlot(data: data, selectedIndex: selection.index)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard selection.held == nil else { return }
                    switch phase {
                    case .active(let location): selection.index = bars.index(at: location.x)
                    case .ended: selection.index = nil
                    }
                }
                .gesture(
                    SpatialTapGesture().onEnded { event in
                        if let index = bars.index(at: event.location.x) { selection.hold(data, at: index) }
                    })
        }
        .frame(height: 96)
        .overlay {
            if !data.samples.contains(where: { ($0?.measuredIntervals ?? 0) > 0 }) {
                Text("No measured CPU intervals").font(.caption).foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }
        }
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
        .focusable()
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { key in
            guard key.modifiers.isEmpty else { return .ignored }
            move(key.key == .leftArrow ? -1 : 1)
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CPU history")
        .accessibilityValue(selection.index.flatMap { data.readout(at: $0) } ?? "No interval selected")
        .accessibilityHint("Use left and right arrows to inspect intervals")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(1)
            case .decrement: move(-1)
            @unknown default: break
            }
        }
        .help("Hover for CPU; click to hold; ←/→ when focused")
    }

    private func move(_ delta: Int) {
        let index = selection.index ?? (delta < 0 ? data.spans.count : -1)
        selection.hold(data, at: min(data.spans.count - 1, max(0, index + delta)))
    }
}

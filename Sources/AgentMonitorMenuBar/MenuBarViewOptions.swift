import AgentMonitorPresentation
import SwiftUI

struct MenuBarViewOptions: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        Menu("View options", systemImage: "slider.horizontal.3") {
            Section("Display") {
                Picker(
                    "Show",
                    selection: Binding(
                        get: { model.report.grouping },
                        set: { if $0 != model.report.grouping { model.report.toggleGrouping() } }
                    )
                ) {
                    Text("Sessions").tag(ReportGrouping.session)
                    Text("Processes").tag(ReportGrouping.none)
                }
                Picker(
                    "Sort by",
                    selection: Binding(
                        get: { model.report.sortKey }, set: { model.report.sort(by: $0) }
                    )
                ) {
                    ForEach(ReportSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Toggle(
                    "Ascending",
                    isOn: Binding(
                        get: { model.report.ascending },
                        set: { if $0 != model.report.ascending { model.report.reverseSort() } }
                    ))
            }
            Section("Sampling") {
                Toggle(
                    "Live menu bar icon",
                    isOn: Binding(get: { model.liveIcon }, set: { model.setLiveIcon($0) })
                )
                .help("Samples every 15 seconds while closed. Turn off to stop closed-panel sampling.")
                Menu("CPU > \(model.report.thresholds.cpuPercent.formatted())%") {
                    Button("Lower by 10 percentage points") { model.report.adjustThreshold(.cpuDown) }
                        .disabled(model.report.thresholds.cpuPercent == 0)
                    Button("Raise by 10 percentage points") { model.report.adjustThreshold(.cpuUp) }
                }
                Menu("Footprint > \((Double(model.report.thresholds.memoryBytes) / 1e9).formatted()) GB") {
                    Button("Lower by 1 GB") { model.report.adjustThreshold(.memoryDown) }
                        .disabled(model.report.thresholds.memoryBytes == 0)
                    Button("Raise by 1 GB") { model.report.adjustThreshold(.memoryUp) }
                }
                Menu("Every \(model.report.interval.formatted()) seconds") {
                    Button("More often") { model.adjustInterval(.faster) }
                        .disabled(!canAdjustInterval(.faster))
                    Button("Less often") { model.adjustInterval(.slower) }
                        .disabled(!canAdjustInterval(.slower))
                }
            }
            Divider()
            Toggle("Keyboard shortcuts", isOn: $model.showsKeyboardHelp)
        }
        .fixedSize().controlSize(.small)
        .help("Grouping, sort direction, CPU and footprint thresholds, and sampling interval")
    }

    private func canAdjustInterval(_ adjustment: IntervalAdjustment) -> Bool {
        var report = model.report
        report.adjustInterval(adjustment)
        return report.interval != model.report.interval
    }
}

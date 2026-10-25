import AgentMonitorCore
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
        Text(
            "Totals are independent of filters; process groups show retained members. Sampling can miss short-lived work. CPU 100% = one core.\n\(snapshot.sampledProcessCount) sampled · \(snapshot.unreadableProcessCount) failed same-user PID reads in the latest scan"
        )
        .font(.caption2).foregroundStyle(.secondary)
    }
}

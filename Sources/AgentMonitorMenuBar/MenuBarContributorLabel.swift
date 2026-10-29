import AgentMonitorPresentation
import SwiftUI

struct MenuBarContributorLabel<Resources: View>: View {
    let label: ContributorLabel
    let resources: Resources

    init(label: ContributorLabel, @ViewBuilder resources: () -> Resources) {
        self.label = label
        self.resources = resources()
    }

    var body: some View {
        switch label {
        case .text:
            singleRow(naturalTitle: false)
        case .session(let identity, let directory):
            ViewThatFits(in: .horizontal) {
                singleRow(naturalTitle: true)
                sessionRows(identity: identity, directory: directory)
            }
        case .workload(let name, let directory):
            HStack(spacing: 6) {
                Text(TextReport.safe(name)).font(.subheadline.weight(.medium))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let directory {
                    Text(TextReport.safe(directory)).font(.caption)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                resources
            }
        }
    }

    private func singleRow(naturalTitle: Bool) -> some View {
        HStack(spacing: 6) {
            Text(TextReport.safe(label.title)).font(.subheadline.weight(.medium))
                .lineLimit(1).truncationMode(.tail)
                .fixedSize(horizontal: naturalTitle, vertical: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            resources
        }
    }

    private func sessionRows(identity: String, directory: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(TextReport.safe(identity)).font(.subheadline.weight(.medium)).fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Text(directory.map(TextReport.safe) ?? "").font(.caption)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                resources
            }
        }
    }
}

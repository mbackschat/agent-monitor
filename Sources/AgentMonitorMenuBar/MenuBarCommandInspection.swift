import AgentMonitorCore
import AgentMonitorPresentation
import SwiftUI

struct MenuBarCommandInspection: View {
    let process: HeavyProcess
    @Bindable var controller: CommandInspectionController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let inspection = controller.state, inspection.process == process.process {
                HStack {
                    Text(inspection.summary).font(.caption2)
                    Spacer()
                    Button("Hide") { controller.dismiss() }.controlSize(.small)
                }
                if let arguments = inspection.arguments {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(arguments.indices, id: \.self) { index in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(String(index)).foregroundStyle(.secondary).frame(
                                        width: 28, alignment: .trailing)
                                    Text(arguments[index]).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }.font(.caption.monospaced()).textSelection(.enabled)
                    }.frame(maxHeight: 160)
                }
            } else if let arguments = process.command {
                Text(arguments.joined(separator: " ")).font(.caption.monospaced()).textSelection(.enabled)
            } else if !process.isHistorical {
                Button("Read arguments", systemImage: "text.alignleft") { controller.start(process) }
                    .controlSize(.small).disabled(controller.isReading)
                    .help(
                        "Read this process now, including when the displayed sample is paused. Keeps only this inspection in memory; does not enable recording."
                    )
            }
        }
    }
}

import AgentMonitorPresentation
import SwiftUI

struct MenuBarKeyboardShortcuts: View {
    let model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.report.showsOverview ? "For the contributor overview" : "For the process table")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Help & glossary", systemImage: "book.closed") { model.showGlossary() }
                .help("Explain resource measurements and contributor groups")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                ForEach(model.availableKeyboardShortcuts, id: \.key) { shortcut in
                    GridRow {
                        Text(shortcut.key).fontDesign(.monospaced).fixedSize()
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                        Text(shortcut.description).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.font(.caption)
        }
    }
}

extension MenuBarModel {
    /// Labels shared browsing keys from their bindings so the guide cannot drift from `ReportShortcut`.
    private static func keys(_ shortcuts: ReportShortcut...) -> String {
        shortcuts.map(\.rawValue).joined(separator: " / ")
    }

    var availableKeyboardShortcuts: [(key: String, description: String)] {
        var keys: [(key: String, description: String)] = [("Esc", "Close this guide")]
        guard isOpen, isReportUnobstructed else { return keys }
        keys.append(("Tab / ⇧Tab", "Next / previous control"))
        if !report.showsOverview || !report.overview.visibleRows.isEmpty {
            keys.append(("↑ / ↓", "Previous / next row"))
        }
        if report.showsOverview {
            keys.append((Self.keys(.foldTable), "Collapse / expand table"))
            for section in report.overview.tableSections {
                keys.append((section.shortcut, "Fold " + section.rawValue))
            }
            if report.overview.selectionIsVisible, let id = report.overview.selection,
                let node = report.overview.nodes[id]
            {
                if !node.children.isEmpty { keys.append(("← / →", "Collapse / expand row")) }
                keys.append(("i", "Show / hide contributor details"))
                if report.overview.pinTarget(for: id) != nil {
                    keys.append((Self.keys(.pin), "Pin / unpin session"))
                }
                if report.overview.detailsVisible, report.overview.inspectedProcess != nil {
                    if let process = report.contributorProcessTarget {
                        if canBegin(.terminate, contributor: id, process: process.process) {
                            keys.append(("k", "Review process termination"))
                        }
                        if canBegin(.focus, contributor: id, process: process.process) {
                            keys.append(("f", "Show terminal"))
                        }
                    }
                } else {
                    if canBeginContributorTermination(id) {
                        keys.append(("k", "Review termination of current processes"))
                    }
                    let targets = report.contributorProcesses(for: id)
                    if targets.count == 1, let process = targets.first,
                        canBegin(.focus, contributor: id, process: process.process)
                    {
                        keys.append(("f", "Show terminal"))
                    }
                }
            }
            keys += [
                (Self.keys(.allContributors), "Main / all contributors"),
                (Self.keys(.chartRange), "Change fixed CPU chart range"),
            ]
        } else {
            if let row = report.selection {
                keys += [("← / →", "Close / open row details"), (Self.keys(.pin), "Pin / unpin row")]
                if pidToCopy(for: row) != nil { keys.append(("y", "Copy PID")) }
                if canBegin(.terminate, row: row) { keys.append(("k", "Review process termination")) }
                if canBegin(.focus, row: row) { keys.append(("f", "Show terminal")) }
            }
            if report.grouping == .session { keys.append(("⇧← / ⇧→", "Collapse / expand session groups")) }
            keys += [
                (Self.keys(.pid), "Sort by PID"), (Self.keys(.historyMetric), "Change history metric"),
                (Self.keys(.historyWindow), "Change history time range"),
            ]
        }
        if report.hasPins { keys.append((Self.keys(.unpinAll), "Unpin all")) }
        if report.canSelectOverview { keys.append((Self.keys(.overview), "Switch overview / processes")) }
        keys += [
            (Self.keys(.grouping), "Toggle process grouping"),
            (Self.keys(.cpu, .memory, .stable), "Sort by CPU / memory / stable order"),
        ]
        if report.showsOverview ? report.overview.order != .stable : report.sortKey != .stable {
            keys.append((Self.keys(.reverse), "Reverse sort direction"))
        }
        if report.snapshot != nil {
            keys.append((Self.keys(.pause), report.frozen ? "Resume updates" : "Pause updates"))
        }
        keys += [
            (Self.keys(.cpuDown, .cpuUp), "Lower / raise CPU filter"),
            (Self.keys(.memoryDown, .memoryUp), "Lower / raise memory filter"),
            (Self.keys(.slower, .faster), "Slower / faster sampling"), ("?", "Show available shortcuts"),
            ("q / ⌘Q", "Quit"),
        ]
        return keys
    }
}

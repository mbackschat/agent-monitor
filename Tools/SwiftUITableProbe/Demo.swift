import AppKit
import SwiftUI

private struct DemoRow: Identifiable {
    let id: String
    let name: String
    var children: [DemoRow] = []
}

@Observable @MainActor private final class DemoTree {
    let roots: [DemoRow]
    var expanded: Set<String> = ["session-a", "executable"]
    var selection: String?

    init(followingRoot: Bool) {
        let a = DemoRow(
            id: "session-a", name: "Session A",
            children: [
                DemoRow(
                    id: "executable", name: "Executable group",
                    children: [
                        DemoRow(id: "process-1", name: "Process 1"),
                        DemoRow(id: "process-2", name: "Process 2"),
                    ])
            ])
        let b = DemoRow(id: "session-b", name: "Session B")
        roots = followingRoot ? [a, b] : [b, a]
    }

    func expansion(_ row: DemoRow) -> Binding<Bool> {
        Binding(
            get: { self.expanded.contains(row.id) },
            set: { value in
                if value { self.expanded.insert(row.id) } else { self.expanded.remove(row.id) }
            })
    }
}

@Observable @MainActor private final class DemoState {
    var following = DemoTree(followingRoot: true)
    var last = DemoTree(followingRoot: false)
    var generation = 0

    func reset() {
        following = DemoTree(followingRoot: true)
        last = DemoTree(followingRoot: false)
        generation += 1
    }
}

private struct DemoView: View {
    @Bindable var state: DemoState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SwiftUI nested expansion").font(.title2.bold())
            Text(
                "Both tables start with Session A and its executable group expanded. Each should show five rows."
            )
            HStack(alignment: .top, spacing: 20) {
                pane("Following root · failing case", model: state.following)
                pane("Expanded branch last · control", model: state.last)
            }.id(state.generation)
            Text(
                "Try the left table: collapse Session A, then expand it again. The two process rows should appear."
            )
            HStack {
                Button("Recreate both tables") { state.reset() }.keyboardShortcut("r", modifiers: .command)
                Spacer()
                Text("Synthetic data · no process monitoring").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20).frame(minWidth: 780, minHeight: 430)
    }

    private func pane(_ title: String, model: DemoTree) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            DemoTable(model: model).frame(minHeight: 230)
            Text(
                "Saved expansion: Session A \(model.expanded.contains("session-a") ? "open" : "closed"), group \(model.expanded.contains("executable") ? "open" : "closed")"
            )
            .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

private struct DemoTable: View {
    @Bindable var model: DemoTree

    var body: some View {
        Table(of: DemoRow.self, selection: $model.selection) {
            TableColumn("Name", value: \.name)
        } rows: {
            DemoRows(rows: model.roots, model: model)
        }
    }
}

private struct DemoRows: TableRowContent {
    let rows: [DemoRow]
    let model: DemoTree

    @TableRowBuilder<DemoRow> var tableRowBody: some TableRowContent<DemoRow> {
        ForEach(rows) { row in
            if row.children.isEmpty {
                TableRow(row)
            } else {
                DisclosureTableRow(row, isExpanded: model.expansion(row)) {
                    DemoRows(rows: row.children, model: model)
                }
            }
        }
    }
}

@MainActor private final class DemoDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor private func tables(in view: NSView) -> [NSOutlineView] {
    if let table = view as? NSOutlineView { return [table] }
    return view.subviews.flatMap { tables(in: $0) }
}

@main private struct Demo {
    @MainActor static func main() {
        let app = NSApplication.shared
        let checking = CommandLine.arguments.contains("--check")
        app.setActivationPolicy(checking ? .prohibited : .regular)
        let delegate = DemoDelegate()
        app.delegate = delegate
        let state = DemoState()
        let host = NSHostingView(rootView: DemoView(state: state))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "SwiftUI Table Expansion Demo"
        window.contentView = host
        if checking {
            Task { @MainActor in
                @MainActor func counts() -> [Int] { tables(in: host).map(\.numberOfRows).sorted() }
                @MainActor func settle(_ expected: [Int]) async {
                    let deadline = ContinuousClock.now + .seconds(2)
                    repeat {
                        host.layoutSubtreeIfNeeded()
                        if counts() == expected { return }
                        try? await Task.sleep(for: .milliseconds(5))
                    } while ContinuousClock.now < deadline
                }
                await settle([3, 5])
                let initial = counts()
                state.following.expanded.remove("session-a")
                await settle([2, 5])
                let collapsed = counts()
                state.following.expanded.insert("session-a")
                await settle([5, 5])
                let reopened = counts()
                state.reset()
                await settle([3, 5])
                let recreated = counts()
                print("initial=\(initial) collapsed=\(collapsed) reopened=\(reopened) recreated=\(recreated)")
                exit(
                    initial == [3, 5] && collapsed == [2, 5] && reopened == [5, 5] && recreated == [3, 5]
                        ? 0 : 1)
            }
        } else {
            let menu = NSMenu()
            let application = NSMenuItem()
            let commands = NSMenu()
            commands.addItem(
                withTitle: "Quit Demo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            application.submenu = commands
            menu.addItem(application)
            app.mainMenu = menu
            window.center()
            window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
        }
        withExtendedLifetime(delegate) { app.run() }
    }
}

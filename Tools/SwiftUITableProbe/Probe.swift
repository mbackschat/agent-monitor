import AppKit
import SwiftUI

@Observable @MainActor final class Node: Identifiable {
    let id: String
    let children: [Node]
    var expanded = false

    init(_ id: String, children: [Node] = []) {
        self.id = id
        self.children = children
    }
}

enum BindingMode: String, CaseIterable {
    case sharedSet
    case perNode
}

@Observable @MainActor final class FixtureState {
    var open: Set<String> = []
    var selection: String?
    let roots: [Node]
    let mode: BindingMode

    init(count: Int, depth: Int, mode: BindingMode) {
        self.mode = mode
        roots = (0..<count).map { index in
            let leaves = [Node("leaf-\(index)-a"), Node("leaf-\(index)-b")]
            let children = depth == 3 ? [Node("grandchild-\(index)", children: leaves)] : leaves
            return Node("parent-\(index)", children: [Node("child-\(index)", children: children)])
        }
        setOpen(true)
    }

    func binding(_ node: Node) -> Binding<Bool> {
        switch mode {
        case .sharedSet:
            Binding(
                get: { self.open.contains(node.id) },
                set: { value in
                    if value { self.open.insert(node.id) } else { self.open.remove(node.id) }
                })
        case .perNode:
            bindNode(node)
        }
    }

    private func bindNode(_ node: Node) -> Binding<Bool> {
        @Bindable var node = node
        return $node.expanded
    }

    func setOpen(_ expanded: Bool) {
        guard let parent = roots.last else { return }
        @MainActor func apply(_ node: Node) {
            guard !node.children.isEmpty else { return }
            node.expanded = expanded
            if expanded { open.insert(node.id) } else { open.remove(node.id) }
            for child in node.children { apply(child) }
        }
        apply(parent)
    }
}

struct Fixture: View {
    @Bindable var state: FixtureState

    var body: some View {
        Table(of: Node.self, selection: $state.selection) {
            TableColumn("Name", value: \.id)
        } rows: {
            ForEach(state.roots) { parent in
                DisclosureTableRow(parent, isExpanded: state.binding(parent)) {
                    ForEach(parent.children) { child in
                        DisclosureTableRow(child, isExpanded: state.binding(child)) {
                            ForEach(child.children) { descendant in
                                if descendant.children.isEmpty {
                                    TableRow(descendant)
                                } else {
                                    DisclosureTableRow(descendant, isExpanded: state.binding(descendant)) {
                                        ForEach(descendant.children) { leaf in TableRow(leaf) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ProbeResult: Codable {
    let mode: String
    let roots: Int
    let depth: Int
    let phase: String
    let rowsAfterLayout: Int?
    let rowsAfterTwentyYields: Int?
    let expectedLevels: [Int]
    let actualLevels: [Int]
    let targetInitiallyOutsideViewport: Bool?
    let selectedID: String?
    let expectedSelection: String?
    let passed: Bool
}

@MainActor func outline(in view: NSView) -> NSOutlineView? {
    if let found = view as? NSOutlineView { return found }
    return view.subviews.lazy.compactMap { outline(in: $0) }.first
}

@MainActor func mount(_ state: FixtureState) -> (NSHostingView<Fixture>, NSWindow) {
    let host = NSHostingView(rootView: Fixture(state: state))
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 240)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    return (host, window)
}

@MainActor func inspect(
    _ host: NSView, state: FixtureState, count: Int, depth: Int, phase: String, expanded: Bool
) async -> ProbeResult {
    let expected =
        Array(repeating: 0, count: count)
        + (expanded ? Array(1..<depth) + [depth, depth] : [])
    host.layoutSubtreeIfNeeded()
    let immediate = outline(in: host)?.numberOfRows
    for _ in 0..<20 {
        await Task.yield()
        host.layoutSubtreeIfNeeded()
    }
    let yielded = outline(in: host)?.numberOfRows
    // Task.yield alone does not establish a completed AppKit update; the independent row oracle does.
    let deadline = ContinuousClock.now + .seconds(2)
    while outline(in: host)?.numberOfRows != expected.count, ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
        host.layoutSubtreeIfNeeded()
    }
    guard let table = outline(in: host) else {
        return ProbeResult(
            mode: state.mode.rawValue, roots: count, depth: depth, phase: phase,
            rowsAfterLayout: immediate, rowsAfterTwentyYields: yielded, expectedLevels: expected,
            actualLevels: [], targetInitiallyOutsideViewport: nil, selectedID: state.selection,
            expectedSelection: nil, passed: false)
    }
    let levels = (0..<table.numberOfRows).map { table.level(forRow: $0) }
    var outside: Bool?
    var target: String?
    if expanded, levels == expected {
        let row = expected.count - 1
        target = "leaf-\(count - 1)-b"
        outside = !NSLocationInRange(row, table.rows(in: table.visibleRect))
        table.scrollRowToVisible(row)
        table.deselectAll(nil)
        state.selection = nil
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        let selectionDeadline = ContinuousClock.now + .seconds(2)
        while state.selection != target, ContinuousClock.now < selectionDeadline {
            try? await Task.sleep(for: .milliseconds(10))
            host.layoutSubtreeIfNeeded()
        }
    }
    return ProbeResult(
        mode: state.mode.rawValue, roots: count, depth: depth, phase: phase,
        rowsAfterLayout: immediate, rowsAfterTwentyYields: yielded, expectedLevels: expected,
        actualLevels: levels, targetInitiallyOutsideViewport: outside, selectedID: state.selection,
        expectedSelection: target,
        passed: levels == expected && (!expanded || state.selection == target)
            && (count == 1 || !expanded || outside == true))
}

@main struct Probe {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            var results: [ProbeResult] = []
            for mode in BindingMode.allCases {
                for count in [1, 30] {
                    for depth in [2, 3] {
                        let state = FixtureState(count: count, depth: depth, mode: mode)
                        let (host, window) = mount(state)
                        results.append(
                            await inspect(
                                host, state: state, count: count, depth: depth,
                                phase: "initial", expanded: true))
                        state.setOpen(false)
                        results.append(
                            await inspect(
                                host, state: state, count: count, depth: depth,
                                phase: "collapsed", expanded: false))
                        state.setOpen(true)
                        results.append(
                            await inspect(
                                host, state: state, count: count, depth: depth,
                                phase: "reopened", expanded: true))
                        window.contentView = nil
                        window.close()
                        state.selection = nil
                        let (replacement, replacementWindow) = mount(state)
                        results.append(
                            await inspect(
                                replacement, state: state, count: count, depth: depth,
                                phase: "remounted", expanded: true))
                        replacementWindow.contentView = nil
                        replacementWindow.close()
                    }
                }
            }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(results)
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
                exit(results.allSatisfy(\.passed) ? 0 : 1)
            } catch {
                FileHandle.standardError.write(Data("\(error)\n".utf8))
                exit(2)
            }
        }
        app.run()
    }
}

import AgentMonitorPresentation
import AppKit
import SwiftUI

enum MenuBarContributorColumn: String, CaseIterable {
    case contributor = "Contributor"
    case cpu = "CPU"
    case memory = "Memory"
}

struct MenuBarContributorOutline: NSViewRepresentable {
    let model: MenuBarModel
    let overview: ContributorOverview
    let focused: Bool
    let focusChanged: @MainActor (Bool) -> Void
    let cell: @MainActor (ContributorNode, MenuBarContributorColumn) -> AnyView
    let height: @MainActor (ContributorNode, CGFloat) -> CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        makeScrollView(coordinator: context.coordinator)
    }

    func makeScrollView(coordinator: Coordinator) -> NSScrollView {
        // MenuBarContributorTableTests reproduces bound-open DisclosureTableRow children staying
        // collapsed on macOS 27 (2026-10-27); explicit items preserve shared disclosure offscreen too.
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let outline = ContributorOutlineView()
        outline.delegate = coordinator
        outline.dataSource = coordinator
        outline.style = .inset
        outline.usesAlternatingRowBackgroundColors = true
        outline.rowSizeStyle = .custom
        outline.rowHeight = 44
        outline.indentationPerLevel = 16
        outline.autoresizesOutlineColumn = false
        outline.autoresizingMask = [.width]
        outline.allowsMultipleSelection = false
        outline.allowsEmptySelection = false
        outline.selectionHighlightStyle = .regular
        outline.allowsColumnReordering = false
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outline.focusRingType = .default
        outline.setAccessibilityLabel("Main contributors")
        for column in MenuBarContributorColumn.allCases {
            let native = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            native.title = column.rawValue
            native.isEditable = false
            switch column {
            case .contributor:
                native.width = 172
                native.minWidth = 130
                native.maxWidth = 172
                native.resizingMask = [.autoresizingMask, .userResizingMask]
            case .cpu:
                native.width = 74
                native.minWidth = 74
                native.maxWidth = 74
                native.headerCell.alignment = .right
            case .memory:
                native.width = 78
                native.minWidth = 78
                native.maxWidth = 78
                native.headerCell.alignment = .right
            }
            outline.addTableColumn(native)
        }
        outline.outlineTableColumn = outline.tableColumns.first
        outline.keyHandler = { [weak coordinator] event in
            coordinator?.handleKey(event) ?? false
        }
        outline.focusChanged = { [weak coordinator] active in
            coordinator?.configuration.focusChanged(active)
        }
        outline.contextMenu = { [weak coordinator] event in
            coordinator?.menu(for: event)
        }
        outline.mounted = { [weak coordinator] in coordinator?.restoreFocus() }
        scroll.documentView = outline
        coordinator.outline = outline
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(self, scroll: scroll)
    }

    @MainActor final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var configuration: MenuBarContributorOutline
        weak var outline: ContributorOutlineView?
        private var items: [ContributorID: Item] = [:]
        private var roots: [Item] = []
        private var previousSelection: ContributorID?
        private var previousOpen: Set<ContributorID> = []
        private var previousShowAll = false
        private var previousPinned: Set<ContributorID> = []
        private var applying = false
        private var pendingFocus = false
        private var heightChanges: Set<ContributorID> = []

        private var acceptsInteraction: Bool {
            configuration.model.isOpen && configuration.model.report.showsOverview
                && !configuration.model.diagnosis.state.isVisible
                && configuration.model.report.actionPanel == nil
        }

        init(_ configuration: MenuBarContributorOutline) {
            self.configuration = configuration
            pendingFocus = configuration.focused
        }

        func update(_ next: MenuBarContributorOutline, scroll: NSScrollView) {
            let oldSelection = previousSelection
            let oldFocus = configuration.focused
            configuration = next
            guard let outline else { return }
            outline.frame.size.width = scroll.contentSize.width
            let origin = scroll.contentView.bounds.origin
            let structureChanged = reconcile(next.overview)
            applying = true
            if structureChanged { outline.reloadData() }
            if structureChanged || previousOpen != next.overview.open
                || previousShowAll != next.overview.showAll
            {
                for root in roots { restoreDisclosure(root, overview: next.overview) }
            }
            if let id = next.overview.selection, let item = items[id] {
                let row = outline.row(forItem: item)
                if row >= 0, outline.selectedRow != row {
                    outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
                if row >= 0, oldSelection != id { outline.scrollRowToVisible(row) }
            }
            if !structureChanged {
                var changed = IndexSet()
                for id in heightChanges {
                    if let item = items[id] {
                        let row = outline.row(forItem: item)
                        if row >= 0 { changed.insert(row) }
                    }
                }
                outline.noteHeightOfRows(withIndexesChanged: changed)
            }
            refreshCells()
            if structureChanged, oldSelection == next.overview.selection {
                let maximum = max(0, outline.bounds.height - scroll.contentSize.height)
                scroll.contentView.scroll(to: NSPoint(x: origin.x, y: min(origin.y, maximum)))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            applying = false
            previousSelection = next.overview.selection
            previousOpen = next.overview.open
            previousShowAll = next.overview.showAll
            if next.focused, !oldFocus || outline.window?.firstResponder == nil { pendingFocus = true }
            restoreFocus()
        }

        private func reconcile(_ overview: ContributorOverview) -> Bool {
            heightChanges.removeAll(keepingCapacity: true)
            let pinned = Set(overview.pinned)
            heightChanges.formUnion(pinned.symmetricDifference(previousPinned))
            previousPinned = pinned
            var retained: [ContributorID: Item] = [:]
            for (id, node) in overview.nodes where node.process == nil || node.stats.filtered.isEmpty {
                let item = items[id] ?? Item(node)
                if item.node.label != node.label || item.node.stats.current.count != node.stats.current.count
                    || item.node.stats.currentAvailable != node.stats.currentAvailable
                {
                    heightChanges.insert(id)
                }
                item.node = node
                retained[id] = item
            }
            var changed = Set(items.keys) != Set(retained.keys)
            for item in retained.values {
                let children = item.node.children.compactMap { id in
                    overview.pinned.contains(id) ? nil : retained[id]
                }
                if item.children.map(\.node.id) != children.map(\.node.id) { changed = true }
                item.children = children
            }
            let nextRoots = overview.topLevel.compactMap { retained[$0] }
            if roots.map(\.node.id) != nextRoots.map(\.node.id) { changed = true }
            items = retained
            roots = nextRoots
            func assignDepth(_ item: Item, depth: Int) {
                item.depth = depth
                for child in item.children { assignDepth(child, depth: depth + 1) }
            }
            for root in roots { assignDepth(root, depth: 0) }
            return changed
        }

        private func restoreDisclosure(_ item: Item, overview: ContributorOverview) {
            guard let outline, !item.children.isEmpty else { return }
            if overview.isExpanded(item.node.id) {
                if !outline.isItemExpanded(item) { outline.expandItem(item) }
                for child in item.children { restoreDisclosure(child, overview: overview) }
            } else if outline.isItemExpanded(item) {
                outline.collapseItem(item)
            }
        }

        private func refreshCells() {
            guard let outline else { return }
            let range = outline.rows(in: outline.visibleRect)
            guard range.location != NSNotFound else { return }
            for row in range.location..<min(outline.numberOfRows, NSMaxRange(range)) {
                guard let item = outline.item(atRow: row) as? Item else { continue }
                for (index, column) in MenuBarContributorColumn.allCases.enumerated() {
                    if let view = outline.view(atColumn: index, row: row, makeIfNecessary: false)
                        as? ContributorCell
                    {
                        view.update(configuration.cell(item.node, column))
                    }
                }
            }
        }

        func restoreFocus() {
            guard let outline, let window = outline.window else {
                pendingFocus = configuration.focused
                return
            }
            guard pendingFocus, configuration.focused else { return }
            pendingFocus = false
            window.makeFirstResponder(outline)
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            (item as? Item)?.children.count ?? roots.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            ((item as? Item)?.children ?? roots)[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? Item).map { !$0.children.isEmpty } ?? false
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any)
            -> NSView?
        {
            guard let item = item as? Item, let identifier = tableColumn?.identifier,
                let column = MenuBarContributorColumn(rawValue: identifier.rawValue)
            else { return nil }
            let view =
                outlineView.makeView(withIdentifier: identifier, owner: self) as? ContributorCell
                ?? ContributorCell(frame: .zero)
            view.identifier = identifier
            view.update(configuration.cell(item.node, column))
            return view
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            guard let item = item as? Item, let column = outlineView.outlineTableColumn else { return 44 }
            let width = max(40, column.width - CGFloat(item.depth) * outlineView.indentationPerLevel - 20)
            let overview = configuration.overview
            let key = Item.HeightKey(
                label: item.node.label, width: width,
                count: item.node.stats.current.count, available: item.node.stats.currentAvailable,
                pinned: overview.pinned.contains(item.node.id))
            if item.heightKey != key {
                item.heightKey = key
                item.height = configuration.height(item.node, width)
            }
            return item.height
        }

        func outlineViewColumnDidResize(_ notification: Notification) {
            guard let outline, !applying else { return }
            outline.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<outline.numberOfRows))
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !applying, acceptsInteraction, let outline, outline.selectedRow >= 0,
                let item = outline.item(atRow: outline.selectedRow) as? Item
            else { return }
            configuration.model.report.overview.select(item.node.id)
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            disclosed(notification, expanded: true)
        }
        func outlineViewItemDidCollapse(_ notification: Notification) {
            disclosed(notification, expanded: false)
        }

        private func disclosed(_ notification: Notification, expanded: Bool) {
            guard !applying, acceptsInteraction, let item = notification.userInfo?["NSObject"] as? Item,
                items[item.node.id] === item
            else { return }
            configuration.model.report.overview.setDisclosure(expanded: expanded, for: item.node.id)
        }

        func handleKey(_ event: NSEvent) -> Bool {
            guard acceptsInteraction else { return true }
            if let special = event.specialKey {
                switch special {
                case .upArrow, .downArrow, .leftArrow, .rightArrow:
                    return configuration.model.report.overview.detailsVisible
                default: return false
                }
            }
            guard let key = event.charactersIgnoringModifiers else { return false }
            var modifiers: EventModifiers = []
            if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
            if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
            if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
            if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
            guard MenuBarKeyboard.accepts(key, modifiers: modifiers) else { return false }
            if key == "q" {
                NSApplication.shared.terminate(nil)
                return true
            }
            return configuration.model.handleShortcut(key, row: nil)
        }

        func menu(for event: NSEvent) -> NSMenu? {
            guard acceptsInteraction, let outline else { return nil }
            let row = outline.row(at: outline.convert(event.locationInWindow, from: nil))
            guard row >= 0, let item = outline.item(atRow: row) as? Item else { return nil }
            let menu = NSMenu()
            for (title, action) in [
                ("Details…", #selector(inspect(_:))), ("Pin / unpin session", #selector(pin(_:))),
            ] {
                let command = NSMenuItem(title: title, action: action, keyEquivalent: "")
                command.target = self
                command.representedObject = item
                menu.addItem(command)
            }
            return menu
        }

        private func target(_ sender: NSMenuItem) -> ContributorID? {
            guard acceptsInteraction, let item = sender.representedObject as? Item,
                items[item.node.id] === item,
                configuration.model.report.overview.visibleRows.contains(where: { $0.id == item.node.id })
            else { return nil }
            return item.node.id
        }

        @objc private func inspect(_ sender: NSMenuItem) {
            guard let id = target(sender) else { return }
            configuration.model.report.overview.select(id)
            if !configuration.model.report.overview.detailsVisible {
                configuration.model.report.overview.toggleDetails()
            }
        }

        @objc private func pin(_ sender: NSMenuItem) {
            guard let id = target(sender) else { return }
            configuration.model.report.overview.select(id)
            configuration.model.report.overview.togglePin()
        }
    }
}

@MainActor private final class Item: NSObject {
    struct HeightKey: Equatable {
        let label: ContributorLabel
        let width: CGFloat
        let count: Int
        let available: Bool
        let pinned: Bool
    }

    var node: ContributorNode
    var children: [Item] = []
    var depth = 0
    var heightKey: HeightKey?
    var height: CGFloat = 44
    init(_ node: ContributorNode) { self.node = node }
}

@MainActor final class ContributorOutlineView: NSOutlineView {
    var keyHandler: ((NSEvent) -> Bool)?
    var focusChanged: ((Bool) -> Void)?
    var contextMenu: ((NSEvent) -> NSMenu?)?
    var mounted: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        mounted?()
    }
    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) != true { super.keyDown(with: event) }
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusChanged?(true) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { focusChanged?(false) }
        return accepted
    }
    override func menu(for event: NSEvent) -> NSMenu? { contextMenu?(event) }
}

@MainActor private final class ContributorCell: NSTableCellView {
    private let hosting = NSHostingView(rootView: AnyView(EmptyView()))
    private var content = AnyView(EmptyView())

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { if oldValue != backgroundStyle { update(content) } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { return nil }

    func update(_ content: AnyView) {
        self.content = content
        hosting.rootView = AnyView(
            content.environment(
                \.backgroundProminence, backgroundStyle == .emphasized ? .increased : .standard))
    }
}

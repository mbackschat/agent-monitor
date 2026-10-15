import AppKit

enum MenuBarActivation {
    case panel, contextMenu

    init(eventType: NSEvent.EventType?, modifiers: NSEvent.ModifierFlags) {
        switch eventType {
        case .rightMouseUp: self = .contextMenu
        case .leftMouseUp where modifiers.contains(.control): self = .contextMenu
        default: self = .panel
        }
    }
}

@MainActor final class MenuBarStatusMenu: NSObject {
    enum Action { case open, quit }

    private let model: MenuBarModel
    private let options: MenuBarOptionsController
    private(set) var selectedAction: Action?

    init(model: MenuBarModel) {
        self.model = model
        options = MenuBarOptionsController(model: model, placement: .submenu)
    }

    func makeMenu() -> NSMenu {
        selectedAction = nil
        let menu = NSMenu(title: "Agent Monitor")
        menu.autoenablesItems = false
        let lines =
            model.liveIcon
            ? model.indicator.statusLines + ["Closed-panel sampling: every 15 seconds"]
            : ["Agent Monitor", "Live icon is off; sampling only while the panel is open"]
        for (index, line) in lines.enumerated() {
            let item =
                index == 0
                ? NSMenuItem.sectionHeader(title: line)
                : NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        add("Open Agent Monitor", action: .open, to: menu)
        let settings = NSMenuItem(title: "View options", action: nil, keyEquivalent: "")
        settings.submenu = options.makeMenu()
        menu.addItem(settings)
        menu.addItem(.separator())
        add("Quit Agent Monitor", action: .quit, to: menu)
        return menu
    }

    private func add(_ title: String, action: Action, to menu: NSMenu) {
        let item = NSMenuItem(
            title: title, action: #selector(selectAction(_:)), keyEquivalent: action == .quit ? "q" : "")
        item.target = self
        item.representedObject = action
        menu.addItem(item)
    }

    @objc private func selectAction(_ item: NSMenuItem) {
        // The host executes after menu tracking ends, so dismissal cannot close a newly opened popover.
        selectedAction = item.representedObject as? Action
    }
}

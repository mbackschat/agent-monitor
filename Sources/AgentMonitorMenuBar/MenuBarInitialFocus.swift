import AgentMonitorPresentation

enum MenuBarFocus: Hashable {
    case table
    case row(LiveReportRowID)
    case pin(LiveReportRowID)

    var rowID: LiveReportRowID? {
        switch self {
        case .row(let id), .pin(let id): id
        case .table: nil
        }
    }
}

struct MenuBarInitialFocus {
    private var waitingForRows = false

    mutating func open(rows: [LiveReportRowID]) -> MenuBarFocus {
        waitingForRows = rows.isEmpty
        return rows.first.map(MenuBarFocus.row) ?? .table
    }

    mutating func rowsChanged(_ rows: [LiveReportRowID], focus: MenuBarFocus?) -> LiveReportRowID? {
        guard waitingForRows else { return nil }
        guard focus == .table else {
            waitingForRows = false
            return nil
        }
        guard let first = rows.first else { return nil }
        waitingForRows = false
        return first
    }
}

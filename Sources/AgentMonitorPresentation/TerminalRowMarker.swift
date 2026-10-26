enum TerminalRowMarker {
    static func selection(_ selected: Bool) -> String { selected ? ">" : " " }

    static func text(selected: Bool, pinned: Bool) -> String {
        selection(selected) + (pinned ? "★" : " ")
    }
}

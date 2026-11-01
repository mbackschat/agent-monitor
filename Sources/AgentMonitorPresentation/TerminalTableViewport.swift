struct TableScrollAnchor<ID: Equatable & Sendable>: Equatable, Sendable {
    let id: ID
    let lineOffset: Int
}

struct TerminalTableViewport<ID: Equatable & Sendable> {
    let ids: [ID]
    let offsets: [Int]
    let capacity: Int
    let start: Int
    let selected: Int?

    init(ids: [ID], heights: [Int], capacity: Int, anchor: TableScrollAnchor<ID>?, selection: ID?) {
        self.ids = ids
        self.capacity = max(0, capacity)
        var offsets = [0]
        for height in heights.prefix(ids.count) { offsets.append(offsets.last! + height) }
        self.offsets = offsets
        selected = ids.firstIndex { $0 == selection }
        var start = 0
        if let anchor, let index = ids.firstIndex(of: anchor.id) {
            start = offsets[index] + min(max(0, anchor.lineOffset), max(0, heights[index] - 1))
        } else if let selected {
            start = offsets[selected]
            for index in (0..<selected).reversed() {
                guard offsets[selected + 1] - offsets[index] <= self.capacity else { break }
                start = offsets[index]
            }
        }
        if let selected, self.capacity > 0 {
            if offsets[selected] < start { start = offsets[selected] }
            if offsets[selected + 1] > start + self.capacity {
                start = min(offsets[selected], offsets[selected + 1] - self.capacity)
            }
        }
        self.start = min(max(0, start), max(0, (offsets.last ?? 0) - self.capacity))
    }

    var total: Int { offsets.last ?? 0 }
    var end: Int { min(total, start + capacity) }
    var scrolls: Bool { total > capacity && capacity > 0 }
    var visibleRows: Range<Int> {
        guard capacity > 0 else { return 0..<0 }
        let first = ids.indices.first { offsets[$0 + 1] > start } ?? ids.count
        let last = ids.indices.last { offsets[$0] < end }.map { $0 + 1 } ?? first
        return first..<max(first, last)
    }
    var anchor: TableScrollAnchor<ID>? { anchor(at: start) }

    private func anchor(at line: Int) -> TableScrollAnchor<ID>? {
        guard let index = ids.indices.last(where: { offsets[$0] <= line }) else { return nil }
        return TableScrollAnchor(id: ids[index], lineOffset: line - offsets[index])
    }

    var position: String {
        guard !visibleRows.isEmpty, scrolls else { return "" }
        return (start > 0 ? "↑ " : "")
            + "\(visibleRows.lowerBound + 1)–\(visibleRows.upperBound)/\(ids.count)"
            + (end < total ? " ↓" : "")
    }

    func page(direction: Int, half: Bool) -> (anchor: TableScrollAnchor<ID>?, selection: ID)? {
        guard let selected, capacity > 0 else { return nil }
        let step = max(1, capacity / (half ? 2 : 1))
        let next = min(max(0, start + direction * step), max(0, total - capacity))
        let target = next + max(0, offsets[selected] - start)
        let complete = ids.indices.filter { offsets[$0] >= next && offsets[$0 + 1] <= next + capacity }
        let candidates =
            complete.isEmpty
            ? ids.indices.filter { offsets[$0 + 1] > next && offsets[$0] < next + capacity }
            : complete
        guard let index = candidates.min(by: { abs(offsets[$0] - target) < abs(offsets[$1] - target) }) else {
            return nil
        }
        let destination: Int
        if next == start {
            destination = min(
                candidates.last ?? index, max(candidates.first ?? index, selected + direction * step))
        } else if index == selected && !complete.contains(selected) {
            // Keeping the clipped selection would snap back when one block fills the pane; see
            // halfPageAdvancesWhenOnlyOneCompleteContributorFits.
            destination = min(ids.count - 1, max(0, selected + direction))
        } else {
            destination = index
        }
        return (anchor(at: next), ids[destination])
    }

    func decorate(_ body: [ReportLine], width: Int) -> [ReportLine] {
        guard scrolls, capacity >= 3 else { return body }
        let track = capacity - 2
        let thumb = max(1, min(track, track * capacity / max(1, total)))
        let top = (track - thumb) * start / max(1, total - capacity)
        return body.enumerated().map { index, line in
            let glyph: String
            switch index {
            case 0: glyph = start > 0 ? "↑" : "│"
            case capacity - 1: glyph = end < total ? "↓" : "│"
            default: glyph = (top..<(top + thumb)).contains(index - 1) ? "█" : "│"
            }
            let content = line.clipped(to: max(0, width - 2))
            return ReportLine(
                runs: content.runs + [
                    .init(
                        String(repeating: " ", count: max(1, width - TerminalCells.width(content.text) - 1))),
                    .init(glyph, style: glyph == "█" ? .heading : .muted),
                ], style: line.style)
        }
    }
}

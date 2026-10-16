/// Terminal geometry for sanitized display text, without a UI-framework dependency.
public enum TerminalCells {
    public static func width(_ text: String) -> Int {
        text.reduce(0) { $0 + width($1) }
    }

    // Match the pinned renderer rather than locale-dependent wcwidth results.
    // Classification adapted from SwiftTUI 0.14.0 TextCellWidth.swift; MIT notice
    // and exact source revision are in THIRD_PARTY_NOTICES.md.
    public static func width(_ character: Character) -> Int {
        let scalars = character.unicodeScalars
        if let first = scalars.first, first.isASCII, scalars.count == 1 {
            return first.value == 0 ? 0 : 1
        }
        let wide = scalars.contains { scalar in
            switch scalar.value {
            case 0x1100...0x115F, 0x2329...0x232A, 0x2E80...0xA4CF, 0xAC00...0xD7A3,
                0xF900...0xFAFF, 0xFE10...0xFE19, 0xFE30...0xFE6F, 0xFF00...0xFF60,
                0xFFE0...0xFFE6, 0x1F300...0x1FAFF, 0x20000...0x3FFFD:
                return true
            default: return false
            }
        }
        let zero = scalars.allSatisfy { scalar in
            if scalar.value == 0 { return true }
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .enclosingMark, .format: return true
            default: return false
            }
        }
        if scalars.contains(where: { $0.value == 0xFE0E }) { return wide ? 2 : zero ? 0 : 1 }
        if wide || scalars.contains(where: { $0.properties.isEmojiPresentation })
            || (scalars.count > 1 && scalars.contains(where: { $0.properties.isEmoji }))
        {
            return 2
        }
        return zero ? 0 : 1
    }

    public static func clipped(_ text: String, to columns: Int) -> String {
        guard columns > 0 else { return "" }
        var used = 0
        return String(
            text.prefix { character in
                used += width(character)
                return used <= columns
            })
    }

    static func padded(_ text: String, to columns: Int) -> String {
        let result = clipped(text, to: columns)
        return result + String(repeating: " ", count: max(0, columns - width(result)))
    }

    static func abbreviated(_ text: String, to columns: Int) -> String {
        guard width(text) > columns else { return text }
        return columns > 0 ? clipped(text, to: columns - 1) + "…" : ""
    }

    static func wrapped(_ text: String, to columns: Int) -> [String] {
        guard columns > 0 else { return [] }
        if text.isEmpty { return [""] }
        var rows: [String] = []
        var row = ""
        var used = 0
        for character in text {
            let cells = width(character)
            if used + cells > columns && !row.isEmpty {
                rows.append(row)
                row = ""
                used = 0
            }
            // A one-cell viewport cannot show half a wide cluster.
            row.append(cells > columns ? "�" : character)
            used += min(cells, columns)
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }
}

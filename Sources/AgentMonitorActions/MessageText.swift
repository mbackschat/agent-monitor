import Foundation

extension MessageDraft {
    public static let maximumUTF8Bytes = 64 * 1024

    /// Admit complete pasted graphemes before retaining them. The byte allowance also bounds
    /// incremental combining marks, which do not consume the character allowance (storage audit,
    /// docs/research/menu-bar-load-cost.md#retained-state-ownership-audit--2026-10-26).
    public static func appending(_ input: String, to current: String) -> (text: String, notice: String?) {
        var result = current
        var remaining = maximumUTF8Bytes - current.utf8.count
        var index = input.startIndex
        var notice: String?
        while index < input.endIndex {
            let next = input.index(after: index)
            var piece = ""
            var bytes = 0
            var fits = true
            for scalar in input[index..<next].unicodeScalars {
                guard !CharacterSet.controlCharacters.contains(scalar) || scalar == "\n" else { continue }
                let size: Int
                switch scalar.value {
                case ...0x7f: size = 1
                case ...0x7ff: size = 2
                case ...0xffff: size = 3
                default: size = 4
                }
                guard bytes + size <= remaining else {
                    fits = false
                    break
                }
                piece.unicodeScalars.append(scalar)
                bytes += size
            }
            guard fits else {
                notice = "64 KiB limit; extra text ignored."
                break
            }
            result += piece
            remaining -= bytes
            index = next
        }
        if result.count > maximumLength {
            result = String(result.prefix(maximumLength))
            notice = "4,000 character limit; extra text ignored."
        }
        return (result, notice)
    }
}
